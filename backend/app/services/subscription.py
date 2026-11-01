from datetime import datetime

from fastapi import HTTPException
from pymongo import DESCENDING
from pymongo.asynchronous.database import AsyncDatabase

from app.core.cache import get_json, get_store, set_json
from app.core.config import settings
from app.core.errors import COMPANY_INACTIVE, COMPANY_SUSPENDED, SUBSCRIPTION_EXPIRED, ApiError
from app.db.mongo import as_utc, utcnow
from app.models import CompanyStatus, SubscriptionStatus


def _company_key(company_id: str) -> str:
    return f"sub:{company_id}"


async def invalidate_company(company_id: str) -> None:
    """Call after any change to company status or subscriptions."""
    await get_store().delete(_company_key(company_id))


async def latest_subscription(db: AsyncDatabase, company_id: str, *, active_only: bool = False) -> dict | None:
    query: dict = {"company_id": company_id}
    if active_only:
        query["status"] = SubscriptionStatus.active.value
    return await db.subscriptions.find_one(query, sort=[("ends_at", DESCENDING)])


async def require_active_subscription(db: AsyncDatabase, company_id: str) -> dict:
    company = await db.companies.find_one({"_id": company_id}, {"status": 1})
    if company and company.get("status") == CompanyStatus.suspended.value:
        raise ApiError(403, "Company is suspended", COMPANY_SUSPENDED)
    if not company or company.get("status") != CompanyStatus.active.value:
        raise ApiError(403, "Company is not active", COMPANY_INACTIVE)
    subscription = await latest_subscription(db, company_id, active_only=True)
    if not subscription or as_utc(subscription["ends_at"]) < utcnow():
        raise ApiError(403, "Subscription expired", SUBSCRIPTION_EXPIRED)
    return subscription


async def ensure_company_active(db: AsyncDatabase, company_id: str) -> None:
    """Cached form of require_active_subscription for the per-request auth path."""
    key = _company_key(company_id)
    cached = await get_json(key)
    if cached and cached.get("ok") and datetime.fromisoformat(cached["endsAt"]) >= utcnow():
        return
    if cached and not cached.get("ok"):
        raise ApiError(403, cached.get("message", "Company is not active"), cached.get("code", COMPANY_INACTIVE))
    try:
        subscription = await require_active_subscription(db, company_id)
    except ApiError as exc:
        await set_json(key, {"ok": False, "message": exc.detail, "code": exc.code}, settings.auth_cache_seconds)
        raise
    await set_json(key, {"ok": True, "endsAt": as_utc(subscription["ends_at"]).isoformat()}, settings.auth_cache_seconds)


async def seat_usage(db: AsyncDatabase, company_id: str) -> dict:
    subscription = await latest_subscription(db, company_id)
    used = await db.employees.count_documents({"company_id": company_id, "is_active": True})
    return {"used": used, "limit": subscription["seats"] if subscription else 0}


async def enforce_seat_limit(db: AsyncDatabase, company_id: str) -> None:
    subscription = await require_active_subscription(db, company_id)
    count = await db.employees.count_documents({"company_id": company_id, "is_active": True})
    if count >= subscription["seats"]:
        raise HTTPException(409, "Subscription seat limit reached")
