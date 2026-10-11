"""Razorpay: order creation, signature checks, and idempotent subscription credit."""
import hashlib
import hmac
import logging
from datetime import datetime, timedelta, timezone
from decimal import ROUND_HALF_UP, Decimal

import httpx
from fastapi import HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.models import (
    Company,
    CompanyStatus,
    PaymentOrder,
    PaymentStatus,
    Subscription,
    SubscriptionPlan,
    SubscriptionStatus,
)
from app.services.subscription import invalidate_company

logger = logging.getLogger(__name__)

API_BASE = "https://api.razorpay.com/v1"
TIMEOUT = httpx.Timeout(15.0, connect=5.0)
DAYS_PER_MONTH = 30


def require_configured() -> None:
    if not settings.payments_configured:
        raise HTTPException(503, "Online payments are not enabled yet. Contact support to renew.")


def quote(plan: SubscriptionPlan, months: int) -> dict:
    base = (Decimal(plan.monthly_price_inr) * months).quantize(Decimal("0.01"))
    tax = (base * Decimal(str(settings.billing_tax_percent)) / 100).quantize(Decimal("0.01"), ROUND_HALF_UP)
    total = base + tax
    return {
        "subtotal": base,
        "tax": tax,
        "taxPercent": settings.billing_tax_percent,
        "total": total,
        "amountPaise": int((total * 100).to_integral_value(ROUND_HALF_UP)),
    }


async def create_provider_order(amount_paise: int, receipt: str, notes: dict) -> dict:
    async with httpx.AsyncClient(timeout=TIMEOUT, auth=(settings.razorpay_key_id, settings.razorpay_key_secret)) as client:
        response = await client.post(
            f"{API_BASE}/orders",
            json={"amount": amount_paise, "currency": "INR", "receipt": receipt[:40], "notes": notes},
        )
    if response.status_code >= 400:
        logger.error("Razorpay order creation failed: %s %s", response.status_code, response.text[:300])
        raise HTTPException(502, "Payment provider is unavailable. Please try again.")
    return response.json()


def _hmac(secret: str, message: bytes) -> str:
    return hmac.new(secret.encode(), message, hashlib.sha256).hexdigest()


def verify_checkout_signature(order_id: str, payment_id: str, signature: str) -> bool:
    expected = _hmac(settings.razorpay_key_secret, f"{order_id}|{payment_id}".encode())
    return hmac.compare_digest(expected, signature or "")


def verify_webhook_signature(body: bytes, signature: str) -> bool:
    expected = _hmac(settings.razorpay_webhook_secret, body)
    return hmac.compare_digest(expected, signature or "")


async def mark_paid(db: AsyncSession, provider_order_id: str, payment_id: str | None) -> PaymentOrder | None:
    """Credit the subscription exactly once per order, whichever of
    checkout-verify or webhook arrives first. Caller commits."""
    order = await db.scalar(
        select(PaymentOrder).where(PaymentOrder.provider_order_id == provider_order_id).with_for_update()
    )
    if not order:
        return None
    if order.status == PaymentStatus.paid:
        return order

    now = datetime.now(timezone.utc)
    subscription = await db.scalar(
        select(Subscription)
        .where(Subscription.company_id == order.company_id)
        .order_by(Subscription.ends_at.desc())
        .limit(1)
        .with_for_update()
    )
    extra = timedelta(days=DAYS_PER_MONTH * order.months)
    if subscription:
        current_end = subscription.ends_at.replace(tzinfo=timezone.utc)
        active = subscription.status == SubscriptionStatus.active and current_end > now
        subscription.ends_at = (current_end if active else now) + extra
        if not active:
            subscription.starts_at = now
        subscription.plan_code = order.plan_code
        subscription.seats = order.seats
        subscription.status = SubscriptionStatus.active
    else:
        subscription = Subscription(
            company_id=order.company_id,
            plan_code=order.plan_code,
            seats=order.seats,
            starts_at=now,
            ends_at=now + extra,
            status=SubscriptionStatus.active,
        )
        db.add(subscription)
        await db.flush()

    company = await db.get(Company, order.company_id)
    if company and company.status == CompanyStatus.pending:
        company.status = CompanyStatus.active

    order.status = PaymentStatus.paid
    order.provider_payment_id = payment_id or order.provider_payment_id
    order.paid_at = now
    order.subscription_id = subscription.id
    order.failure_reason = None
    await db.flush()
    await invalidate_company(order.company_id)
    logger.info("Payment %s credited %s months to company %s", provider_order_id, order.months, order.company_id)
    return order


async def mark_failed(db: AsyncSession, provider_order_id: str, payment_id: str | None, reason: str | None) -> None:
    order = await db.scalar(select(PaymentOrder).where(PaymentOrder.provider_order_id == provider_order_id))
    if order and order.status != PaymentStatus.paid:
        order.status = PaymentStatus.failed
        order.provider_payment_id = payment_id or order.provider_payment_id
        order.failure_reason = (reason or "Payment failed")[:500]


def order_json(order: PaymentOrder, company_name: str | None = None) -> dict:
    return {
        "id": order.id,
        "companyId": order.company_id,
        "companyName": company_name,
        "planCode": order.plan_code,
        "seats": order.seats,
        "months": order.months,
        "amount": Decimal(order.amount_paise) / 100,
        "currency": order.currency,
        "status": order.status.value,
        "providerOrderId": order.provider_order_id,
        "providerPaymentId": order.provider_payment_id,
        "failureReason": order.failure_reason,
        "createdAt": order.created_at,
        "paidAt": order.paid_at,
    }
