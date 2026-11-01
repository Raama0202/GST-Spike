"""Selling subscriptions: GST invoices, refunds, amount checks, public pages, renewal reminders."""
import hashlib
import hmac
import json
from datetime import datetime, timedelta, timezone
from decimal import Decimal

import pytest

import factories as f
from app.core.config import settings
from app.models import PaymentStatus, Role
from app.services import billing_invoice, renewals
from test_production import _configure_razorpay, admin_headers, client, seed

SELLER_GSTIN = "29ABCDE1234F1Z5"  # Karnataka


def _business(monkeypatch, gstin=SELLER_GSTIN):
    monkeypatch.setattr(settings, "business_name", "GST Expense")
    monkeypatch.setattr(settings, "business_legal_name", "Expense Labs Pvt Ltd")
    monkeypatch.setattr(settings, "business_gstin", gstin)
    monkeypatch.setattr(settings, "business_address", "1 MG Road, Bengaluru 560001")
    monkeypatch.setattr(settings, "business_email", "billing@gstexpense.in")
    monkeypatch.setattr(settings, "business_phone", "+91 80 1234 5678")


def _email(monkeypatch) -> list[tuple[str, str, str]]:
    monkeypatch.setattr(settings, "email_provider", "brevo")
    monkeypatch.setattr(settings, "brevo_api_key", "test")
    monkeypatch.setattr(settings, "email_from", "noreply@gstexpense.in")
    outbox: list[tuple[str, str, str]] = []

    async def fake_send(to, subject, text, html=None):
        outbox.append((to, subject, text))

    import app.services.email as email

    monkeypatch.setattr(email, "send_email", fake_send)
    return outbox


async def _pay(c, headers, plan="starter", months=1) -> dict:
    order = await c.post("/v1/admin/billing/orders", headers=headers, json={"planCode": plan, "seats": 10, "months": months})
    assert order.status_code == 201, order.text
    body = order.json()
    sig = hmac.new(b"secret_abc", f"{body['orderId']}|pay_{body['orderId']}".encode(), hashlib.sha256).hexdigest()
    paid = await c.post("/v1/admin/billing/verify", headers=headers, json={
        "razorpayOrderId": body["orderId"], "razorpayPaymentId": f"pay_{body['orderId']}", "razorpaySignature": sig})
    assert paid.status_code == 200 and paid.json()["status"] == "paid", paid.text
    return paid.json()


def _hook(event: dict, event_id: str) -> tuple[bytes, dict]:
    raw = json.dumps(event).encode()
    return raw, {"X-Razorpay-Signature": hmac.new(b"whsec_abc", raw, hashlib.sha256).hexdigest(), "X-Razorpay-Event-Id": event_id}


@pytest.mark.asyncio
async def test_paid_order_gets_intra_state_tax_invoice_and_receipt(mongo, monkeypatch):
    company_id = await seed(mongo)
    await mongo.companies.update_one({"_id": company_id}, {"$set": {"gstin": "29AAACB1234C1Z2", "legal_name": "Prod Co Pvt Ltd"}})
    _configure_razorpay(monkeypatch)
    _business(monkeypatch)
    outbox = _email(monkeypatch)
    async with client() as c:
        headers = await admin_headers(c)
        paid = await _pay(c, headers, months=2)
        await billing_invoice.drain_receipts()
        invoice = (await c.get(f"/v1/admin/billing/orders/{paid['id']}/invoice", headers=headers)).json()
        again = (await c.get(f"/v1/admin/billing/orders/{paid['id']}/invoice", headers=headers)).json()
        orders = (await c.get("/v1/admin/billing", headers=headers)).json()

    fy = billing_invoice.financial_year(datetime.now(timezone.utc))
    assert invoice["number"] == f"GSTX/{fy}/00001" == again["number"]
    assert invoice["title"] == "Tax Invoice"
    assert invoice["seller"]["gstin"] == SELLER_GSTIN and invoice["seller"]["legalName"] == "Expense Labs Pvt Ltd"
    assert invoice["buyer"]["gstin"] == "29AAACB1234C1Z2" and invoice["placeOfSupply"]["code"] == "29"
    assert Decimal(str(invoice["subtotal"])) == Decimal("1998.00")
    assert Decimal(str(invoice["cgst"])) == Decimal(str(invoice["sgst"])) == Decimal("179.82")
    assert Decimal(str(invoice["igst"])) == 0 and Decimal(str(invoice["total"])) == Decimal("2357.64")
    assert invoice["lines"][0]["sac"] == "997331" and invoice["lines"][0]["quantity"] == 2
    assert invoice["amountInWords"] == "Rupees Two Thousand Three Hundred Fifty Seven and Sixty Four Paise Only"
    assert orders["orders"][0]["invoiceNumber"] == invoice["number"]
    assert [to for to, *_ in outbox] == ["admin@prod.co"] and invoice["number"] in outbox[0][1]


