import asyncio
from datetime import timedelta
from decimal import Decimal

from pymongo.asynchronous.database import AsyncDatabase

from app.core.config import settings
from app.core.security import hash_password
from app.db.mongo import as_utc, close_client, ensure_indexes, get_database, new_id, utcnow
from app.models import CompanyStatus, Role, SubscriptionStatus
from app.services.companies import company_doc

DEFAULT_PLANS = [
    ("starter", "Starter", Decimal("999"), 10, {"galleryImport": True}),
    ("growth", "Growth", Decimal("2999"), 50, {"galleryImport": True, "analytics": True}),
    ("enterprise", "Enterprise", Decimal("9999"), None, {"allFeatures": True}),
]

DEMO_COMPANY = "Acme Construction"


async def seed_plans(db: AsyncDatabase) -> None:
    """Idempotent: safe to run on every start (self sign-up needs a plan)."""
    for code, name, price, maximum, features in DEFAULT_PLANS:
        await db.subscription_plans.update_one(
            {"code": code},
            {"$setOnInsert": {
                "_id": new_id(), "code": code, "name": name, "monthly_price_inr": price,
                "max_employees": maximum, "features_json": features, "created_at": utcnow(),
            }},
            upsert=True,
        )


async def _active_subscription(db: AsyncDatabase, company_id: str, days: int = 365) -> None:
    now = utcnow()
    latest = await db.subscriptions.find_one(
        {"company_id": company_id, "status": SubscriptionStatus.active.value}, sort=[("ends_at", -1)]
    )
    if latest is None or as_utc(latest["ends_at"]) < now + timedelta(days=30):
        await db.subscriptions.insert_one({
            "_id": new_id(), "company_id": company_id, "plan_code": "growth", "seats": 50,
            "starts_at": now, "ends_at": now + timedelta(days=days),
            "status": SubscriptionStatus.active.value, "created_at": now,
        })


async def seed_demo(db: AsyncDatabase) -> None:
    """Demo tenant with well-known credentials — production only with SEED_DEMO_DATA=true."""
    now = utcnow()
    if not await db.users.find_one({"email": "admin@gstexpenses.app"}, {"_id": 1}):
        await db.users.insert_one({
            "_id": new_id(), "company_id": None, "email": "admin@gstexpenses.app",
            "password_hash": hash_password("ChangeMeNow!123"), "role": Role.super_admin.value,
            "is_active": True, "refresh_token_hash": None, "created_at": now, "updated_at": now,
        })

    existing = await db.companies.find_one({"name": DEMO_COMPANY}, {"_id": 1})
    if existing:
        await _active_subscription(db, existing["_id"])
        return
    company = company_doc(
        DEMO_COMPANY,
        industry="Construction",
        legal_name="Acme Construction Private Limited",
        gstin="37AABCA1234C1ZE",
        status=CompanyStatus.active,
        activation_code="ACME-DEMO-2026",
        features={"galleryImport": True, "remarksRequired": False},
    )
    await db.companies.insert_one(company)
    branch_id = new_id()
    await db.branches.insert_one({
        "_id": branch_id, "company_id": company["_id"], "name": "Site A", "code": "A",
        "is_active": True, "created_at": now, "updated_at": now,
    })
    await db.expense_categories.insert_many([
        {"_id": new_id(), "company_id": company["_id"], "name": name, "parent_id": None,
         "sort_order": i, "is_active": True, "created_at": now, "updated_at": now}
        for i, name in enumerate(("Cement", "Steel", "Diesel"), 1)
    ])
    employee_user_id = new_id()
    await db.users.insert_many([
        {"_id": new_id(), "company_id": company["_id"], "email": "acme@demo.com",
         "password_hash": hash_password("DemoAdmin!123"), "role": Role.company_admin.value,
         "is_active": True, "refresh_token_hash": None, "created_at": now, "updated_at": now},
        {"_id": employee_user_id, "company_id": company["_id"], "role": Role.employee.value,
         "is_active": True, "refresh_token_hash": None, "created_at": now, "updated_at": now},
    ])
    await db.employees.insert_one({
        "_id": new_id(), "company_id": company["_id"], "user_id": employee_user_id, "branch_id": branch_id,
        "name": "Demo Employee", "employee_code": "EMP001", "mobile": "9999999999", "email": None,
        "is_active": True, "created_at": now, "updated_at": now,
    })
    await _active_subscription(db, company["_id"])


async def seed() -> None:
    db = get_database()
    try:
        await ensure_indexes(db)
        await seed_plans(db)
        demo = not settings.is_production or settings.seed_demo_data
        if demo:
            await seed_demo(db)
    finally:
        await close_client()
    print("Seed data is ready." + ("" if demo else " (plans only — production)"))


if __name__ == "__main__":
    asyncio.run(seed())
