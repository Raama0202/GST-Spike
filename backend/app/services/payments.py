"""Razorpay: order creation, signature checks, and idempotent subscription credit."""
import hashlib
import hmac
import logging
from datetime import timedelta
from decimal import ROUND_HALF_UP, Decimal
from uuid import NAMESPACE_URL, uuid5

import httpx
from fastapi import HTTPException
from pymongo import ReturnDocument
from pymongo.asynchronous.database import AsyncDatabase
from pymongo.errors import DuplicateKeyError

from app.core.config import settings
from app.db.mongo import as_utc, new_id, utcnow
from app.models import CompanyStatus, PaymentStatus, SubscriptionStatus
from app.services.subscription import invalidate_company

logger = logging.getLogger(__name__)

API_BASE = "https://api.razorpay.com/v1"
TIMEOUT = httpx.Timeout(15.0, connect=5.0)
DAYS_PER_MONTH = 30


def require_configured() -> None:
    if not settings.payments_configured:
        raise HTTPException(503, "Online payments are not enabled yet. Contact support to renew.")


def quote(plan: dict, months: int) -> dict:
    base = (Decimal(str(plan["monthly_price_inr"])) * months).quantize(Decimal("0.01"))
    percent = Decimal(str(settings.effective_tax_percent))
    tax = (base * percent / 100).quantize(Decimal("0.01"), ROUND_HALF_UP)
    total = base + tax
    return {
        "subtotal": base,
        "tax": tax,
        "taxPercent": settings.effective_tax_percent,
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


SETTLED = [PaymentStatus.paid.value, PaymentStatus.refunded.value]


async def mark_paid(
    db: AsyncDatabase, provider_order_id: str, payment_id: str | None, *, amount_paise: int | None = None
) -> dict | None:
    """Credit the subscription exactly once per order, whichever of checkout-verify or
    webhook arrives first. `credited: False` marks a claim whose credit has not finished,
    so a crash between the two steps is completed by the next verify/webhook retry."""
    now = utcnow()
    if amount_paise is not None:
        expected = await db.payment_orders.find_one({"provider_order_id": provider_order_id}, {"amount_paise": 1})
        if expected and expected["amount_paise"] != amount_paise:
            logger.error("Razorpay order %s paid %s paise, expected %s; not crediting", provider_order_id, amount_paise, expected["amount_paise"])
            return expected
    claimed = await db.payment_orders.find_one_and_update(
        {"provider_order_id": provider_order_id, "status": {"$nin": SETTLED}},
        {"$set": {"status": PaymentStatus.paid.value, "paid_at": now, "failure_reason": None, "credited": False}},
        return_document=ReturnDocument.AFTER,
    )
    if claimed is None:
        existing = await db.payment_orders.find_one({"provider_order_id": provider_order_id})
        if not existing or existing.get("credited") is not False:
            return existing
        claimed = existing

    company_id = claimed["company_id"]
    subscription_id = await _credit_subscription(db, claimed)
    await db.companies.update_one(
        {"_id": company_id, "status": CompanyStatus.pending.value},
        {"$set": {"status": CompanyStatus.active.value, "updated_at": now}},
    )
    order = await db.payment_orders.find_one_and_update(
        {"_id": claimed["_id"]},
        {"$set": {
            "subscription_id": subscription_id,
            "provider_payment_id": payment_id or claimed.get("provider_payment_id"),
            "credited": True,
        }},
        return_document=ReturnDocument.AFTER,
    )
    await invalidate_company(company_id)
    from app.services.audit import record_audit
    from app.services.billing_invoice import ensure_invoice, send_receipt_later

    try:
        order = await ensure_invoice(db, order)
    except Exception:  # noqa: BLE001
        # The subscription is credited; the invoice is issued on first view instead.
        logger.exception("Could not issue invoice for order %s", claimed["_id"])
    send_receipt_later(db, order)

    await record_audit(
        db, None, "billing.paid", "payment", claimed["_id"],
        f"Paid ₹{Decimal(claimed['amount_paise']) / 100} for {claimed['plan_code']} · {claimed['seats']} seats · {claimed['months']} month(s)",
        company_id=company_id,
    )
    logger.info("Payment %s credited %s months to company %s", provider_order_id, claimed["months"], company_id)
    return order


async def _credit_subscription(db: AsyncDatabase, order: dict) -> str:
    """Idempotent per order: the subscription remembers which orders it already absorbed."""
    now = utcnow()
    company_id = order["company_id"]
    extra = timedelta(days=DAYS_PER_MONTH * order["months"])
    subscription = await db.subscriptions.find_one({"company_id": company_id}, sort=[("ends_at", -1)])
    if subscription is None:
        subscription_id = str(uuid5(NAMESPACE_URL, f"payment-order:{order['_id']}"))
        try:
            await db.subscriptions.insert_one({
                "_id": subscription_id,
                "company_id": company_id,
                "plan_code": order["plan_code"],
                "seats": order["seats"],
                "starts_at": now,
                "ends_at": now + extra,
                "status": SubscriptionStatus.active.value,
                "credited_orders": [order["_id"]],
                "created_at": now,
            })
        except DuplicateKeyError:
            pass
        return subscription_id
    if order["_id"] in (subscription.get("credited_orders") or []):
        return subscription["_id"]
    current_end = as_utc(subscription["ends_at"])
    active = subscription["status"] == SubscriptionStatus.active.value and current_end > now
    changes = {
        "ends_at": (current_end if active else now) + extra,
        "plan_code": order["plan_code"],
        "seats": order["seats"],
        "status": SubscriptionStatus.active.value,
    }
    if not active:
        changes["starts_at"] = now
    await db.subscriptions.update_one(
        {"_id": subscription["_id"], "credited_orders": {"$ne": order["_id"]}},
        {"$set": changes, "$push": {"credited_orders": order["_id"]}},
    )
    return subscription["_id"]

async def mark_failed(db: AsyncDatabase, provider_order_id: str, payment_id: str | None, reason: str | None) -> None:
    changes: dict = {"status": PaymentStatus.failed.value, "failure_reason": (reason or "Payment failed")[:500]}
    if payment_id:
        changes["provider_payment_id"] = payment_id
    await db.payment_orders.update_one(
        {"provider_order_id": provider_order_id, "status": {"$nin": SETTLED}},
        {"$set": changes},
    )


async def mark_refunded(db: AsyncDatabase, payment_id: str, refunded_paise: int) -> dict | None:
    """Record a refund made in the Razorpay dashboard. The subscription is not shortened
    automatically; the super admin decides that on the company page."""
    order = await db.payment_orders.find_one({"provider_payment_id": payment_id})
    if not order or refunded_paise <= (order.get("refunded_paise") or 0):
        return order
    full = refunded_paise >= order["amount_paise"]
    changes: dict = {"refunded_paise": refunded_paise, "refunded_at": utcnow()}
    if full:
        changes["status"] = PaymentStatus.refunded.value
    order = await db.payment_orders.find_one_and_update(
        {"_id": order["_id"]}, {"$set": changes}, return_document=ReturnDocument.AFTER
    )
    from app.services.audit import record_audit

    await record_audit(
        db, None, "billing.refunded", "payment", order["_id"],
        f"Refunded ₹{Decimal(refunded_paise) / 100} of ₹{Decimal(order['amount_paise']) / 100}" + (" (full)" if full else " (partial)"),
        company_id=order["company_id"],
    )
    logger.info("Payment %s refunded %s paise", payment_id, refunded_paise)
    return order


def order_json(order: dict, company_name: str | None = None) -> dict:
    return {
        "id": order["_id"],
        "companyId": order["company_id"],
        "companyName": company_name or order.get("company_name"),
        "planCode": order["plan_code"],
        "seats": order["seats"],
        "months": order["months"],
        "amount": Decimal(order["amount_paise"]) / 100,
        "currency": order.get("currency", "INR"),
        "status": order["status"],
        "providerOrderId": order["provider_order_id"],
        "providerPaymentId": order.get("provider_payment_id"),
        "failureReason": order.get("failure_reason"),
        "invoiceNumber": (order.get("invoice") or {}).get("number"),
        "refundedAmount": Decimal(order.get("refunded_paise") or 0) / 100,
        "createdAt": order.get("created_at"),
        "paidAt": order.get("paid_at"),
    }
