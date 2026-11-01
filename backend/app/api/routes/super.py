import asyncio
import re
import secrets
from datetime import timedelta
from decimal import Decimal
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from pymongo import ReturnDocument
from pymongo.asynchronous.database import AsyncDatabase

from app.core.deps import Principal, invalidate_user, super_principal
from app.core.ratelimit import client_ip, enforce
from app.core.security import hash_password_async
from app.db.mongo import as_utc, get_db, icontains, new_id, paginate, sid, utcnow
from app.models import CompanyStatus, PaymentStatus, Role, SubscriptionStatus
from app.schemas.common import (
    ActivationRequest,
    CompanyCreate,
    CompanyUpdate,
    ExtendSubscription,
    PlanInput,
    SubscriptionChange,
    SuperCompanyDelete,
)
from app.services import gstin as gst
from app.services.audit import audit_json, record_audit
from app.services.companies import EmailTaken, GstinTaken, company_doc, create_company_with_admin, purge_company
from app.services.gstin_verify import check_json, company_gstin_check
from app.services.payments import DAYS_PER_MONTH, order_json
from app.services.reports import day_bucket, ist_last_days
from app.services.subscription import invalidate_company, latest_subscription

router = APIRouter()
public_router = APIRouter()

EXPIRING_DAYS = 14
METRIC_DAYS = 30


def plan_json(plan: dict, subscribers: int | None = None) -> dict:
    item = {
        "id": plan["_id"],
        "code": plan["code"],
        "name": plan["name"],
        "monthlyPriceInr": plan["monthly_price_inr"],
        "maxEmployees": plan.get("max_employees"),
        "features": plan.get("features_json") or {},
    }
    if subscribers is not None:
        item["subscriberCount"] = subscribers
    return item


def _plan_fields(body: PlanInput) -> dict:
    return {
        "code": body.code,
        "name": body.name,
        "monthly_price_inr": body.monthly_price_inr,
        "max_employees": body.max_employees,
        "features_json": body.features,
    }


async def _subscriber_counts(db: AsyncDatabase) -> dict[str, int]:
    return {
        row["_id"]: row["count"]
        async for row in await db.subscriptions.aggregate([
            {"$match": {"status": SubscriptionStatus.active.value, "ends_at": {"$gte": utcnow()}}},
            {"$group": {"_id": "$plan_code", "count": {"$sum": 1}}},
        ])
    }


@router.get("/plans")
async def plans(_: Principal = Depends(super_principal), db: AsyncDatabase = Depends(get_db)):
    rows = await db.subscription_plans.find().sort([("monthly_price_inr", 1), ("_id", 1)]).to_list(None)
    counts = await _subscriber_counts(db)
    return {"items": [plan_json(x, counts.get(x["code"], 0)) for x in rows]}


@router.post("/plans", status_code=201)
async def create_plan(body: PlanInput, principal: Principal = Depends(super_principal), db: AsyncDatabase = Depends(get_db)):
    if await db.subscription_plans.find_one({"code": body.code}, {"_id": 1}):
        raise HTTPException(409, "Plan code exists")
    plan = {"_id": new_id(), **_plan_fields(body), "created_at": utcnow()}
    await db.subscription_plans.insert_one(plan)
    await record_audit(db, principal, "plan.created", "plan", plan["_id"], f"Created plan {body.name} ({body.code})", company_id=None)
    return plan_json(plan, 0)


@router.put("/plans/{plan_id}")
async def update_plan(plan_id: UUID, body: PlanInput, principal: Principal = Depends(super_principal), db: AsyncDatabase = Depends(get_db)):
    existing = await db.subscription_plans.find_one({"_id": sid(plan_id)})
    if not existing:
        raise HTTPException(404, "Plan not found")
    if body.code != existing["code"]:
        if await db.subscriptions.find_one({"plan_code": existing["code"]}, {"_id": 1}):
            raise HTTPException(409, "This plan's code cannot change while companies are subscribed to it")
        if await db.subscription_plans.find_one({"code": body.code, "_id": {"$ne": existing["_id"]}}, {"_id": 1}):
            raise HTTPException(409, "Plan code exists")
    plan = await db.subscription_plans.find_one_and_update(
        {"_id": existing["_id"]}, {"$set": _plan_fields(body)}, return_document=ReturnDocument.AFTER
    )
    await record_audit(db, principal, "plan.updated", "plan", plan["_id"], f"Updated plan {body.name} ({body.code})", company_id=None)
    counts = await _subscriber_counts(db)
    return plan_json(plan, counts.get(plan["code"], 0))


