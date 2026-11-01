"""Admin console, super admin portal and employee app endpoints added for the production release."""
import json
from datetime import timedelta
from decimal import Decimal

import pytest
from httpx import ASGITransport, AsyncClient

import factories as f
from app.db.mongo import new_id, utcnow
from app.main import app
from app.models import PaymentStatus, Role

JPEG = b"\xff\xd8\xff\xe0" + b"\x00" * 64
SUPPLIER_GSTIN = "29ABCDE1234F1Z5"


def client():
    return AsyncClient(transport=ASGITransport(app=app, raise_app_exceptions=False), base_url="http://test")


async def seed(db, *, seats=10):
    await f.plan(db, "starter", "Starter", 999, 50)
    await f.plan(db, "trial", "Trial", 0, 5)
    company = await f.company(db, "Acme Builders", activation_code="ACME")
    branch = await f.branch(db, company["_id"])
    category = await f.category(db, company["_id"], "Cement")
    await f.user(db, company["_id"], Role.company_admin, email="admin@acme.in", password="AdminPass!123")
    await f.user(db, None, Role.super_admin, email="root@platform.in", password="RootPassword!1")
    employee = await f.employee(db, company["_id"], branch_id=branch["_id"], name="Ravi", code="E1", mobile="9876500001")
    await f.subscription(db, company["_id"], "starter", seats)
    return {"company": company, "branch": branch, "category": category, "employee": employee}


async def login_admin(c, email="admin@acme.in", password="AdminPass!123"):
    r = await c.post("/v1/admin/auth/login", json={"email": email, "password": password})
    assert r.status_code == 200, r.text
    return {"Authorization": f"Bearer {r.json()['accessToken']}"}


async def login_employee(c, mobile="9876500001"):
    r = await c.post("/v1/auth/otp/request", json={"mobile": mobile})
    assert r.status_code == 200, r.text
    r = await c.post("/v1/auth/otp/verify", json={"mobile": mobile, "otp": "123456"})
    assert r.status_code == 200, r.text
    body = r.json()
    return {"Authorization": f"Bearer {body['accessToken']}", "X-Company-Id": body["employee"]["companyId"]}


async def upload(c, headers, key, number, amount, category_id=None):
    payload = {"editedData": {"invoiceNumber": number, "gstin": SUPPLIER_GSTIN, "vendorName": "Shree Cement",
                              "netAmount": amount, "invoiceDate": "2026-10-15"}}
    if category_id:
        payload["categoryId"] = category_id
    files = {kind: (f"{kind}.jpg", JPEG + kind.encode(), "image/jpeg") for kind in ("original", "compressed", "thumbnail")}
    r = await c.post("/v1/invoices/upload", headers=headers, data={"idempotencyKey": key, "payload": json.dumps(payload)}, files=files)
    assert r.status_code == 201, r.text
    return r.json()["id"]


