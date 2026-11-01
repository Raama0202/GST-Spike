"""One-time codes for employee login (SMS or email), firm sign-up and password reset."""
from datetime import timedelta
from hmac import compare_digest
from secrets import randbelow

from fastapi import HTTPException
from pymongo import DESCENDING, ReturnDocument
from pymongo.asynchronous.database import AsyncDatabase

from app.core.config import settings
from app.core.ratelimit import enforce
from app.core.security import hash_otp
from app.db.mongo import stamp, utcnow
from app.models import OtpPurpose
from app.services.email import EmailUnavailable, send_otp_email
from app.services.sms import SMSUnavailable, send_otp

MAX_ATTEMPTS = 5
MAX_PER_10_MIN = 5
MAX_VERIFY_PER_HOUR = 15


def mask_email(email: str) -> str:
    local, _, domain = email.partition("@")
    visible = local[:2] if len(local) > 2 else local[:1]
    return f"{visible}{'*' * max(len(local) - len(visible), 1)}@{domain}"


def mask_mobile(mobile: str) -> str:
    digits = "".join(ch for ch in mobile if ch.isdigit())
    return f"{'*' * max(len(digits) - 4, 0)}{digits[-4:]}"


def _scope(purpose: OtpPurpose, target: str) -> str:
    return f"{purpose.value}:{target}"


async def create_challenge(
    db: AsyncDatabase,
    target: str,
    *,
    purpose: OtpPurpose = OtpPurpose.login,
    channel: str = "sms",
    destination: str | None = None,
    demo_code: str | None = None,
) -> None:
    """Store a hashed code for `target` and deliver it over `channel` ("sms" | "email")
    to `destination` (defaults to `target`)."""
    if demo_code is None:
        if channel == "email" and not settings.email_configured:
            raise EmailUnavailable()
        if channel == "sms" and not settings.sms_configured:
            raise SMSUnavailable()
    now = utcnow()
    recent = await db.otp_challenges.count_documents(
        {"purpose": purpose.value, "target": target, "created_at": {"$gte": now - timedelta(minutes=10)}}
    )
    if recent >= MAX_PER_10_MIN:
        raise HTTPException(429, "Too many codes requested; try again in a few minutes")
    code = demo_code or settings.fixed_otp or f"{randbelow(1_000_000):06d}"
    challenge = stamp(
        {
            "purpose": purpose.value,
            "target": target,
            "code_hash": hash_otp(code, _scope(purpose, target)),
            "expires_at": now + timedelta(minutes=settings.otp_ttl_minutes),
            "consumed_at": None,
            "attempts": 0,
            "created_at": now,
        },
        timestamps=False,
    )
    await db.otp_challenges.insert_one(challenge)
    if demo_code is not None:
        return
    try:
        if channel == "email":
            await send_otp_email(destination or target, code, purpose.value)
        else:
            await send_otp(destination or target, code)
    except Exception:
        await db.otp_challenges.delete_one({"_id": challenge["_id"]})
        raise


async def verify_challenge(db: AsyncDatabase, target: str, code: str, *, purpose: OtpPurpose = OtpPurpose.login) -> bool:
    # Caps guesses across every code issued to this target, not just the latest one.
    await enforce(f"otp-verify:{purpose.value}:{target}", MAX_VERIFY_PER_HOUR, 3600, "Too many incorrect codes; try again later")
    latest = await db.otp_challenges.find_one(
        {"purpose": purpose.value, "target": target, "consumed_at": None},
        {"_id": 1},
        sort=[("created_at", DESCENDING)],
    )
    if not latest:
        return False
    now = utcnow()
    # Count the attempt before comparing so parallel guesses can't all pass the limit.
    challenge = await db.otp_challenges.find_one_and_update(
        {"_id": latest["_id"], "consumed_at": None, "attempts": {"$lt": MAX_ATTEMPTS}, "expires_at": {"$gt": now}},
        {"$inc": {"attempts": 1}},
        return_document=ReturnDocument.AFTER,
    )
    if not challenge or not compare_digest(challenge["code_hash"], hash_otp(code, _scope(purpose, target))):
        return False
    consumed = await db.otp_challenges.update_one(
        {"_id": challenge["_id"], "consumed_at": None}, {"$set": {"consumed_at": now}}
    )
    return consumed.modified_count == 1


async def purge_expired(db: AsyncDatabase) -> int:
    result = await db.otp_challenges.delete_many({"expires_at": {"$lt": utcnow() - timedelta(days=1)}})
    return result.deleted_count