@router.delete("/plans/{plan_id}", status_code=204)
async def delete_plan(plan_id: UUID, principal: Principal = Depends(super_principal), db: AsyncDatabase = Depends(get_db)):
    plan = await db.subscription_plans.find_one({"_id": sid(plan_id)})
    if not plan:
        raise HTTPException(404, "Plan not found")
    if await db.subscriptions.find_one({"plan_code": plan["code"]}, {"_id": 1}):
        raise HTTPException(409, "Plan is assigned to subscriptions")
    await db.subscription_plans.delete_one({"_id": plan["_id"]})
    await record_audit(db, principal, "plan.deleted", "plan", plan["_id"], f"Deleted plan {plan['name']} ({plan['code']})", company_id=None)


@router.post("/companies", status_code=201)
async def create_company(body: CompanyCreate, principal: Principal = Depends(super_principal), db: AsyncDatabase = Depends(get_db)):
    plan = await db.subscription_plans.find_one({"code": body.plan_code})
    if not plan:
        raise HTTPException(400, "Unknown plan")
    if plan.get("max_employees") is not None and body.seats > plan["max_employees"]:
        raise HTTPException(400, "Seats exceed plan maximum")
    gstin_check = await company_gstin_check(body.gstin)
    company = company_doc(
        body.name, industry=body.industry, legal_name=body.legal_name or (gstin_check or {}).get("legal_name"), gstin=body.gstin
    )
    if gstin_check:
        company["gstin_check"] = gstin_check
    try:
        await create_company_with_admin(
            db,
            company,
            admin_email=str(body.admin_email).lower(),
            password_hash=await hash_password_async(body.admin_password),
            plan_code=plan["code"],
            seats=body.seats,
            days=body.subscription_days,
            with_defaults=True,
        )
    except EmailTaken:
        raise HTTPException(409, "Admin email already exists")
    except GstinTaken:
        raise HTTPException(409, "GSTIN is already registered to another company")
    await record_audit(db, principal, "company.created", "company", company["_id"], f"Created {company['name']}", company_id=company["_id"])
    return {"id": company["_id"], "name": company["name"], "status": company["status"], "activationCode": company["activation_code"]}


@public_router.post("/companies/activate")
async def activate(body: ActivationRequest, request: Request, db: AsyncDatabase = Depends(get_db)):
    await enforce(f"activate-ip:{client_ip(request)}", 10, 3600, "Too many activation attempts; try again later")
    company = await db.companies.find_one({"activation_code": body.activation_code.strip()})
    if not company:
        raise HTTPException(404, "Invalid activation code")
    if company["status"] == CompanyStatus.suspended.value:
        raise HTTPException(403, "Company is suspended")
    await db.companies.update_one(
        {"_id": company["_id"]}, {"$set": {"status": CompanyStatus.active.value, "updated_at": utcnow()}}
    )
    await invalidate_company(company["_id"])
    return {"id": company["_id"], "status": CompanyStatus.active.value}


# ── Companies ────────────────────────────────────────────────────────────────


def _subscription_state(subscription: dict | None) -> str | None:
    if not subscription:
        return None
    if subscription["status"] == SubscriptionStatus.active.value and as_utc(subscription["ends_at"]) < utcnow():
        return SubscriptionStatus.expired.value
    return subscription["status"]


def company_json(x: dict, extra: dict | None = None) -> dict:
    return {
        "id": x["_id"],
        "name": x["name"],
        "legalName": x.get("legal_name"),
        "gstin": x.get("gstin"),
        "industry": x.get("industry"),
        "status": x["status"],
        "activationCode": x.get("activation_code"),
        "gstinCheck": check_json(x.get("gstin_check")),
        "createdAt": x.get("created_at"),
        **(extra or {}),
    }


