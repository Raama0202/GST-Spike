"""End-to-end journey across all clients, using the exact requests each app sends.

Super admin (web) -> company admin (web / Android / iOS admin) -> employee
(Android / iOS scanner) -> back to the admin, then billing-free renewal paths.
"""
import json

import pytest
from httpx import ASGITransport, AsyncClient

from app.core.security import hash_password
from app.main import app
from app.models import Role, SubscriptionPlan, User

JPEG = b"\xff\xd8\xff\xe0" + b"\x00" * 64


async def seed_platform(session_factory):
    async with session_factory() as db:
        db.add(SubscriptionPlan(code="growth", name="Growth", monthly_price_inr=2499, max_employees=50))
        db.add(User(email="root@platform.app", password_hash=hash_password("RootPassword!1"), role=Role.super_admin))
        await db.commit()


def bearer(token, company_id=None, device="device-1"):
    headers = {"Authorization": f"Bearer {token}", "X-Device-Id": device}
    if company_id:
        headers["X-Company-Id"] = str(company_id)
    return headers


@pytest.mark.asyncio
async def test_full_platform_journey(db_engine):
    _, session_factory, _ = db_engine
    await seed_platform(session_factory)

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as c:
        # --- Super admin (web dashboard) creates and activates a company ---
        r = await c.post("/v1/admin/auth/login", json={"email": "root@platform.app", "password": "RootPassword!1"})
        assert r.status_code == 200, r.text
        root = r.json()
        assert root["user"]["role"] == "super_admin" and root["billingRequired"] is False
        su = bearer(root["accessToken"])

        r = await c.get("/v1/super/plans", headers=su)
        assert [p["code"] for p in r.json()["items"]] == ["growth"]

        r = await c.post("/v1/super/companies", headers=su, json={
            "name": "Sunrise Traders", "industry": "Retail", "adminEmail": "owner@sunrise.in",
            "adminPassword": "OwnerPass!23", "planCode": "growth", "seats": 5, "subscriptionDays": 30,
        })
        assert r.status_code == 201, r.text
        company = r.json()
        assert company["status"] == "pending"

        # Pending company cannot sign in until activated.
        r = await c.post("/v1/admin/auth/login", json={"email": "owner@sunrise.in", "password": "OwnerPass!23"})
        assert r.status_code in (402, 403), r.text

        r = await c.post("/v1/super/companies/activate", json={"activationCode": company["activationCode"]})
        assert r.status_code == 200 and r.json()["status"] == "active"

        r = await c.get("/v1/super/companies", headers=su, params={"q": "sunrise"})
        body = r.json()
        assert body["total"] == 1 and body["items"][0]["status"] == "active"
        assert body["counts"]["active"] == 1

        # --- Company admin (web / Flutter admin / iOS admin) sets up the tenant ---
        r = await c.post("/v1/admin/auth/login", json={"email": "owner@sunrise.in", "password": "OwnerPass!23"})
        assert r.status_code == 200, r.text
        owner = r.json()
        assert owner["billingRequired"] is False and owner["refreshToken"]
        company_id = owner["user"]["companyId"]
        adm = bearer(owner["accessToken"], company_id)

        r = await c.post("/v1/admin/company/branches", headers=adm, json={"name": "Hyderabad", "code": "HYD"})
        assert r.status_code == 201, r.text
        branch_id = r.json()["id"]
        r = await c.post("/v1/admin/company/categories", headers=adm, json={"name": "Travel", "sortOrder": 1})
        assert r.status_code == 201, r.text
        category_id = r.json()["id"]

        r = await c.patch("/v1/admin/company/settings", headers=adm, json={
            "primaryColorHex": "0B5FFF", "duplicateCheckEnabled": True, "requiresGps": False,
        })
        assert r.status_code == 200, r.text
        settings_body = (await c.get("/v1/admin/company/settings", headers=adm)).json()
        assert settings_body["primary_color_hex"] == "0B5FFF"  # read as snake_case by all admin clients

        r = await c.post("/v1/admin/employees", headers=adm, json={
            "name": "Ravi Kumar", "mobile": "9876543210", "employeeCode": "SUN-001", "branchId": branch_id,
        })
        assert r.status_code == 201, r.text
        employee_id = r.json()["id"]

        r = await c.get("/v1/admin/employees", headers=adm, params={"page": 1, "pageSize": 50})
        assert r.json()["total"] == 1

        # --- Employee (Android / iOS scanner) signs in with OTP ---
        r = await c.post("/v1/auth/otp/request", json={"mobile": "9876543210"})
        assert r.status_code == 200, r.text
        r = await c.post("/v1/auth/otp/verify", json={"mobile": "9876543210", "otp": "123456"})
        assert r.status_code == 200, r.text
        emp_auth = r.json()
        assert emp_auth["employee"]["companyId"] == company_id
        emp = bearer(emp_auth["accessToken"], company_id, device="phone-ravi")

        r = await c.get("/v1/employees/me", headers=emp)
        assert r.status_code == 200 and r.json()["name"] == "Ravi Kumar"

        config = (await c.get("/v1/company/config", headers=emp)).json()
        assert config["companyName"] == "Sunrise Traders"
        assert config["primaryColorHex"] == "0B5FFF"
        assert [b["id"] for b in config["branches"]] == [branch_id]
        assert [x["id"] for x in config["categories"]] == [category_id]

        r = await c.post("/v1/devices/register", headers=emp, json={
            "deviceId": "phone-ravi", "platform": "ios", "appVersion": "1.0.0",
        })
        assert r.status_code in (200, 201), r.text

        r = await c.post("/v1/invoices/duplicate-check", headers=emp, json={"invoiceNumber": "INV-501", "gstin": "36ABCDE1234F1Z5"})
        assert r.json()["isDuplicate"] is False

        payload = {
            "branchId": branch_id, "categoryId": category_id, "deviceId": "phone-ravi", "ocrConfidence": 0.91,
            "ocrData": {"rawText": "Sunrise"},
            "editedData": {"invoiceNumber": "INV-501", "gstin": "36ABCDE1234F1Z5", "vendorName": "Taj Travels",
                           "invoiceDate": "2026-10-01", "netAmount": 5900, "taxableAmount": 5000},
        }

        def files():
            return {
                "original": ("original.jpg", JPEG + b"o", "image/jpeg"),
                "compressed": ("compressed.jpg", JPEG + b"c", "image/jpeg"),
                "thumbnail": ("thumbnail.jpg", JPEG + b"t", "image/jpeg"),
            }

        form = {"idempotencyKey": "ravi-local-1", "payload": json.dumps(payload)}
        r = await c.post("/v1/invoices/upload", headers=emp, data=form, files=files())
        assert r.status_code == 201, r.text
        invoice_id = r.json()["id"]
        # Offline queue retry must not create a second invoice.
        r = await c.post("/v1/invoices/upload", headers=emp, data=form, files=files())
        assert r.status_code == 201 and r.json()["id"] == invoice_id

        # Same bill from a different capture is caught as a duplicate.
        r = await c.post("/v1/invoices/upload", headers=emp, files=files(),
                         data={"idempotencyKey": "ravi-local-2", "payload": json.dumps(payload)})
        assert r.status_code == 409

        # --- Admin reviews the bill ---
        r = await c.get("/v1/admin/dashboard", headers=adm)
        assert r.status_code == 200 and r.json()["pendingCount"] == 1

        r = await c.get("/v1/admin/invoices", headers=adm, params={"status": "pending", "page": 1, "pageSize": 25})
        listing = r.json()
        assert listing["total"] == 1 and listing["items"][0]["id"] == invoice_id
        assert listing["items"][0]["vendorName"] == "Taj Travels"

        r = await c.get("/v1/admin/invoices", headers=adm, params={"q": "taj"})
        assert r.json()["total"] == 1

        detail = (await c.get(f"/v1/admin/invoices/{invoice_id}", headers=adm)).json()
        for key in ("imageUrl", "thumbnailUrl", "originalImageUrl"):
            assert detail[key].startswith("/v1/media/"), detail[key]
            image = await c.get(detail[key])
            assert image.status_code == 200 and image.content.startswith(b"\xff\xd8\xff")

        r = await c.post(f"/v1/admin/invoices/{invoice_id}/reject", headers=adm, json={"remarks": None})
        assert r.status_code == 400  # remarks required for reject/return
        r = await c.post(f"/v1/admin/invoices/{invoice_id}/return", headers=adm, json={"remarks": "Attach the GST page"})
        assert r.status_code == 200 and r.json()["approvalStatus"] == "returned"
        r = await c.post(f"/v1/admin/invoices/{invoice_id}/approve", headers=adm, json={})
        assert r.status_code == 200 and r.json()["approvalStatus"] == "approved"

        # --- Employee sees the decision ---
        mine = (await c.get("/v1/invoices/mine", headers=emp)).json()
        assert mine["items"][0]["approvalStatus"] == "approved"
        assert mine["items"][0]["localIdempotencyKey"] == "ravi-local-1"

        r = await c.post("/v1/admin/notifications/announcements", headers=adm, json={"title": "Diwali", "body": "Submit bills by Friday"})
        assert r.status_code == 201 and r.json()["created"] == 1

        notes = (await c.get("/v1/notifications", headers=emp)).json()["items"]
        types = {n["type"] for n in notes}
        assert {"billApproved", "billReturned", "companyAnnouncement"} <= types
        r = await c.post("/v1/notifications/read", headers=emp, json={"ids": [n["id"] for n in notes]})
        assert r.status_code == 200

        history = (await c.get("/v1/admin/notifications/announcements", headers=adm)).json()["items"]
        assert history[0]["title"] == "Diwali" and history[0]["recipients"] == 1 and history[0]["read"] == 1

        activity = (await c.get("/v1/admin/notifications", headers=adm, params={"excludeType": "companyAnnouncement"})).json()
        assert all(n["type"] != "companyAnnouncement" for n in activity["items"])

        # --- Token lifecycle used by all four apps ---
        r = await c.post("/v1/auth/token/refresh", json={"refreshToken": emp_auth["refreshToken"]})
        assert r.status_code == 200
        emp_refreshed = r.json()
        r = await c.post("/v1/auth/token/refresh", json={"refreshToken": emp_auth["refreshToken"]})
        assert r.status_code == 401  # rotated tokens can't be replayed

        r = await c.post("/v1/auth/token/refresh", json={"refreshToken": owner["refreshToken"]})
        assert r.status_code == 200
        owner_access = r.json()["accessToken"]
        assert (await c.get("/v1/admin/dashboard", headers=bearer(owner_access, company_id))).status_code == 200

        # --- Admin disables the employee: phone access stops immediately ---
        r = await c.delete(f"/v1/admin/employees/{employee_id}", headers=adm)
        assert r.status_code == 204
        r = await c.get("/v1/invoices/mine", headers=bearer(emp_refreshed["accessToken"], company_id))
        assert r.status_code in (401, 403)

        # --- Super admin suspends the company: admins are locked out ---
        r = await c.post(f"/v1/super/companies/{company['id']}/suspend", headers=su)
        assert r.status_code == 200, r.text
        r = await c.get("/v1/admin/dashboard", headers=bearer(owner_access, company_id))
        assert r.status_code in (402, 403)
        r = await c.post(f"/v1/super/companies/{company['id']}/reactivate", headers=su)
        assert r.status_code == 200
        assert (await c.get("/v1/admin/dashboard", headers=bearer(owner_access, company_id))).status_code == 200


@pytest.mark.asyncio
async def test_company_admin_cannot_reach_super_routes(db_engine):
    _, session_factory, _ = db_engine
    await seed_platform(session_factory)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as c:
        root = (await c.post("/v1/admin/auth/login", json={"email": "root@platform.app", "password": "RootPassword!1"})).json()
        su = bearer(root["accessToken"])
        created = (await c.post("/v1/super/companies", headers=su, json={
            "name": "Other Co", "adminEmail": "a@other.co", "adminPassword": "OtherPass!23", "planCode": "growth", "seats": 2,
        })).json()
        await c.post("/v1/super/companies/activate", json={"activationCode": created["activationCode"]})
        owner = (await c.post("/v1/admin/auth/login", json={"email": "a@other.co", "password": "OtherPass!23"})).json()
        adm = bearer(owner["accessToken"], owner["user"]["companyId"])
        assert (await c.get("/v1/super/companies", headers=adm)).status_code == 403
        assert (await c.get("/v1/admin/dashboard", headers=su)).status_code in (400, 403)
        assert (await c.get("/v1/admin/invoices")).status_code == 401