@pytest.mark.asyncio
async def test_invoice_review_lifecycle(mongo):
    s = await seed(mongo)
    async with client() as c:
        emp = await login_employee(c)
        first = await upload(c, emp, "k1", "INV-1", 1180, s["category"]["_id"])
        second = await upload(c, emp, "k2", "INV-2", 500)
        third = await upload(c, emp, "k3", "INV-3", 250)
        adm = await login_admin(c)

        listing = (await c.get("/v1/admin/invoices", headers=adm, params={"sort": "amount_desc"})).json()
        assert [i["invoiceNumber"] for i in listing["items"]] == ["INV-1", "INV-2", "INV-3"]
        top = listing["items"][0]
        assert top["employeeName"] == "Ravi" and top["employeeCode"] == "E1"
        assert top["branchName"] == "HQ" and top["categoryName"] == "Cement"
        filtered = (await c.get("/v1/admin/invoices", headers=adm, params={"categoryId": s["category"]["_id"]})).json()
        assert filtered["total"] == 1

        r = await c.post(f"/v1/admin/invoices/{second}/return", headers=adm, json={"remarks": "Amount unclear"})
        assert r.status_code == 200, r.text
        r = await c.post(f"/v1/admin/invoices/{second}/return", headers=adm, json={"remarks": "Again"})
        assert r.status_code == 409

        # The employee fixes the returned bill and sends it back.
        r = await c.post(f"/v1/invoices/{first}/resubmit", headers=emp, json={"editedData": {"netAmount": 1}})
        assert r.status_code == 409
        r = await c.post(f"/v1/invoices/{second}/resubmit", headers=emp,
                         json={"editedData": {"netAmount": 550}, "note": "Corrected total"})
        assert r.status_code == 200, r.text
        assert r.json()["approvalStatus"] == "pending" and Decimal(str(r.json()["netAmount"])) == Decimal("550")
        mine = (await c.get(f"/v1/invoices/{second}", headers=emp)).json()
        assert [h["action"] for h in mine["history"]] == ["uploaded", "returned", "resubmitted"]
        assert mine["history"][2]["remarks"] == "Corrected total"

        r = await c.patch(f"/v1/admin/invoices/{third}", headers=adm,
                          json={"editedData": {"vendorName": "Shree Cement Ltd"}, "categoryId": s["category"]["_id"]})
        assert r.status_code == 200, r.text
        assert r.json()["vendorName"] == "Shree Cement Ltd" and r.json()["categoryName"] == "Cement"
        assert r.json()["history"][-1]["action"] == "edited"

        r = await c.post("/v1/admin/invoices/bulk-decision", headers=adm,
                         json={"ids": [first, second, third], "status": "approved"})
        assert r.json() == {"updated": 3, "skipped": 0}
        r = await c.post("/v1/admin/invoices/bulk-decision", headers=adm, json={"ids": [first], "status": "approved"})
        assert r.json() == {"updated": 0, "skipped": 1}
        r = await c.post("/v1/admin/invoices/bulk-decision", headers=adm, json={"ids": [first], "status": "rejected"})
        assert r.status_code == 400  # remarks required

        detail = (await c.get(f"/v1/admin/invoices/{second}", headers=adm)).json()
        assert detail["history"][-1]["action"] == "approved" and detail["history"][-1]["byName"] == "admin@acme.in"

        r = await c.get("/v1/admin/invoices/export", headers=adm, params={"format": "csv"})
        assert r.status_code == 200
        assert r.content.startswith("\ufeff".encode())
        assert "attachment" in r.headers["content-disposition"]
        assert r.text.count("\n") == 4  # header + 3 bills
        r = await c.get("/v1/admin/invoices/export", headers=adm, params={"format": "xlsx"})
        assert r.status_code == 200 and r.content[:2] == b"PK"

        dash = (await c.get("/v1/admin/dashboard", headers=adm)).json()
        assert dash["approvedCount"] == 3 and Decimal(str(dash["approvedAmount"])) == Decimal("1980.00")
        assert dash["todayUploads"] == 3 and len(dash["daily"]) == 14 and dash["daily"][-1]["count"] == 3
        top_category = dash["topCategories"][0]
        assert top_category["name"] == "Cement" and top_category["count"] == 2
        assert Decimal(str(top_category["amount"])) == Decimal("1430.00")
        assert dash["seats"] == {"used": 1, "limit": 10}

        audit = (await c.get("/v1/admin/company/audit", headers=adm)).json()
        actions = {item["action"] for item in audit["items"]}
        assert {"invoice.returned", "invoice.edited", "invoice.bulk_decision"} <= actions