@pytest.mark.asyncio
async def test_inter_state_buyer_pays_igst_and_numbers_are_consecutive(mongo, monkeypatch):
    company_id = await seed(mongo)
    await mongo.companies.update_one({"_id": company_id}, {"$set": {"gstin": "27AAACB1234C1Z6"}})
    _configure_razorpay(monkeypatch)
    _business(monkeypatch)
    async with client() as c:
        headers = await admin_headers(c)
        first = await _pay(c, headers)
        second = await _pay(c, headers)
        one = (await c.get(f"/v1/admin/billing/orders/{first['id']}/invoice", headers=headers)).json()
        two = (await c.get(f"/v1/admin/billing/orders/{second['id']}/invoice", headers=headers)).json()
        root = await admin_headers(c, "root@prod.co", "RootPassword!1")
        as_super = (await c.get(f"/v1/super/payments/{second['id']}/invoice", headers=root)).json()

    assert one["number"].endswith("/00001") and two["number"].endswith("/00002") and as_super["number"] == two["number"]
    assert one["placeOfSupply"]["code"] == "27"
    assert Decimal(str(one["igst"])) == Decimal("179.82") and Decimal(str(one["cgst"])) == 0


@pytest.mark.asyncio
async def test_unregistered_seller_charges_no_gst(mongo, monkeypatch):
    await seed(mongo)
    _configure_razorpay(monkeypatch)
    _business(monkeypatch, gstin="")
    async with client() as c:
        headers = await admin_headers(c)
        overview = (await c.get("/v1/admin/billing", headers=headers)).json()
        paid = await _pay(c, headers)
        invoice = (await c.get(f"/v1/admin/billing/orders/{paid['id']}/invoice", headers=headers)).json()

    assert overview["taxPercent"] == 0 and overview["liveMode"] is False
    assert Decimal(str(paid["amount"])) == Decimal("999")
    assert invoice["title"] == "Invoice" and invoice["seller"]["gstin"] is None
    assert Decimal(str(invoice["total"])) == Decimal("999.00") and Decimal(str(invoice["cgst"])) == 0


@pytest.mark.asyncio
async def test_invoice_needs_success_and_is_company_scoped(mongo, monkeypatch):
    await seed(mongo)
    other = await f.company(mongo, "Other Co")
    await f.user(mongo, other["_id"], Role.company_admin, email="admin@other.co", password="Password!123")
    await f.subscription(mongo, other["_id"])
    _configure_razorpay(monkeypatch)
    async with client() as c:
        headers = await admin_headers(c)
        order = (await c.post("/v1/admin/billing/orders", headers=headers, json={"planCode": "starter", "seats": 5})).json()
        pending = await c.get(f"/v1/admin/billing/orders/{order['id']}/invoice", headers=headers)
        paid = await _pay(c, headers)
        foreign = await c.get(f"/v1/admin/billing/orders/{paid['id']}/invoice", headers=await admin_headers(c, "admin@other.co"))
    assert pending.status_code == 409
    assert foreign.status_code == 404


@pytest.mark.asyncio
async def test_webhook_with_wrong_amount_is_not_credited(mongo, monkeypatch):
    company_id = await seed(mongo, expired=True)
    _configure_razorpay(monkeypatch)
    async with client() as c:
        headers = await admin_headers(c)
        order = (await c.post("/v1/admin/billing/orders", headers=headers, json={"planCode": "starter", "seats": 5})).json()
        raw, hook_headers = _hook({"event": "payment.captured", "payload": {"payment": {"entity": {
            "id": "pay_x", "order_id": order["orderId"], "amount": order["amountPaise"] - 100}}}}, "evt_amount")
        hook = await c.post("/v1/payments/razorpay/webhook", content=raw, headers=hook_headers)
    assert hook.status_code == 200
    stored = await mongo.payment_orders.find_one({})
    assert stored["status"] == PaymentStatus.created.value and "invoice" not in stored
    assert await mongo.subscriptions.count_documents({"company_id": company_id}) == 1


