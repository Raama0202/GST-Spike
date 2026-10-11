from datetime import datetime, timezone
from uuid import UUID

from fastapi import HTTPException
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.cache import get_json, get_store, set_json
from app.core.config import settings
from app.models import Company, CompanyStatus, Employee, Subscription, SubscriptionStatus


def _company_key(company_id: UUID) -> str:
    return f"sub:{company_id}"


async def invalidate_company(company_id: UUID) -> None:
    """Call after any change to company status or subscriptions."""
    await get_store().delete(_company_key(company_id))


async def require_active_subscription(db: AsyncSession, company_id: UUID) -> Subscription:
    company = await db.get(Company, company_id)
    if not company or company.status != CompanyStatus.active:
        raise HTTPException(403, "Company is not active")
    subscription = await db.scalar(
        select(Subscription)
        .where(
            Subscription.company_id == company_id,
            Subscription.status == SubscriptionStatus.active,
        )
        .order_by(Subscription.ends_at.desc())
        .limit(1)
    )
    if not subscription or subscription.ends_at.replace(tzinfo=timezone.utc) < datetime.now(timezone.utc):
        raise HTTPException(403, "Subscription expired")
    return subscription


async def ensure_company_active(db: AsyncSession, company_id: UUID) -> None:
    """Cached form of require_active_subscription for the per-request auth path."""
    key = _company_key(company_id)
    cached = await get_json(key)
    now = datetime.now(timezone.utc)
    if cached and cached.get("ok") and datetime.fromisoformat(cached["endsAt"]) >= now:
        return
    if cached and not cached.get("ok"):
        raise HTTPException(403, cached.get("message", "Company is not active"))
    try:
        subscription = await require_active_subscription(db, company_id)
    except HTTPException as exc:
        await set_json(key, {"ok": False, "message": exc.detail}, settings.auth_cache_seconds)
        raise
    ends_at = subscription.ends_at.replace(tzinfo=timezone.utc)
    await set_json(key, {"ok": True, "endsAt": ends_at.isoformat()}, settings.auth_cache_seconds)


async def enforce_seat_limit(db: AsyncSession, company_id: UUID) -> None:
    subscription = await require_active_subscription(db, company_id)
    count = await db.scalar(
        select(func.count(Employee.id)).where(
            Employee.company_id == company_id, Employee.is_active.is_(True)
        )
    )
    if count >= subscription.seats:
        raise HTTPException(409, "Subscription seat limit reached")
