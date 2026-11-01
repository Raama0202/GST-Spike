"""Insert test documents with the same shape the API writes."""
from datetime import timedelta
from decimal import Decimal

from app.core.security import hash_password
from app.db.mongo import new_id, utcnow
from app.models import CompanyStatus, Role, SubscriptionStatus
from app.services.companies import company_doc


async def plan(db, code="starter", name="Starter", price=999, max_employees=10) -> dict:
    doc = {"_id": new_id(), "code": code, "name": name, "monthly_price_inr": Decimal(str(price)),
           "max_employees": max_employees, "features_json": {}, "created_at": utcnow()}
    await db.subscription_plans.insert_one(doc)
    return doc


async def company(db, name="Test Company", *, status=CompanyStatus.active, activation_code=None, **fields) -> dict:
    doc = company_doc(name, status=status, activation_code=activation_code,
                      gstin=fields.pop("gstin", None), legal_name=fields.pop("legal_name", None))
    doc.update(fields)
    await db.companies.insert_one(doc)
    return doc


async def branch(db, company_id, name="HQ", code="HQ") -> dict:
    doc = {"_id": new_id(), "company_id": company_id, "name": name, "code": code, "is_active": True,
           "created_at": utcnow(), "updated_at": utcnow()}
    await db.branches.insert_one(doc)
    return doc


async def category(db, company_id, name="Cement", sort_order=1) -> dict:
    doc = {"_id": new_id(), "company_id": company_id, "name": name, "parent_id": None, "sort_order": sort_order,
           "is_active": True, "created_at": utcnow(), "updated_at": utcnow()}
    await db.expense_categories.insert_one(doc)
    return doc


async def user(db, company_id=None, role=Role.employee, email=None, password=None) -> dict:
    doc = {"_id": new_id(), "company_id": company_id, "role": role.value, "email": email,
           "password_hash": hash_password(password) if password else None, "is_active": True,
           "refresh_token_hash": None, "created_at": utcnow(), "updated_at": utcnow()}
    if email is None:
        doc.pop("email")
    await db.users.insert_one(doc)
    return doc


async def employee(db, company_id, *, branch_id=None, name="Tester", code="E1", mobile="9999999999", email=None) -> dict:
    account = await user(db, company_id, Role.employee)
    doc = {"_id": new_id(), "company_id": company_id, "user_id": account["_id"], "branch_id": branch_id,
           "name": name, "employee_code": code, "mobile": mobile, "email": email, "is_active": True,
           "created_at": utcnow(), "updated_at": utcnow()}
    await db.employees.insert_one(doc)
    return doc


async def subscription(db, company_id, plan_code="starter", seats=10, *, days=30, starts_days_ago=0) -> dict:
    now = utcnow()
    doc = {"_id": new_id(), "company_id": company_id, "plan_code": plan_code, "seats": seats,
           "starts_at": now - timedelta(days=starts_days_ago), "ends_at": now + timedelta(days=days),
           "status": SubscriptionStatus.active.value, "created_at": now}
    await db.subscriptions.insert_one(doc)
    return doc
