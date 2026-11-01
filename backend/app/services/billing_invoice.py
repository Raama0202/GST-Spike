"""GST tax invoices for subscription payments, issued once per paid order."""
import asyncio
import logging
from datetime import datetime
from decimal import ROUND_HALF_UP, Decimal

from pymongo import ReturnDocument
from pymongo.asynchronous.database import AsyncDatabase

from app.core.config import settings
from app.db.mongo import as_utc, utcnow
from app.models import Role
from app.services.gstin_verify import STATE_NAMES
from app.services.reports import IST

logger = logging.getLogger(__name__)

CENT = Decimal("0.01")
_background: set[asyncio.Task] = set()


def financial_year(moment: datetime) -> str:
    local = as_utc(moment).astimezone(IST)
    start = local.year if local.month >= 4 else local.year - 1
    return f"{start}-{str(start + 1)[2:]}"


async def next_invoice_number(db: AsyncDatabase, issued_at: datetime) -> str:
    """Consecutive per financial year, as GST rules expect for invoice series."""
    fy = financial_year(issued_at)
    counter = await db.counters.find_one_and_update(
        {"_id": f"invoice:{fy}"}, {"$inc": {"seq": 1}}, upsert=True, return_document=ReturnDocument.AFTER
    )
    return f"{settings.billing_invoice_prefix}/{fy}/{counter['seq']:05d}"


def order_breakdown(order: dict) -> tuple[Decimal, Decimal, Decimal]:
    """(subtotal, tax, tax_percent) recorded at checkout; derived for orders created before that."""
    total = (Decimal(order["amount_paise"]) / 100).quantize(CENT)
    if order.get("subtotal") is not None:
        return Decimal(str(order["subtotal"])), Decimal(str(order["tax"])), Decimal(str(order.get("tax_percent", 0)))
    percent = Decimal(str(settings.effective_tax_percent))
    subtotal = (total * 100 / (100 + percent)).quantize(CENT, ROUND_HALF_UP)
    return subtotal, total - subtotal, percent


def _state(code: str | None) -> dict | None:
    if not code or code not in STATE_NAMES:
        return None
    return {"code": code, "name": STATE_NAMES[code]}


def build_invoice(order: dict, company: dict, plan_name: str, number: str, issued_at: datetime) -> dict:
    subtotal, tax, percent = order_breakdown(order)
    total = subtotal + tax
    seller_gstin = settings.business_gstin_clean or None
    seller_state = _state(seller_gstin[:2] if seller_gstin else None)
    buyer_gstin = (company.get("gstin") or "").strip().upper() or None
    buyer_state = _state(buyer_gstin[:2] if buyer_gstin else company.get("state_code"))
    place_of_supply = buyer_state or seller_state
    intra_state = bool(seller_state and place_of_supply and seller_state["code"] == place_of_supply["code"])
    cgst = sgst = igst = Decimal("0.00")
    if tax:
        if intra_state:
            cgst = (tax / 2).quantize(CENT, ROUND_HALF_UP)
            sgst = tax - cgst
        else:
            igst = tax
    months = order["months"]
    return {
        "number": number,
        "issued_at": issued_at,
        "title": "Tax Invoice" if seller_gstin and tax else "Invoice",
        "seller": {
            "name": settings.business_name,
            "legal_name": settings.business_legal_name or settings.business_name,
            "gstin": seller_gstin,
            "address": settings.business_address or None,
            "email": settings.business_email or None,
            "phone": settings.business_phone or None,
            "state": seller_state,
        },
        "buyer": {
            "name": company.get("name"),
            "legal_name": company.get("legal_name") or company.get("name"),
            "gstin": buyer_gstin,
            "state": buyer_state,
        },
        "place_of_supply": place_of_supply,
        "reverse_charge": False,
        "lines": [{
            "description": f"{settings.business_name} subscription - {plan_name} plan, {order['seats']} employee seats, "
                           f"{months} month{'s' if months > 1 else ''}",
            "sac": settings.billing_sac_code,
            "quantity": months,
            "unit": "month",
            "rate": (subtotal / months).quantize(CENT, ROUND_HALF_UP),
            "amount": subtotal,
        }],
        "subtotal": subtotal,
        "tax_percent": percent,
        "cgst": cgst,
        "sgst": sgst,
        "igst": igst,
        "total": total,
        "amount_in_words": rupees_in_words(total),
        "payment": {
            "method": "Razorpay",
            "order_id": order.get("provider_order_id"),
            "payment_id": order.get("provider_payment_id"),
            "paid_at": order.get("paid_at"),
        },
    }


async def ensure_invoice(db: AsyncDatabase, order: dict) -> dict:
    """Return the order with its invoice, issuing one the first time a paid order is seen."""
    if order.get("invoice") or order.get("status") != "paid":
        return order
    company = await db.companies.find_one({"_id": order["company_id"]}) or {"name": order.get("company_name")}
    plan = await db.subscription_plans.find_one({"code": order["plan_code"]}, {"name": 1})
    issued_at = utcnow()
    invoice = build_invoice(order, company, plan["name"] if plan else order["plan_code"], await next_invoice_number(db, issued_at), issued_at)
    updated = await db.payment_orders.find_one_and_update(
        {"_id": order["_id"], "invoice": {"$exists": False}},
        {"$set": {"invoice": invoice}},
        return_document=ReturnDocument.AFTER,
    )
    if updated is None:
        # A concurrent retry issued it first; keep theirs.
        return await db.payment_orders.find_one({"_id": order["_id"]}) or order
    return updated


