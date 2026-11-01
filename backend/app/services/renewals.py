"""Subscription renewal reminder emails (N days before expiry, and on expiry)."""
import asyncio
import logging
import math
from datetime import timedelta

from pymongo.asynchronous.database import AsyncDatabase

from app.core.config import settings
from app.db.mongo import as_utc, utcnow
from app.models import CompanyStatus, Role, SubscriptionStatus
from app.services.reports import IST

logger = logging.getLogger(__name__)

EXPIRED_GRACE_DAYS = 3
INTERVAL_SECONDS = 3600


def reminder_key(days_left: int, ends_at) -> str | None:
    """Most urgent threshold reached; the end date is part of the key so a renewal starts afresh."""
    stamp = as_utc(ends_at).date().isoformat()
    if days_left <= 0:
        return f"expired:{stamp}"
    due = [d for d in settings.renewal_reminder_day_list if days_left <= d]
    return f"{min(due)}d:{stamp}" if due else None


def _message(company: dict, days_left: int, ends_at) -> tuple[str, str]:
    brand = settings.business_name
    link = f"{settings.public_web_url.rstrip('/')}/#/billing" if settings.public_web_url else "the Billing page of your admin console"
    when = as_utc(ends_at).astimezone(IST).strftime("%d %b %Y")
    if days_left <= 0:
        subject = f"Your {brand} subscription has expired"
        lead = (f"The {brand} subscription for {company['name']} ended on {when}. Your admins and employees "
                "can no longer upload or review bills until it is renewed.")
    else:
        subject = f"Your {brand} subscription ends in {days_left} day{'s' if days_left != 1 else ''}"
        lead = (f"The {brand} subscription for {company['name']} ends on {when}. Renew now so your team "
                "keeps scanning and approving bills without interruption.")
    body = "\n".join([lead, "", f"Renew in a minute with UPI, card or net banking: {link}", "",
                      "Bills, employees and reports are kept safe while you renew.", "", f"- {brand}"])
    return subject, body


async def send_renewal_reminders(db: AsyncDatabase) -> int:
    if not settings.email_configured or not settings.renewal_reminder_day_list:
        return 0
    from app.services.email import send_email

    now = utcnow()
    horizon = now + timedelta(days=max(settings.renewal_reminder_day_list))
    sent = 0
    # Latest subscription per company only: an older expired one must not trigger "expired".
    latest = await (await db.subscriptions.aggregate([
        {"$match": {"ends_at": {"$gte": now - timedelta(days=EXPIRED_GRACE_DAYS)}}},
        {"$sort": {"ends_at": -1}},
        {"$group": {"_id": "$company_id", "sub": {"$first": "$$ROOT"}}},
    ])).to_list(None)
    for row in latest:
        subscription = row["sub"]
        ends_at = as_utc(subscription["ends_at"])
        if ends_at > horizon or subscription.get("status") == SubscriptionStatus.cancelled.value:
            continue
        days_left = math.ceil((ends_at - now).total_seconds() / 86400)
        key = reminder_key(days_left, ends_at)
        if not key:
            continue
        company = await db.companies.find_one({"_id": subscription["company_id"]}, {"name": 1, "status": 1})
        if not company or company.get("status") not in (CompanyStatus.active.value, CompanyStatus.pending.value):
            continue
        # Claim before sending so parallel workers never email twice.
        claim = await db.subscriptions.update_one(
            {"_id": subscription["_id"], "reminders_sent": {"$ne": key}}, {"$addToSet": {"reminders_sent": key}}
        )
        if not claim.modified_count:
            continue
        subject, body = _message(company, days_left, ends_at)
        async for admin in db.users.find(
            {"company_id": company["_id"], "role": Role.company_admin.value, "is_active": {"$ne": False}}, {"email": 1}
        ):
            if not admin.get("email"):
                continue
            try:
                await send_email(admin["email"], subject, body)
                sent += 1
            except Exception as exc:  # noqa: BLE001
                logger.warning("Renewal reminder to %s failed: %s", admin["email"], exc)
    if sent:
        logger.info("Sent %s renewal reminder email(s)", sent)
    return sent


async def reminder_loop(db: AsyncDatabase) -> None:
    await asyncio.sleep(90)
    while True:
        try:
            await send_renewal_reminders(db)
        except Exception:  # noqa: BLE001
            logger.exception("Renewal reminder run failed")
        await asyncio.sleep(INTERVAL_SECONDS)