@pytest.mark.asyncio
async def test_refund_webhooks_mark_partial_then_full(mongo, monkeypatch):
    await seed(mongo)
    _configure_razorpay(monkeypatch)
    async with client() as c:
        headers = await admin_headers(c)
        paid = await _pay(c, headers)
        payment_id = paid["providerPaymentId"]
        for event_id, refunded in (("evt_r1", 50000), ("evt_r2", int(Decimal(str(paid["amount"])) * 100))):
            raw, hook_headers = _hook({"event": "refund.processed", "payload": {
                "refund": {"entity": {"id": f"rfnd_{event_id}", "payment_id": payment_id, "amount": refunded}},
                "payment": {"entity": {"id": payment_id, "order_id": paid["providerOrderId"], "amount_refunded": refunded}},
            }}, event_id)
            assert (await c.post("/v1/payments/razorpay/webhook", content=raw, headers=hook_headers)).status_code == 200
            stored = await mongo.payment_orders.find_one({})
            if event_id == "evt_r1":
                assert stored["status"] == PaymentStatus.paid.value and stored["refunded_paise"] == 50000
        root = await admin_headers(c, "root@prod.co", "RootPassword!1")
        totals = (await c.get("/v1/super/payments", headers=root)).json()["totals"]
        invoice = (await c.get(f"/v1/admin/billing/orders/{paid['id']}/invoice", headers=headers)).json()
    stored = await mongo.payment_orders.find_one({})
    assert stored["status"] == PaymentStatus.refunded.value
    assert Decimal(str(totals["netInr"])) == 0 and Decimal(str(totals["refundedInr"])) == Decimal(str(totals["paidInr"]))
    assert Decimal(str(invoice["refundedAmount"])) == Decimal(str(invoice["total"]))
    assert await mongo.audit_logs.count_documents({"action": "billing.refunded"}) == 2


@pytest.mark.asyncio
async def test_public_business_and_plans(mongo, monkeypatch):
    await seed(mongo)
    await f.plan(mongo, "trial", "Trial", 0, 5)
    _business(monkeypatch)
    async with client() as c:
        business = (await c.get("/v1/public/business")).json()
        plans = (await c.get("/v1/public/plans")).json()
    assert business["legalName"] == "Expense Labs Pvt Ltd" and business["gstin"] == SELLER_GSTIN
    assert business["email"] == "billing@gstexpense.in" and business["taxPercent"] == 18.0
    assert [p["code"] for p in plans["items"]] == ["starter", "growth"] and plans["taxPercent"] == 18.0


def test_rupees_in_words_uses_indian_grouping():
    assert billing_invoice.rupees_in_words(Decimal("12345678.05")) == (
        "Rupees One Crore Twenty Three Lakh Forty Five Thousand Six Hundred Seventy Eight and Five Paise Only")
    assert billing_invoice.rupees_in_words(Decimal("1179")) == "Rupees One Thousand One Hundred Seventy Nine Only"


def test_financial_year_boundary():
    assert billing_invoice.financial_year(datetime(2026, 3, 31, 18, 31, tzinfo=timezone.utc)) == "2026-27"  # 00:01 IST, 1 Apr
    assert billing_invoice.financial_year(datetime(2026, 3, 31, 18, 29, tzinfo=timezone.utc)) == "2025-26"


@pytest.mark.asyncio
async def test_renewal_reminders_once_per_threshold(mongo, monkeypatch):
    company_id = await seed(mongo)
    outbox = _email(monkeypatch)
    monkeypatch.setattr(settings, "public_web_url", "https://console.gstexpense.in")
    subscription = await mongo.subscriptions.find_one({"company_id": company_id})

    async def ends_in(days: float):
        await mongo.subscriptions.update_one(
            {"_id": subscription["_id"]}, {"$set": {"ends_at": datetime.now(timezone.utc) + timedelta(days=days)}})

    await ends_in(20)
    assert await renewals.send_renewal_reminders(mongo) == 0
    await ends_in(6.5)
    assert await renewals.send_renewal_reminders(mongo) == 1
    assert await renewals.send_renewal_reminders(mongo) == 0
    assert "7 days" in outbox[0][1] and "https://console.gstexpense.in/#/billing" in outbox[0][2]
    await ends_in(0.5)
    assert await renewals.send_renewal_reminders(mongo) == 1
    await ends_in(-1)
    assert await renewals.send_renewal_reminders(mongo) == 1
    assert "expired" in outbox[-1][1]
    assert len(outbox) == 3


@pytest.mark.asyncio
async def test_renewal_reminder_ignores_superseded_subscription(mongo, monkeypatch):
    company_id = await seed(mongo, expired=True)
    outbox = _email(monkeypatch)
    await f.subscription(mongo, company_id, days=90)
    assert await renewals.send_renewal_reminders(mongo) == 0
    assert outbox == []