async def _company_facts(db: AsyncDatabase, rows: list[dict]) -> dict[str, dict]:
    """Plan, seats, usage and admin contact for a page of companies, in a few batched queries."""
    ids = [row["_id"] for row in rows]
    if not ids:
        return {}
    subscriptions = {
        row["_id"]: row["sub"]
        async for row in await db.subscriptions.aggregate([
            {"$match": {"company_id": {"$in": ids}}},
            {"$sort": {"ends_at": -1}},
            {"$group": {"_id": "$company_id", "sub": {"$first": "$$ROOT"}}},
        ])
    }
    plan_names = {p["code"]: p["name"] async for p in db.subscription_plans.find({}, {"code": 1, "name": 1})}
    employees = {
        row["_id"]: row["count"]
        async for row in await db.employees.aggregate([
            {"$match": {"company_id": {"$in": ids}, "is_active": True}},
            {"$group": {"_id": "$company_id", "count": {"$sum": 1}}},
        ])
    }
    admins = {
        row["_id"]: row["email"]
        async for row in await db.users.aggregate([
            {"$match": {"company_id": {"$in": ids}, "role": Role.company_admin.value}},
            {"$sort": {"created_at": 1}},
            {"$group": {"_id": "$company_id", "email": {"$first": "$email"}}},
        ])
    }

    async def last_upload(company_id: str):
        row = await db.invoices.find_one({"company_id": company_id}, {"uploaded_at": 1}, sort=[("uploaded_at", -1)])
        return company_id, row.get("uploaded_at") if row else None

    last_activity = dict(await asyncio.gather(*(last_upload(i) for i in ids)))
    facts = {}
    for company_id in ids:
        sub = subscriptions.get(company_id)
        facts[company_id] = {
            "planCode": sub["plan_code"] if sub else None,
            "planName": plan_names.get(sub["plan_code"]) if sub else None,
            "seats": sub["seats"] if sub else None,
            "subscriptionStatus": _subscription_state(sub),
            "endsAt": sub["ends_at"] if sub else None,
            "employeeCount": employees.get(company_id, 0),
            "lastActivityAt": last_activity.get(company_id),
            "adminEmail": admins.get(company_id),
        }
    return facts


async def _company_item(db: AsyncDatabase, company: dict) -> dict:
    return company_json(company, (await _company_facts(db, [company]))[company["_id"]])


@router.get("/companies")
async def companies(
    page: int = Query(1, ge=1),
    page_size: int = Query(100, alias="pageSize", ge=1, le=500),
    q: str | None = Query(None, max_length=100),
    status: CompanyStatus | None = None,
    _: Principal = Depends(super_principal),
    db: AsyncDatabase = Depends(get_db),
):
    query: dict = {}
    if q and q.strip():
        term = icontains(q)
        admin_companies = [u["company_id"] async for u in db.users.find(
            {"email": term, "role": Role.company_admin.value}, {"company_id": 1}
        ).limit(200)]
        query["$or"] = [
            {"name": term}, {"legal_name": term}, {"gstin": term}, {"industry": term},
            {"activation_code": term}, {"_id": {"$in": admin_companies}},
        ]
    if status:
        query["status"] = status.value
    result = await paginate(db.companies, query, [("created_at", -1), ("_id", 1)], page, page_size, lambda row: row)
    facts = await _company_facts(db, result["items"])
    result["items"] = [company_json(row, facts[row["_id"]]) for row in result["items"]]
    counts = {row["_id"]: row["count"] async for row in await db.companies.aggregate(
        [{"$group": {"_id": "$status", "count": {"$sum": 1}}}]
    )}
    result["counts"] = {s.value: counts.get(s.value, 0) for s in CompanyStatus} | {"all": sum(counts.values())}
    return result


async def _get_company(db: AsyncDatabase, company_id: UUID) -> dict:
    company = await db.companies.find_one({"_id": sid(company_id)})
    if not company:
        raise HTTPException(404, "Company not found")
    return company


def _subscription_json(sub: dict | None, plan_names: dict[str, str]) -> dict | None:
    if not sub:
        return None
    return {
        "planCode": sub["plan_code"],
        "planName": plan_names.get(sub["plan_code"]),
        "seats": sub["seats"],
        "status": _subscription_state(sub),
        "startsAt": sub.get("starts_at"),
        "endsAt": sub["ends_at"],
    }


