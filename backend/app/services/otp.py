from hmac import compare_digest
from datetime import datetime, timedelta, timezone
from secrets import randbelow

from fastapi import HTTPException
from sqlalchemy import delete, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.security import hash_otp
from app.models import OTPChallenge
from app.services.sms import SMSUnavailable, send_otp


async def create_challenge(db: AsyncSession, mobile: str) -> None:
    demo_code = settings.demo_otp_for(mobile)
    if demo_code is None and not settings.sms_configured:
        raise SMSUnavailable()
    now = datetime.now(timezone.utc)
    recent = await db.scalar(
        select(func.count(OTPChallenge.id)).where(
            OTPChallenge.mobile == mobile,
            OTPChallenge.created_at >= now - timedelta(minutes=10),
        )
    )
    if recent >= 5:
        raise HTTPException(429, "Too many OTP requests; try again later")
    code = demo_code or settings.fixed_otp or f"{randbelow(1_000_000):06d}"
    challenge = OTPChallenge(mobile=mobile, code_hash=hash_otp(code), expires_at=now + timedelta(minutes=5))
    db.add(challenge)
    await db.flush()
    if demo_code is None:
        try:
            await send_otp(mobile, code)
        except Exception:
            await db.rollback()
            raise
    await db.commit()


async def verify_challenge(db: AsyncSession, mobile: str, code: str) -> bool:
    challenge = await db.scalar(
        select(OTPChallenge)
        .where(OTPChallenge.mobile == mobile, OTPChallenge.consumed_at.is_(None))
        .order_by(OTPChallenge.created_at.desc())
        .limit(1)
    )
    now = datetime.now(timezone.utc)
    if not challenge or challenge.expires_at.replace(tzinfo=timezone.utc) < now or challenge.attempts >= 5:
        return False
    challenge.attempts += 1
    if not compare_digest(challenge.code_hash, hash_otp(code)):
        await db.commit()
        return False
    challenge.consumed_at = now
    await db.commit()
    return True


async def purge_expired(db: AsyncSession) -> int:
    result = await db.execute(delete(OTPChallenge).where(OTPChallenge.expires_at < datetime.now(timezone.utc) - timedelta(days=1)))
    await db.commit()
    return result.rowcount or 0
