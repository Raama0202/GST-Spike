import asyncio
from datetime import datetime, timedelta, timezone
from decimal import Decimal

from sqlalchemy import select

from app.core.config import settings
from app.core.security import hash_password
from app.db.session import SessionLocal
from app.models import (
    Branch,
    Company,
    CompanyStatus,
    Employee,
    ExpenseCategory,
    Role,
    Subscription,
    SubscriptionPlan,
    SubscriptionStatus,
    User,
)

DEFAULT_PLANS = [
    ("starter", "Starter", Decimal("999"), 10, {"galleryImport": True}),
    ("growth", "Growth", Decimal("2999"), 50, {"galleryImport": True, "analytics": True}),
    ("enterprise", "Enterprise", Decimal("9999"), None, {"allFeatures": True}),
]


async def seed_plans(db) -> None:
    for code, name, price, maximum, features in DEFAULT_PLANS:
        if not await db.scalar(select(SubscriptionPlan).where(SubscriptionPlan.code == code)):
            db.add(SubscriptionPlan(code=code, name=name, monthly_price_inr=price, max_employees=maximum, features_json=features))
    await db.flush()


async def seed_demo(db) -> None:
    """Demo tenant with well-known credentials — production only with SEED_DEMO_DATA=true."""
    if not await db.scalar(select(User).where(User.email == "admin@gstexpenses.app")):
        db.add(User(email="admin@gstexpenses.app", password_hash=hash_password("ChangeMeNow!123"), role=Role.super_admin))

    now = datetime.now(timezone.utc)
    existing = await db.scalar(select(Company).where(Company.name == "Acme Construction"))
    if existing:
        latest = await db.scalar(
            select(Subscription.ends_at)
            .where(Subscription.company_id == existing.id, Subscription.status == SubscriptionStatus.active)
            .order_by(Subscription.ends_at.desc())
            .limit(1)
        )
        if latest is None or latest.replace(tzinfo=timezone.utc) < now + timedelta(days=30):
            db.add(Subscription(company_id=existing.id, plan_code="growth", seats=50, starts_at=now, ends_at=now + timedelta(days=365), status=SubscriptionStatus.active))
        return
    company = Company(
        name="Acme Construction",
        industry="Construction",
        activation_code="ACME-DEMO-2026",
        status=CompanyStatus.active,
        features_json={"galleryImport": True, "remarksRequired": False},
    )
    db.add(company)
    await db.flush()
    branch = Branch(company_id=company.id, name="Site A", code="A")
    db.add(branch)
    db.add_all([ExpenseCategory(company_id=company.id, name=name, sort_order=i) for i, name in enumerate(("Cement", "Steel", "Diesel"), 1)])
    admin = User(company_id=company.id, email="acme@demo.com", password_hash=hash_password("DemoAdmin!123"), role=Role.company_admin)
    employee_user = User(company_id=company.id, role=Role.employee)
    db.add_all([admin, employee_user])
    await db.flush()
    db.add(Employee(company_id=company.id, user_id=employee_user.id, branch_id=branch.id, name="Demo Employee", employee_code="EMP001", mobile="9999999999"))
    db.add(Subscription(company_id=company.id, plan_code="growth", seats=50, starts_at=now, ends_at=now + timedelta(days=365), status=SubscriptionStatus.active))


async def seed() -> None:
    async with SessionLocal() as db:
        await seed_plans(db)
        demo = not settings.is_production or settings.seed_demo_data
        if demo:
            await seed_demo(db)
        await db.commit()
    print("Seed data is ready." + ("" if demo else " (plans only — production)"))


if __name__ == "__main__":
    asyncio.run(seed())