@router.get("/companies/{company_id}")
async def company_detail(company_id: UUID, _: Principal = Depends(super_principal), db: AsyncDatabase = Depends(get_db)):
    company = await _get_company(db, company_id)
    cid = company["_id"]
    admins = await db.users.find(
        {"company_id": cid, "role": Role.company_admin.value}, {"email": 1, "name": 1, "is_active": 1, "created_at": 1}
    ).sort([("created_at", 1)]).to_list(50)
    subscription = await latest_subscription(db, cid)
    plan_names = {p["code"]: p["name"] async for p in db.subscription_plans.find({}, {"code": 1, "name": 1})}
    since = utcnow() - timedelta(days=30)
    employees, active_employees, invoices, invoices30d, pending = await asyncio.gather(
        db.employees.count_documents({"company_id": cid}),
        db.employees.count_documents({"company_id": cid, "is_active": True}),
        db.invoices.count_documents({"company_id": cid}),
        db.invoices.count_documents({"company_id": cid, "uploaded_at": {"$gte": since}}),
        db.invoices.count_documents({"company_id": cid, "approval_status": "pending"}),
    )
    item = await _company_item(db, company)
    payments = await db.payment_orders.find({"company_id": cid}).sort([("created_at", -1)]).limit(10).to_list(10)
    return {
        "company": item,
        "admins": [
            {"id": a["_id"], "email": a.get("email"), "name": a.get("name"), "isActive": a.get("is_active", True), "createdAt": a.get("created_at")}
            for a in admins
        ],
        "subscription": _subscription_json(subscription, plan_names),
        "usage": {
            "employees": employees,
            "activeEmployees": active_employees,
            "invoices": invoices,
            "invoices30d": invoices30d,
            "pendingInvoices": pending,
            "lastActivityAt": item["lastActivityAt"],
        },
        "payments": [order_json(o, company["name"]) for o in payments],
    }


@router.patch("/companies/{company_id}")
async def update_company(
    company_id: UUID, body: CompanyUpdate, principal: Principal = Depends(super_principal), db: AsyncDatabase = Depends(get_db)
):
    company = await _get_company(db, company_id)
    values = body.model_dump(exclude_unset=True)
    if "name" in values and not values["name"]:
        values.pop("name")
    if "gstin" in values:
        values["state_code"] = gst.state_code(values["gstin"])
        if values["gstin"] and await db.companies.find_one({"gstin": values["gstin"], "_id": {"$ne": company["_id"]}}, {"_id": 1}):
            raise HTTPException(409, "This GSTIN is already registered to another company")
        values["gstin_check"] = await company_gstin_check(values["gstin"])
    if not values:
        return await _company_item(db, company)
    values["updated_at"] = utcnow()
    company = await db.companies.find_one_and_update({"_id": company["_id"]}, {"$set": values}, return_document=ReturnDocument.AFTER)
    await invalidate_company(company["_id"])
    changed = sorted(k for k in values if k not in ("updated_at", "state_code"))
    await record_audit(db, principal, "company.updated", "company", company["_id"], f"Updated {company['name']}: {', '.join(changed)}", company_id=company["_id"])
    return await _company_item(db, company)


@router.put("/companies/{company_id}/subscription")
async def change_subscription(
    company_id: UUID, body: SubscriptionChange, principal: Principal = Depends(super_principal), db: AsyncDatabase = Depends(get_db)
):
    company = await _get_company(db, company_id)
    cid = company["_id"]
    plan = await db.subscription_plans.find_one({"code": body.plan_code.strip().lower()})
    if not plan:
        raise HTTPException(400, "Unknown plan")
    if plan.get("max_employees") is not None and body.seats > plan["max_employees"]:
        raise HTTPException(400, f"{plan['name']} allows up to {plan['max_employees']} employees")
    active = await db.employees.count_documents({"company_id": cid, "is_active": True})
    if body.seats < active:
        raise HTTPException(400, f"{company['name']} has {active} active employees; seats cannot be lower")
    now = utcnow()
    current = await latest_subscription(db, cid)
    if body.ends_at:
        ends_at = as_utc(body.ends_at)
        if ends_at <= now:
            raise HTTPException(400, "End date must be in the future")
    elif current and as_utc(current["ends_at"]) > now:
        ends_at = as_utc(current["ends_at"])
    else:
        ends_at = now + timedelta(days=DAYS_PER_MONTH)
    changes = {"plan_code": plan["code"], "seats": body.seats, "ends_at": ends_at, "status": SubscriptionStatus.active.value}
    if current:
        if as_utc(current["ends_at"]) <= now or current["status"] != SubscriptionStatus.active.value:
            changes["starts_at"] = now
        await db.subscriptions.update_one({"_id": current["_id"]}, {"$set": changes})
        subscription = {**current, **changes}
    else:
        subscription = {"_id": new_id(), "company_id": cid, "starts_at": now, "created_at": now, **changes}
        await db.subscriptions.insert_one(subscription)
    await invalidate_company(cid)
    await record_audit(
        db, principal, "subscription.changed", "subscription", subscription["_id"],
        f"{company['name']}: {plan['name']}, {body.seats} seats, until {ends_at:%d %b %Y}", company_id=cid,
    )
    return _subscription_json(subscription, {plan["code"]: plan["name"]})