@pytest.mark.asyncio
async def test_employee_rules_seats_and_devices(mongo):
    s = await seed(mongo, seats=2)
    other = await f.company(mongo, "Other Firm")
    await f.subscription(mongo, other["_id"], "starter", 5)
    await f.employee(mongo, other["_id"], name="Elsewhere", code="X1", mobile="9876500009")
    async with client() as c:
        adm = await login_admin(c)
        r = await c.post("/v1/admin/employees", headers=adm, json={"name": "Dup", "mobile": "+91 98765 00009", "employeeCode": "E9"})
        assert r.status_code == 409 and "another company" in r.json()["message"]
        r = await c.post("/v1/admin/employees", headers=adm, json={"name": "Sita", "mobile": "09876500002", "employeeCode": "E2"})
        assert r.status_code == 201, r.text
        assert r.json()["mobile"] == "9876500002"
        sita = r.json()["id"]
        listing = (await c.get("/v1/admin/employees", headers=adm)).json()
        assert listing["seats"] == {"used": 2, "limit": 2}
        r = await c.post("/v1/admin/employees", headers=adm, json={"name": "Full", "mobile": "9876500003", "employeeCode": "E3"})
        assert r.status_code == 409
        r = await c.patch(f"/v1/admin/employees/{sita}", headers=adm, json={"isActive": False})
        assert r.status_code == 200 and r.json()["isActive"] is False
        r = await c.post("/v1/admin/employees", headers=adm, json={"name": "Full", "mobile": "9876500003", "employeeCode": "E3"})
        assert r.status_code == 201
        r = await c.patch(f"/v1/admin/employees/{sita}", headers=adm, json={"isActive": True})
        assert r.status_code == 409  # no free seat

        # Login accepts any common way of typing the number.
        emp = await login_employee(c, "+919876500001")
        r = await c.post("/v1/devices/register", headers=emp, json={"deviceId": "phone-1", "platform": "android", "appVersion": "1.0.0", "fcmToken": "tok-1"})
        assert r.status_code == 200, r.text
        await mongo.devices.insert_one({"_id": new_id(), "company_id": s["company"]["_id"], "device_id": "old-phone",
                                        "employee_id": "someone-else", "fcm_token": "tok-1", "created_at": utcnow()})
        r = await c.post("/v1/devices/register", headers=emp, json={"deviceId": "phone-1", "platform": "android", "appVersion": "1.0.0", "fcmToken": "tok-1"})
        assert await mongo.devices.count_documents({"fcm_token": "tok-1"}) == 1
        r = await c.delete("/v1/devices/phone-1", headers=emp)
        assert r.status_code == 204
        assert await mongo.devices.count_documents({}) == 0


@pytest.mark.asyncio
async def test_company_self_delete_and_suspension_codes(mongo):
    s = await seed(mongo)
    async with client() as c:
        emp = await login_employee(c)
        await upload(c, emp, "k1", "INV-1", 100)
        adm = await login_admin(c)
        r = await c.patch("/v1/admin/company/settings", headers=adm, json={"features": {"itc": True}, "requiresGps": True})
        assert r.status_code == 200 and r.json()["features_json"] == {}
        r = await c.post("/v1/admin/company/delete", headers=adm, json={"password": "wrong", "confirmName": "Acme Builders"})
        assert r.status_code == 400
        r = await c.post("/v1/admin/company/delete", headers=adm, json={"password": "AdminPass!123", "confirmName": "acme"})
        assert r.status_code == 400
        r = await c.post("/v1/admin/company/delete", headers=adm, json={"password": "AdminPass!123", "confirmName": " acme builders "})
        assert r.status_code == 204, r.text
        company_id = s["company"]["_id"]
        for name in ("companies", "users", "employees", "invoices", "subscriptions", "branches"):
            key = "_id" if name == "companies" else "company_id"
            assert await mongo[name].count_documents({key: company_id}) == 0, name
        r = await c.get("/v1/admin/dashboard", headers=adm)
        assert r.status_code in (401, 403)


