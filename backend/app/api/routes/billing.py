import json
import logging
from datetime import datetime, timezone
from uuid import uuid4

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.pagination import paginate
from app.core.config import settings
from app.core.deps import Principal, billing_admin_principal, super_principal
from app.core.ratelimit import enforce
from app.db.session import get_db
from app.models import Company, PaymentEvent, PaymentOrder, PaymentStatus, Subscription, SubscriptionPlan, User
from app.schemas.common import BillingOrderCreate, BillingVerify
from app.services.payments import (
    create_provider_order,
    mark_failed,
    mark_paid,
    order_json,
    quote,
    require_configured,
    verify_checkout_signature,
    verify_webhook_signature,
)

logger = logging.getLogger(__name__)

admin_router = APIRouter()
super_router = APIRouter()
webhook_router = APIRouter()


def plan_json(plan: SubscriptionPlan) -> dict:
    return {
        "code": plan.code,
        "name": plan.name,
        "monthlyPriceInr": plan.monthly_price_inr,
        "maxEmployees": plan.max_employees,
        "features": plan.features_json,
    }


@admin_router.get("")
async def billing_overview(principal: Principal = Depends(billing_admin_principal), db: AsyncSession = Depends(get_db)):
    subscription = await db.scalar(
        select(Subscription).where(Subscription.company_id == principal.company_id).order_by(Subscription.ends_at.desc()).limit(1)
    )
    plans = (await db.scalars(select(SubscriptionPlan).order_by(SubscriptionPlan.monthly_price_inr))).all()
    orders = (
        await db.scalars(
            select(PaymentOrder).where(PaymentOrder.company_id == principal.company_id).order_by(PaymentOrder.created_at.desc()).limit(25)
        )
    ).all()
    now = datetime.now(timezone.utc)
    return {
        "paymentsEnabled": settings.payments_configured,
        "keyId": settings.razorpay_key_id if settings.payments_configured else None,
        "taxPercent": settings.billing_tax_percent,
        "subscription": None
        if not subscription
        else {
            "planCode": subscription.plan_code,
            "seats": subscription.seats,
            "startsAt": subscription.starts_at,
            "endsAt": subscription.ends_at,
            "status": subscription.status.value,
            "isActive": subscription.status.value == "active" and subscription.ends_at.replace(tzinfo=timezone.utc) >= now,
        },
        "plans": [plan_json(p) for p in plans],
        "orders": [order_json(o) for o in orders],
    }


@admin_router.post("/orders", status_code=201)
async def create_order(
    body: BillingOrderCreate,
    principal: Principal = Depends(billing_admin_principal),
    db: AsyncSession = Depends(get_db),
):
    require_configured()
    await enforce(f"billing-order:{principal.company_id}", 10, 600, "Too many checkout attempts; wait a few minutes")
    plan = await db.scalar(select(SubscriptionPlan).where(SubscriptionPlan.code == body.plan_code))
    if not plan:
        raise HTTPException(400, "Unknown plan")
    if plan.max_employees is not None and body.seats > plan.max_employees:
        raise HTTPException(400, f"{plan.name} allows up to {plan.max_employees} employees")
    if plan.monthly_price_inr <= 0:
        raise HTTPException(400, "This plan cannot be purchased online")
    company = await db.get(Company, principal.company_id)
    user = await db.get(User, principal.user.id)
    price = quote(plan, body.months)
    receipt = f"sub_{uuid4().hex[:24]}"
    provider = await create_provider_order(
        price["amountPaise"],
        receipt,
        {"companyId": str(principal.company_id), "planCode": plan.code, "seats": str(body.seats), "months": str(body.months)},
    )
    order = PaymentOrder(
        company_id=principal.company_id,
        plan_code=plan.code,
        seats=body.seats,
        months=body.months,
        amount_paise=price["amountPaise"],
        currency="INR",
        provider_order_id=provider["id"],
        created_by=principal.user.id,
    )
    db.add(order)
    await db.commit()
    return {
        "orderId": provider["id"],
        "keyId": settings.razorpay_key_id,
        "amountPaise": price["amountPaise"],
        "currency": "INR",
        "quote": price,
        "companyName": company.name if company else None,
        "prefillEmail": user.email if user else None,
        "description": f"{plan.name} · {body.seats} seats · {body.months} month{'s' if body.months > 1 else ''}",
    }


@admin_router.post("/verify")
async def verify_payment(
    body: BillingVerify,
    principal: Principal = Depends(billing_admin_principal),
    db: AsyncSession = Depends(get_db),
):
    require_configured()
    order = await db.scalar(
        select(PaymentOrder).where(
            PaymentOrder.provider_order_id == body.razorpay_order_id,
            PaymentOrder.company_id == principal.company_id,
        )
    )
    if not order:
        raise HTTPException(404, "Order not found")
    if not verify_checkout_signature(body.razorpay_order_id, body.razorpay_payment_id, body.razorpay_signature):
        raise HTTPException(400, "Payment signature could not be verified")
    order = await mark_paid(db, body.razorpay_order_id, body.razorpay_payment_id)
    await db.commit()
    return order_json(order)


@webhook_router.post("/razorpay/webhook")
async def razorpay_webhook(request: Request, db: AsyncSession = Depends(get_db)):
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
    event_id = request.headers.get("x-razorpay-event-id") or f"{event_type}:{event.get('created_at')}:{hash(raw)}"

    db.add(PaymentEvent(provider_event_id=event_id[:100], event_type=event_type[:60], payload=event))
    try:
        await db.flush()
    except IntegrityError:
        await db.rollback()
        return {"ok": True, "duplicate": True}

    payload = event.get("payload", {})
    payment = (payload.get("payment") or {}).get("entity") or {}
    order_entity = (payload.get("order") or {}).get("entity") or {}
    order_id = payment.get("order_id") or order_entity.get("id")
    if order_id:
        if event_type in ("payment.captured", "order.paid"):
            await mark_paid(db, order_id, payment.get("id"))
        elif event_type == "payment.failed":
            await mark_failed(db, order_id, payment.get("id"), payment.get("error_description"))
    await db.commit()
    return {"ok": True}


@super_router.get("")
async def all_payments(
    page: int = Query(1, ge=1),
    page_size: int = Query(50, alias="pageSize", ge=1, le=200),
    status: PaymentStatus | None = None,
    _: Principal = Depends(super_principal),
    db: AsyncSession = Depends(get_db),
):
    query = select(PaymentOrder, Company.name).join(Company, Company.id == PaymentOrder.company_id)
    if status:
        query = query.where(PaymentOrder.status == status)
    result = await paginate(
        db,
        query.order_by(PaymentOrder.created_at.desc(), PaymentOrder.id),
        page,
        page_size,
        lambda row: order_json(row[0], row[1]),
        scalars=False,
    )
    result["paymentsEnabled"] = settings.payments_configured
    return result