@router.post("/companies/{company_id}/admins/{user_id}/reset-password")
async def reset_admin_password(
    company_id: UUID, user_id: UUID, principal: Principal = Depends(super_principal), db: AsyncDatabase = Depends(get_db)
):
    company = await _get_company(db, company_id)
    temporary = secrets.token_urlsafe(12)
    user = await db.users.find_one_and_update(
        {"_id": sid(user_id), "company_id": company["_id"], "role": Role.company_admin.value},
        {
            "$set": {"password_hash": await hash_password_async(temporary), "refresh_token_hash": None, "updated_at": utcnow()},
            "$inc": {"token_version": 1},
        },
    )
    if not user:
        raise HTTPException(404, "Admin not found")
    await invalidate_user(user["_id"])
    await record_audit(
        db, principal, "admin.password_reset", "user", user["_id"],
        f"Reset password for {user.get('email')} ({company['name']})", company_id=company["_id"],
    )
    return {"temporaryPassword": temporary}


@router.post("/companies/{company_id}/delete", status_code=204)
async def delete_company(
    company_id: UUID, body: SuperCompanyDelete, principal: Principal = Depends(super_principal), db: AsyncDatabase = Depends(get_db)
):
    company = await _get_company(db, company_id)
    if body.confirm_name.strip().casefold() != company["name"].strip().casefold():
        raise HTTPException(400, "Type the company name exactly as shown to confirm")
    await purge_company(db, company["_id"])
    await record_audit(
        db, principal, "company.deleted", "company", company["_id"], f"Deleted {company['name']}",
        company_id=None, details={"name": company["name"]},
    )


async def set_status(company_id: UUID, status: CompanyStatus, required: CompanyStatus, principal: Principal, db: AsyncDatabase):
    company = await db.companies.find_one_and_update(
        {"_id": sid(company_id), "status": required.value},
        {"$set": {"status": status.value, "updated_at": utcnow()}},
        return_document=ReturnDocument.AFTER,
    )
    if not company:
        existing = await _get_company(db, company_id)
        raise HTTPException(409, f"Company is {existing['status']}; only {required.value} companies can be changed this way")
    await invalidate_company(company["_id"])
    action = "company.suspended" if status == CompanyStatus.suspended else "company.reactivated"
    await record_audit(db, principal, action, "company", company["_id"], f"{company['name']} {status.value}", company_id=company["_id"])
    return {"id": company["_id"], "status": company["status"]}


@router.post("/companies/{company_id}/suspend")
async def suspend(company_id: UUID, principal: Principal = Depends(super_principal), db: AsyncDatabase = Depends(get_db)):
    return await set_status(company_id, CompanyStatus.suspended, CompanyStatus.active, principal, db)


@router.post("/companies/{company_id}/reactivate")
async def reactivate(company_id: UUID, principal: Principal = Depends(super_principal), db: AsyncDatabase = Depends(get_db)):
    return await set_status(company_id, CompanyStatus.active, CompanyStatus.suspended, principal, db)


@router.post("/companies/{company_id}/subscription/extend")
async def extend(company_id: UUID, body: ExtendSubscription, principal: Principal = Depends(super_principal), db: AsyncDatabase = Depends(get_db)):
    cid = sid(company_id)
    subscription = await db.subscriptions.find_one({"company_id": cid}, sort=[("ends_at", -1)])
    if not subscription:
        raise HTTPException(404, "Subscription not found")
    base = max(as_utc(subscription["ends_at"]), utcnow())
    ends_at = base + timedelta(days=body.days)
    await db.subscriptions.update_one(
        {"_id": subscription["_id"]}, {"$set": {"ends_at": ends_at, "status": SubscriptionStatus.active.value}}
    )
    await invalidate_company(cid)
    company = await db.companies.find_one({"_id": cid}, {"name": 1})
    await record_audit(
        db, principal, "subscription.extended", "subscription", subscription["_id"],
        f"{(company or {}).get('name', cid)}: +{body.days} days, until {ends_at:%d %b %Y}", company_id=cid,
    )
    return {"companyId": cid, "endsAt": ends_at, "status": SubscriptionStatus.active.value}


# ── Platform metrics and audit ───────────────────────────────────────────────


def _inr(paise) -> Decimal:
    return (Decimal(paise or 0) / 100).quantize(Decimal("0.01"))


