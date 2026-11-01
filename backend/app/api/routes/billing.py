import hashlib
import json
import logging
from datetime import date, timedelta
from decimal import Decimal
from uuid import UUID, uuid4

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from pymongo.asynchronous.database import AsyncDatabase
from pymongo.errors import DuplicateKeyError

from app.core.config import settings
from app.core.deps import Principal, billing_admin_principal, super_principal
from app.core.ratelimit import enforce
from app.db.mongo import as_utc, get_db, icontains, new_id, sid, utcnow
from app.models import PaymentStatus, SubscriptionStatus
from app.schemas.common import BillingOrderCreate, BillingVerify
from app.services.payments import (
    create_provider_order,
    mark_failed,
    mark_paid,
    mark_refunded,
    order_json,
    quote,
    require_configured,
    verify_checkout_signature,
    verify_webhook_signature,
)
from app.services.billing_invoice import ensure_invoice, invoice_json
from app.services.reports import ist_day_start

logger = logging.getLogger(__name__)

admin_router = APIRouter()
super_router = APIRouter()
webhook_router = APIRouter()


def plan_json(plan: dict) -> dict:
    return {
        "code": plan["code"],
        "name": plan["name"],
        "monthlyPriceInr": plan["monthly_price_inr"],
        "maxEmployees": plan.get("max_employees"),
        "features": plan.get("features_json") or {},
        "purchasable": plan["monthly_price_inr"] > 0,
    }


@admin_router.get("")
async def billing_overview(principal: Principal = Depends(billing_admin_principal), db: AsyncDatabase = Depends(get_db)):
    subscription = await db.subscriptions.find_one({"company_id": principal.company_id}, sort=[("ends_at", -1)])
    plans = await db.subscription_plans.find().sort([("monthly_price_inr", 1), ("_id", 1)]).to_list(None)
    orders = await db.payment_orders.find({"company_id": principal.company_id}).sort([("created_at", -1)]).limit(25).to_list(25)
    active_employees = await db.employees.count_documents({"company_id": principal.company_id, "is_active": True})
    return {
        "activeEmployees": active_employees,
        "paymentsEnabled": settings.payments_configured,
        "keyId": settings.razorpay_key_id if settings.payments_configured else None,
        "taxPercent": settings.effective_tax_percent,
        "liveMode": settings.payments_live,
        "businessName": settings.business_name,
        "subscription": None
        if not subscription
        else {
            "planCode": subscription["plan_code"],
            "seats": subscription["seats"],
            "startsAt": subscription.get("starts_at"),
            "endsAt": subscription["ends_at"],
            "status": subscription["status"],
            "isActive": subscription["status"] == SubscriptionStatus.active.value and as_utc(subscription["ends_at"]) >= utcnow(),
        },
        "plans": [plan_json(p) for p in plans],
        "orders": [order_json(o) for o in orders],
    }