@pytest.mark.asyncio
async def test_super_admin_portal(mongo):
    s = await seed(mongo)
    company_id = s["company"]["_id"]
    await mongo.payment_orders.insert_one({
        "_id": new_id(), "company_id": company_id, "plan_code": "starter", "seats": 10, "months": 1,
        "amount_paise": 117882, "currency": "INR", "status": PaymentStatus.paid.value, "provider_order_id": "order_1",
        "provider_payment_id": "pay_1", "created_at": utcnow(), "paid_at": utcnow(),
    })
    async with client() as c:
        su = await login_admin(c, "root@platform.in", "RootPassword!1")
        listing = (await c.get("/v1/super/companies", headers=su, params={"q": "admin@acme"})).json()
        assert listing["total"] == 1
        item = listing["items"][0]
        assert item["planCode"] == "starter" and item["planName"] == "Starter" and item["seats"] == 10
        assert item["employeeCount"] == 1 and item["adminEmail"] == "admin@acme.in" and item["subscriptionStatus"] == "active"

        detail = (await c.get(f"/v1/super/companies/{company_id}", headers=su)).json()
        assert detail["usage"]["activeEmployees"] == 1 and len(detail["payments"]) == 1
        admin_id = detail["admins"][0]["id"]

        r = await c.patch(f"/v1/super/companies/{company_id}", headers=su, json={"legalName": "Acme Builders Pvt Ltd"})
        assert r.status_code == 200 and r.json()["legalName"] == "Acme Builders Pvt Ltd"

        r = await c.put(f"/v1/super/companies/{company_id}/subscription", headers=su, json={"planCode": "starter", "seats": 51})
        assert r.status_code == 400
        ends = (utcnow() + timedelta(days=90)).isoformat()
        r = await c.put(f"/v1/super/companies/{company_id}/subscription", headers=su, json={"planCode": "starter", "seats": 20, "endsAt": ends})
        assert r.status_code == 200, r.text
        assert r.json()["seats"] == 20

        old_session = await login_admin(c)
        r = await c.post(f"/v1/super/companies/{company_id}/admins/{admin_id}/reset-password", headers=su)
        temporary = r.json()["temporaryPassword"]
        assert len(temporary) >= 10
        assert (await c.get("/v1/admin/dashboard", headers=old_session)).status_code == 401
        await login_admin(c, "admin@acme.in", temporary)

        r = await c.post(f"/v1/super/companies/{company_id}/reactivate", headers=su)
        assert r.status_code == 409
        r = await c.post(f"/v1/super/companies/{company_id}/suspend", headers=su)
        assert r.status_code == 200
        r = await c.post("/v1/admin/auth/login", json={"email": "admin@acme.in", "password": temporary})
        assert r.status_code == 403 and r.json()["code"] == "COMPANY_SUSPENDED"

        plans = (await c.get("/v1/super/plans", headers=su)).json()["items"]
        starter = next(p for p in plans if p["code"] == "starter")
        assert starter["subscriberCount"] == 1
        r = await c.put(f"/v1/super/plans/{starter['id']}", headers=su,
                        json={"code": "starter-v2", "name": "Starter", "monthlyPriceInr": 999, "maxEmployees": 50})
        assert r.status_code == 409

        payments = (await c.get("/v1/super/payments", headers=su, params={"q": "acme"})).json()
        assert payments["total"] == 1 and payments["totals"]["paidCount"] == 1
        assert Decimal(str(payments["totals"]["paidInr"])) == Decimal("1178.82")

        metrics = (await c.get("/v1/super/metrics", headers=su)).json()
        assert metrics["companies"]["all"] == 1 and metrics["companies"]["suspended"] == 1
        assert Decimal(str(metrics["revenueTotalInr"])) == Decimal("1178.82") and len(metrics["daily"]) == 30

        audit = (await c.get("/v1/super/audit", headers=su, params={"companyId": company_id})).json()
        assert {"company.suspended", "subscription.changed", "admin.password_reset"} <= {i["action"] for i in audit["items"]}
        assert audit["items"][0]["companyName"] == "Acme Builders"

        r = await c.post(f"/v1/super/companies/{company_id}/delete", headers=su, json={"confirmName": "nope"})
        assert r.status_code == 400
        r = await c.post(f"/v1/super/companies/{company_id}/delete", headers=su, json={"confirmName": "Acme Builders"})
        assert r.status_code == 204
        assert await mongo.companies.count_documents({}) == 0
        order = await mongo.payment_orders.find_one({})
        assert order["company_name"] == "Acme Builders"