def invoice_json(order: dict) -> dict | None:
    invoice = order.get("invoice")
    if not invoice:
        return None

    def party(p: dict) -> dict:
        return {
            "name": p.get("name"), "legalName": p.get("legal_name"), "gstin": p.get("gstin"),
            "address": p.get("address"), "email": p.get("email"), "phone": p.get("phone"), "state": p.get("state"),
        }

    payment = invoice.get("payment") or {}
    return {
        "orderId": order["_id"],
        "number": invoice["number"],
        "issuedAt": invoice["issued_at"],
        "title": invoice["title"],
        "seller": party(invoice["seller"]),
        "buyer": party(invoice["buyer"]),
        "placeOfSupply": invoice.get("place_of_supply"),
        "reverseCharge": invoice.get("reverse_charge", False),
        "lines": [
            {"description": l["description"], "sac": l["sac"], "quantity": l["quantity"], "unit": l["unit"],
             "rate": l["rate"], "amount": l["amount"]}
            for l in invoice["lines"]
        ],
        "subtotal": invoice["subtotal"],
        "taxPercent": invoice["tax_percent"],
        "cgst": invoice["cgst"],
        "sgst": invoice["sgst"],
        "igst": invoice["igst"],
        "total": invoice["total"],
        "amountInWords": invoice["amount_in_words"],
        "payment": {
            "method": payment.get("method"), "orderId": payment.get("order_id"),
            "paymentId": payment.get("payment_id") or order.get("provider_payment_id"), "paidAt": payment.get("paid_at"),
        },
        "refundedAmount": Decimal(order.get("refunded_paise") or 0) / 100,
    }


_ONES = ["", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten", "Eleven", "Twelve",
         "Thirteen", "Fourteen", "Fifteen", "Sixteen", "Seventeen", "Eighteen", "Nineteen"]
_TENS = ["", "", "Twenty", "Thirty", "Forty", "Fifty", "Sixty", "Seventy", "Eighty", "Ninety"]


def _below_thousand(n: int) -> str:
    words = []
    if n >= 100:
        words.append(f"{_ONES[n // 100]} Hundred")
        n %= 100
    if n >= 20:
        words.append(_TENS[n // 10] + (f" {_ONES[n % 10]}" if n % 10 else ""))
    elif n:
        words.append(_ONES[n])
    return " ".join(words)


def _indian_words(n: int) -> str:
    if n == 0:
        return "Zero"
    parts = []
    for size, name in ((10**7, "Crore"), (10**5, "Lakh"), (1000, "Thousand")):
        if n >= size:
            parts.append(f"{_indian_words(n // size) if n // size >= 1000 else _below_thousand(n // size)} {name}")
            n %= size
    if n:
        parts.append(_below_thousand(n))
    return " ".join(parts)


def rupees_in_words(amount: Decimal) -> str:
    paise_total = int((amount * 100).to_integral_value(ROUND_HALF_UP))
    rupees, paise = divmod(paise_total, 100)
    text = f"Rupees {_indian_words(rupees)}"
    if paise:
        text += f" and {_below_thousand(paise)} Paise"
    return text + " Only"


async def _send_receipt(db: AsyncDatabase, order: dict) -> None:
    from app.services.email import send_email

    if not settings.email_configured:
        return
    invoice = order.get("invoice") or {}
    recipients: set[str] = set()
    creator = await db.users.find_one({"_id": order.get("created_by")}, {"email": 1}) if order.get("created_by") else None
    if creator and creator.get("email"):
        recipients.add(creator["email"])
    if not recipients:
        async for user in db.users.find(
            {"company_id": order["company_id"], "role": Role.company_admin.value, "is_active": {"$ne": False}}, {"email": 1}
        ).limit(3):
            if user.get("email"):
                recipients.add(user["email"])
    link = f"{settings.public_web_url.rstrip('/')}/#/billing/invoices/{order['_id']}" if settings.public_web_url else None
    total = invoice.get("total") or Decimal(order["amount_paise"]) / 100
    lines = [
        f"Thank you. We received your payment of Rs. {total}.",
        "",
        f"{invoice.get('title', 'Invoice')} {invoice.get('number', '')}",
        invoice.get("lines", [{}])[0].get("description", ""),
        f"Razorpay payment ID: {order.get('provider_payment_id') or '-'}",
        "",
        f"View or download your invoice: {link}" if link else "Your invoice is on the Billing page of the admin console.",
        "",
        f"- {settings.business_legal_name or settings.business_name}",
    ]
    for to in recipients:
        try:
            await send_email(to, f"Payment received - {invoice.get('number', 'subscription renewed')}", "\n".join(lines))
        except Exception as exc:  # noqa: BLE001
            logger.warning("Could not email payment receipt for order %s to %s: %s", order["_id"], to, exc)


def send_receipt_later(db: AsyncDatabase, order: dict) -> None:
    """Email the receipt without delaying the checkout response or Razorpay's webhook (5 s timeout)."""
    task = asyncio.get_running_loop().create_task(_send_receipt(db, order))
    _background.add(task)
    task.add_done_callback(_background.discard)


async def drain_receipts() -> None:
    if _background:
        await asyncio.gather(*_background, return_exceptions=True)