@admin_router.post("/orders", status_code=201)
async def create_order(
    body: BillingOrderCreate,
    principal: Principal = Depends(billing_admin_principal),
    db: AsyncDatabase = Depends(get_db),
):
    require_configured()
    await enforce(f"billing-order:{principal.company_id}", 10, 600, "Too many checkout attempts; wait a few minutes")
    plan = await db.subscription_plans.find_one({"code": body.plan_code})
    if not plan:
        raise HTTPException(400, "Unknown plan")
    if plan.get("max_employees") is not None and body.seats > plan["max_employees"]:
        raise HTTPException(400, f"{plan['name']} allows up to {plan['max_employees']} employees")
    if plan["monthly_price_inr"] <= 0:
        raise HTTPException(400, "This plan cannot be purchased online")
    active_employees = await db.employees.count_documents({"company_id": principal.company_id, "is_active": True})
    if body.seats < active_employees:
        raise HTTPException(
            400, f"You have {active_employees} active employees. Buy at least {active_employees} seats or deactivate employees first."
        )
    company = await db.companies.find_one({"_id": principal.company_id}, {"name": 1})
    user = await db.users.find_one({"_id": principal.user.id}, {"email": 1})
    price = quote(plan, body.months)
    receipt = f"sub_{uuid4().hex[:24]}"
    provider = await create_provider_order(
        price["amountPaise"],
        receipt,
        {"companyId": principal.company_id, "planCode": plan["code"], "seats": str(body.seats), "months": str(body.months)},
    )
    order_doc_id = new_id()
    await db.payment_orders.insert_one({
        "_id": order_doc_id,
        "company_id": principal.company_id,
        "plan_code": plan["code"],
        "seats": body.seats,
        "months": body.months,
        "amount_paise": price["amountPaise"],
        "subtotal": price["subtotal"],
        "tax": price["tax"],
        "tax_percent": Decimal(str(price["taxPercent"])),
        "currency": "INR",
        "status": PaymentStatus.created.value,
        "provider_order_id": provider["id"],
        "provider_payment_id": None,
        "failure_reason": None,
        "subscription_id": None,
        "created_by": principal.user.id,
        "created_at": utcnow(),
        "paid_at": None,
    })
    return {
        "id": order_doc_id,
        "orderId": provider["id"],
        "keyId": settings.razorpay_key_id,
        "amountPaise": price["amountPaise"],
        "currency": "INR",
        "quote": price,
        "companyName": company["name"] if company else None,
        "prefillEmail": user.get("email") if user else None,
        "description": f"{plan['name']} · {body.seats} seats · {body.months} month{'s' if body.months > 1 else ''}",
    }


@admin_router.post("/verify")
async def verify_payment(
    body: BillingVerify,
    principal: Principal = Depends(billing_admin_principal),
    db: AsyncDatabase = Depends(get_db),
):
    require_configured()
    order = await db.payment_orders.find_one(
        {"provider_order_id": body.razorpay_order_id, "company_id": principal.company_id}, {"_id": 1}
    )
    if not order:
        raise HTTPException(404, "Order not found")
    if not verify_checkout_signature(body.razorpay_order_id, body.razorpay_payment_id, body.razorpay_signature):
        raise HTTPException(400, "Payment signature could not be verified")
    return order_json(await mark_paid(db, body.razorpay_order_id, body.razorpay_payment_id))


@webhook_router.post("/razorpay/webhook")
async def razorpay_webhook(request: Request, db: AsyncDatabase = Depends(get_db)):
    if not settings.payments_configured:
        raise HTTPException(503, "Payments not configured")
    raw = await request.body()
    if not verify_webhook_signature(raw, request.headers.get("x-razorpay-signature", "")):
        raise HTTPException(400, "Invalid signature")
    try:
        event = json.loads(raw)
    except ValueError:
        raise HTTPException(400, "Invalid payload")
    event_type = event.get("event", "")
    event_id = request.headers.get("x-razorpay-event-id") or f"{event_type}:{hashlib.sha256(raw).hexdigest()}"

    record = {
        "_id": new_id(),
        "provider_event_id": event_id[:100],
        "event_type": event_type[:60],
        "payload": event,
        "created_at": utcnow(),
    }
    try:
        await db.payment_events.insert_one(record)
    except DuplicateKeyError:
        return {"ok": True, "duplicate": True}

    payload = event.get("payload", {})
    payment = (payload.get("payment") or {}).get("entity") or {}
    order_entity = (payload.get("order") or {}).get("entity") or {}
    order_id = payment.get("order_id") or order_entity.get("id")
    try:
        if order_id:
            if event_type in ("payment.captured", "order.paid"):
                await mark_paid(db, order_id, payment.get("id"), amount_paise=payment.get("amount"))
            elif event_type == "payment.failed":
                await mark_failed(db, order_id, payment.get("id"), payment.get("error_description"))
        if event_type in ("refund.processed", "refund.created", "payment.refunded"):
            refund = (payload.get("refund") or {}).get("entity") or {}
            payment_id = payment.get("id") or refund.get("payment_id")
            refunded = payment.get("amount_refunded") or refund.get("amount")
            if payment_id and refunded:
                await mark_refunded(db, payment_id, int(refunded))
    except Exception:
        # Forget the event so Razorpay's retry is processed instead of skipped as a duplicate.
        await db.payment_events.delete_one({"_id": record["_id"]})
        raise
    return {"ok": True}