@pytest.mark.asyncio
async def test_billing_overview_flags_and_seat_floor(mongo, monkeypatch):
    from app.core.config import settings

    await seed(mongo)
    async with client() as c:
        adm = await login_admin(c)
        body = (await c.get("/v1/admin/billing", headers=adm)).json()
        assert body["activeEmployees"] == 1
        flags = {p["code"]: p["purchasable"] for p in body["plans"]}
        assert flags == {"starter": True, "trial": False}
        monkeypatch.setattr(settings, "razorpay_key_id", "rzp_test_x")
        monkeypatch.setattr(settings, "razorpay_key_secret", "secret")
        monkeypatch.setattr(settings, "razorpay_webhook_secret", "whsec")
        await mongo.employees.insert_one({**(await mongo.employees.find_one({})), "_id": new_id(), "user_id": new_id(),
                                          "mobile": "9876500005", "employee_code": "E5"})
        r = await c.post("/v1/admin/billing/orders", headers=adm, json={"planCode": "starter", "seats": 1, "months": 1})
        assert r.status_code == 400 and "2 active employees" in r.json()["message"]


@pytest.mark.asyncio
async def test_interrupted_payment_credit_is_completed_once(mongo):
    from app.services.payments import mark_paid

    s = await seed(mongo)
    company_id = s["company"]["_id"]
    before = (await mongo.subscriptions.find_one({"company_id": company_id}))["ends_at"]
    await mongo.payment_orders.insert_one({
        "_id": new_id(), "company_id": company_id, "plan_code": "starter", "seats": 10, "months": 1,
        "amount_paise": 99900, "currency": "INR", "status": PaymentStatus.paid.value, "credited": False,
        "provider_order_id": "order_crash", "created_at": utcnow(), "paid_at": utcnow(),
    })
    await mark_paid(mongo, "order_crash", "pay_1")
    await mark_paid(mongo, "order_crash", "pay_1")
    sub = await mongo.subscriptions.find_one({"company_id": company_id})
    assert (sub["ends_at"] - before).days == 30
    assert (await mongo.payment_orders.find_one({"provider_order_id": "order_crash"}))["credited"] is True


@pytest.mark.asyncio
async def test_itc_reimport_replaces_rows_and_reminders_dedupe(mongo):
    await seed(mongo)
    csv_text = "GSTIN of supplier,Trade/Legal name,Invoice number,Invoice Date,Taxable Value,Invoice Value\n" \
               "27AAAAA0000A1Z5,Other Supplier,X-1,15-10-2026,100,118\n"
    async with client() as c:
        emp = await login_employee(c)
        await upload(c, emp, "k1", "INV-1", 1180)
        adm = await login_admin(c)
        for _ in range(2):
            r = await c.post("/v1/admin/itc/import", headers=adm, data={"period": "2026-10", "returnType": "2B"},
                             files={"file": ("2b.csv", csv_text.encode(), "text/csv")})
            assert r.status_code == 200, r.text
        assert await mongo.gstr_inward_rows.count_documents({}) == 1
        imports = (await c.get("/v1/admin/itc/imports", headers=adm)).json()["items"]
        assert len(imports) == 1

        first = (await c.post("/v1/admin/itc/remind-missing", headers=adm, params={"period": "2026-10"})).json()
        second = (await c.post("/v1/admin/itc/remind-missing", headers=adm, params={"period": "2026-10"})).json()
        assert first["count"] == 1 and second["count"] == 0 and second["skipped"] == 1

        r = await c.delete(f"/v1/admin/itc/imports/{imports[0]['id']}", headers=adm)
        assert r.status_code == 204
        assert await mongo.gstr_inward_rows.count_documents({}) == 0
        summary = (await c.get("/v1/admin/itc/summary", headers=adm, params={"period": "2026-10"})).json()
        assert summary["counts"]["missing_in_books"] == 0 and summary["counts"]["missing_in_2b"] == 1