@router.get("/metrics")
async def metrics(_: Principal = Depends(super_principal), db: AsyncDatabase = Depends(get_db)):
    now = utcnow()
    since = now - timedelta(days=30)
    status_counts = {row["_id"]: row["count"] async for row in await db.companies.aggregate(
        [{"$group": {"_id": "$status", "count": {"$sum": 1}}}]
    )}
    signups30d, employees_active, invoices30d = await asyncio.gather(
        db.companies.count_documents({"created_at": {"$gte": since}}),
        db.employees.count_documents({"is_active": True}),
        db.invoices.count_documents({"uploaded_at": {"$gte": since}}),
    )
    prices = {p["code"]: Decimal(str(p["monthly_price_inr"])) async for p in db.subscription_plans.find({}, {"code": 1, "monthly_price_inr": 1})}
    mrr = Decimal(0)
    async for sub in db.subscriptions.find(
        {"status": SubscriptionStatus.active.value, "ends_at": {"$gte": now}}, {"plan_code": 1, "company_id": 1}
    ):
        mrr += prices.get(sub["plan_code"], Decimal(0))
    paid = {"status": PaymentStatus.paid.value}

    async def revenue(match: dict) -> Decimal:
        rows = await (await db.payment_orders.aggregate([
            {"$match": match}, {"$group": {"_id": None, "paise": {"$sum": "$amount_paise"}}},
        ])).to_list(1)
        return _inr(rows[0]["paise"] if rows else 0)

    revenue30d = await revenue({**paid, "paid_at": {"$gte": since}})
    revenue_total = await revenue(paid)

    expiring = await db.subscriptions.find(
        {"status": SubscriptionStatus.active.value, "ends_at": {"$gte": now, "$lte": now + timedelta(days=EXPIRING_DAYS)}}
    ).sort([("ends_at", 1)]).limit(50).to_list(50)
    names = {c["_id"]: c["name"] async for c in db.companies.find({"_id": {"$in": [s["company_id"] for s in expiring]}}, {"name": 1})}

    window_start, days = ist_last_days(METRIC_DAYS)

    async def per_day(collection, field: str, match: dict, value=None) -> dict:
        group: dict = {"_id": day_bucket(field), "n": {"$sum": value if value is not None else 1}}
        return {row["_id"]: row["n"] async for row in await collection.aggregate([
            {"$match": {**match, field: {"$gte": window_start}}}, {"$group": group},
        ])}

    signups = await per_day(db.companies, "created_at", {})
    uploads = await per_day(db.invoices, "uploaded_at", {})
    revenue_daily = await per_day(db.payment_orders, "paid_at", paid, "$amount_paise")
    return {
        "companies": {
            "all": sum(status_counts.values()),
            **{s.value: status_counts.get(s.value, 0) for s in CompanyStatus},
        },
        "signups30d": signups30d,
        "employeesActive": employees_active,
        "invoices30d": invoices30d,
        "mrrInr": mrr.quantize(Decimal("0.01")),
        "revenue30dInr": revenue30d,
        "revenueTotalInr": revenue_total,
        "expiringSoon": [
            {"companyId": s["company_id"], "companyName": names.get(s["company_id"]), "planCode": s["plan_code"], "endsAt": s["ends_at"]}
            for s in expiring
            if s["company_id"] in names
        ],
        "daily": [
            {"date": day, "signups": signups.get(day, 0), "invoices": uploads.get(day, 0), "revenueInr": _inr(revenue_daily.get(day, 0))}
            for day in days
        ],
    }


@router.get("/audit")
async def audit_log(
    company_id: UUID | None = Query(None, alias="companyId"),
    action: str | None = Query(None, max_length=60),
    page: int = Query(1, ge=1),
    page_size: int = Query(50, alias="pageSize", ge=1, le=200),
    _: Principal = Depends(super_principal),
    db: AsyncDatabase = Depends(get_db),
):
    query: dict = {}
    if company_id:
        query["company_id"] = sid(company_id)
    if action:
        query["action"] = {"$regex": "^" + re.escape(action)}
    result = await paginate(db.audit_logs, query, [("created_at", -1), ("_id", 1)], page, page_size, lambda row: row)
    ids = list({row.get("company_id") for row in result["items"] if row.get("company_id")})
    names = {c["_id"]: c["name"] async for c in db.companies.find({"_id": {"$in": ids}}, {"name": 1})}
    result["items"] = [audit_json(row, names) for row in result["items"]]
    return result