@super_router.get("")
async def all_payments(
    page: int = Query(1, ge=1),
    page_size: int = Query(50, alias="pageSize", ge=1, le=200),
    status: PaymentStatus | None = None,
    company_id: UUID | None = Query(None, alias="companyId"),
    q: str | None = Query(None, max_length=100),
    date_from: date | None = Query(None, alias="dateFrom"),
    date_to: date | None = Query(None, alias="dateTo"),
    _: Principal = Depends(super_principal),
    db: AsyncDatabase = Depends(get_db),
):
    query: dict = {"status": status.value} if status else {}
    if company_id:
        query["company_id"] = sid(company_id)
    if q and q.strip():
        term = icontains(q)
        matching = [c["_id"] async for c in db.companies.find({"$or": [{"name": term}, {"gstin": term}]}, {"_id": 1}).limit(500)]
        query["$or"] = [
            {"company_id": {"$in": matching}}, {"company_name": term},
            {"provider_order_id": term}, {"provider_payment_id": term},
        ]
    if date_from or date_to:
        query["created_at"] = {
            **({"$gte": ist_day_start(date_from)} if date_from else {}),
            **({"$lt": ist_day_start(date_to + timedelta(days=1))} if date_to else {}),
        }
    total = await db.payment_orders.count_documents(query)
    settled = [PaymentStatus.paid.value, PaymentStatus.refunded.value]
    paid_query = {**query, "status": query["status"] if query.get("status") in settled else {"$in": settled}}
    if query.get("status") and query["status"] not in settled:
        paid_query["status"] = "__none__"
    totals = await (await db.payment_orders.aggregate([
        {"$match": paid_query},
        {"$group": {
            "_id": None, "paise": {"$sum": "$amount_paise"}, "count": {"$sum": 1},
            "refunded": {"$sum": {"$ifNull": ["$refunded_paise", 0]}},
        }},
    ])).to_list(1)
    orders = await db.payment_orders.find(query).sort([("created_at", -1), ("_id", 1)]).skip((page - 1) * page_size).limit(page_size).to_list(page_size)
    names = {
        c["_id"]: c["name"]
        async for c in db.companies.find({"_id": {"$in": list({o["company_id"] for o in orders})}}, {"name": 1})
    }
    return {
        "items": [order_json(o, names.get(o["company_id"])) for o in orders],
        "total": total,
        "page": page,
        "pageSize": page_size,
        "totals": {
            "paidInr": Decimal(totals[0]["paise"]) / 100 if totals else Decimal(0),
            "paidCount": totals[0]["count"] if totals else 0,
            "refundedInr": Decimal(totals[0]["refunded"]) / 100 if totals else Decimal(0),
            "netInr": Decimal(totals[0]["paise"] - totals[0]["refunded"]) / 100 if totals else Decimal(0),
        },
        "paymentsEnabled": settings.payments_configured,
    }


async def _invoice_for(db: AsyncDatabase, query: dict) -> dict:
    order = await db.payment_orders.find_one(query)
    if not order:
        raise HTTPException(404, "Payment not found")
    if order["status"] not in (PaymentStatus.paid.value, PaymentStatus.refunded.value) and not order.get("invoice"):
        raise HTTPException(409, "An invoice is issued once the payment succeeds")
    if not order.get("invoice"):
        order = await ensure_invoice(db, {**order, "status": PaymentStatus.paid.value})
    return invoice_json(order)


@admin_router.get("/orders/{order_id}/invoice")
async def company_invoice(order_id: UUID, principal: Principal = Depends(billing_admin_principal), db: AsyncDatabase = Depends(get_db)):
    return await _invoice_for(db, {"_id": sid(order_id), "company_id": principal.company_id})


@super_router.get("/{order_id}/invoice")
async def super_invoice(order_id: UUID, _: Principal = Depends(super_principal), db: AsyncDatabase = Depends(get_db)):
    return await _invoice_for(db, {"_id": sid(order_id)})
