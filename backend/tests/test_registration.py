"""Self-service firm registration through to the first employee scan."""
import pytest
from httpx import ASGITransport, AsyncClient

import factories as f
from app.core.config import settings
from app.main import app

JPEG = b"\xff\xd8\xff\xe0" + b"\x00" * 64
COMPANY_GSTIN = "36AAACS5678L1ZS"
SUPPLIER_GSTIN = "37AABCV1234K1ZC"

REGISTRATION = {
    "companyName": "Sunrise Traders",
    "legalName": "Sunrise Traders Private Limited",
    "gstin": COMPANY_GSTIN,
    "industry": "Retail",
    "adminName": "Lakshmi Rao",
    "adminEmail": "Owner@Sunrise.in",
    "adminPassword": "OwnerPass!234",
    "mobile": "98480 22338",
}


def client():
    return AsyncClient(transport=ASGITransport(app=app, raise_app_exceptions=False), base_url="http://test")


def bearer(session):
    return {"Authorization": f"Bearer {session['accessToken']}", "X-Company-Id": session["user"]["companyId"]}


@pytest.mark.asyncio
async def test_register_verify_login_and_first_scan(mongo, monkeypatch):
    await f.plan(mongo, "starter", "Starter", 999, 10)
    async with client() as c:
        options = (await c.get("/v1/admin/auth/register/options")).json()
        assert options["enabled"] and options["available"] and options["verificationRequired"]

        r = await c.post("/v1/admin/auth/register", json=REGISTRATION)
        assert r.status_code == 201, r.text
        assert r.json()["verificationRequired"] is True
        assert r.json()["destination"].endswith("@sunrise.in")

        # No firm exists until the emailed code is entered.
        assert await mongo.companies.count_documents({}) == 0
        r = await c.post("/v1/admin/auth/register/verify", json={"email": "owner@sunrise.in", "code": "000000", "password": REGISTRATION["adminPassword"]})
        assert r.status_code == 400

        r = await c.post("/v1/admin/auth/register/resend", json={"email": "owner@sunrise.in"})
        assert r.status_code == 200, r.text
        r = await c.post("/v1/admin/auth/register/verify", json={"email": "owner@sunrise.in", "code": "123456", "password": REGISTRATION["adminPassword"]})
        assert r.status_code == 201, r.text
        session = r.json()
        assert session["user"]["role"] == "company_admin" and session["user"]["email"] == "owner@sunrise.in"
        assert await mongo.signup_requests.count_documents({}) == 0

        # The same email or GSTIN cannot register twice.
        r = await c.post("/v1/admin/auth/register", json=REGISTRATION)
        assert r.status_code == 409
        r = await c.post("/v1/admin/auth/register", json={**REGISTRATION, "adminEmail": "other@sunrise.in"})
        assert r.status_code == 409 and "GSTIN" in r.json()["message"]

        # Password sign-in works and lands on an active trial.
        r = await c.post("/v1/admin/auth/login", json={"email": "owner@sunrise.in", "password": "OwnerPass!234"})
        assert r.status_code == 200, r.text
        assert r.json()["billingRequired"] is False
        admin = bearer(r.json())

        company = (await c.get("/v1/admin/company/settings", headers=admin)).json()
        assert company["gstin"] == COMPANY_GSTIN and company["legal_name"] == "Sunrise Traders Private Limited"
        branches = (await c.get("/v1/admin/company/branches", headers=admin)).json()["items"]
        categories = (await c.get("/v1/admin/company/categories", headers=admin)).json()["items"]
        assert [b["code"] for b in branches] == ["HO"] and len(categories) >= 5

        r = await c.patch("/v1/admin/company/settings", headers=admin, json={"nameAliases": ["Sunrise Traders HYD"]})
        assert r.status_code == 200 and r.json()["name_aliases"] == ["Sunrise Traders HYD"]

        # First employee, with an email so the free email OTP channel is used.
        r = await c.post("/v1/admin/employees", headers=admin, json={
            "name": "Ravi Kumar", "mobile": "9876543210", "email": "ravi@sunrise.in", "employeeCode": "SUN-001",
            "branchId": branches[0]["id"],
        })
        assert r.status_code == 201, r.text

        r = await c.post("/v1/auth/otp/request", json={"mobile": "9876543210"})
        assert r.status_code == 200, r.text
        assert r.json()["channel"] == "email" and r.json()["destination"].endswith("@sunrise.in")
        r = await c.post("/v1/auth/otp/verify", json={"mobile": "9876543210", "otp": "123456"})
        assert r.status_code == 200, r.text
        assert r.json()["employee"]["companyName"] == "Sunrise Traders"
        employee = {"Authorization": f"Bearer {r.json()['accessToken']}"}

        config = (await c.get("/v1/company/config", headers=employee)).json()
        assert config["gstins"] == [COMPANY_GSTIN] and config["legalName"] == "Sunrise Traders Private Limited"

        # A bill naming both firms: the AI picked the buyer; the server switches to the supplier.
        captured = {}

        async def fake_gemini(image_bytes, mime_type, identity):
            captured["hint"] = identity.prompt_hint()
            return {
                "vendorName": "Sunrise Traders Pvt Ltd",
                "gstin": COMPANY_GSTIN,
                "netAmount": 1180,
                "parties": [
                    {"name": "Sunrise Traders Pvt Ltd", "gstin": COMPANY_GSTIN, "role": "buyer"},
                    {"name": "Vijaya Hardware", "gstin": SUPPLIER_GSTIN, "role": "seller"},
                ],
                "confidence": 0.9,
            }, "gemini-test"

        monkeypatch.setattr(settings, "gemini_api_key", "test-key")
        monkeypatch.setattr("app.services.ai_extract._call_gemini", fake_gemini)
        r = await c.post("/v1/invoices/extract", headers=employee, files={"image": ("bill.jpg", JPEG, "image/jpeg")})
        assert r.status_code == 200, r.text
        assert r.json()["vendorName"] == "Vijaya Hardware" and r.json()["gstin"] == SUPPLIER_GSTIN
        assert "Sunrise Traders HYD" in captured["hint"] and COMPANY_GSTIN in captured["hint"]


@pytest.mark.asyncio
async def test_register_without_email_verification_signs_in_immediately(mongo, monkeypatch):
    await f.plan(mongo, "starter", "Starter", 999, 10)
    monkeypatch.setattr(settings, "signup_verify_email", False)
    async with client() as c:
        r = await c.post("/v1/admin/auth/register", json={**REGISTRATION, "gstin": None})
    assert r.status_code == 201, r.text
    body = r.json()
    assert body["verificationRequired"] is False and body["accessToken"] and body["user"]["companyId"]


@pytest.mark.asyncio
async def test_registration_explains_missing_email_provider(mongo, monkeypatch):
    await f.plan(mongo, "starter", "Starter", 999, 10)
    monkeypatch.setattr(settings, "email_provider", "brevo")
    async with client() as c:
        options = (await c.get("/v1/admin/auth/register/options")).json()
        assert options["enabled"] and not options["available"]
        r = await c.post("/v1/admin/auth/register", json=REGISTRATION)
    assert r.status_code == 503
    assert "verification emails" in r.json()["message"]


@pytest.mark.asyncio
async def test_registration_validates_input(mongo):
    await f.plan(mongo, "starter", "Starter", 999, 10)
    async with client() as c:
        r = await c.post("/v1/admin/auth/register", json={**REGISTRATION, "gstin": "36AAACS5678L1ZX"})
        assert r.status_code == 400 and "GSTIN" in r.json()["message"]
        r = await c.post("/v1/admin/auth/register", json={**REGISTRATION, "adminPassword": "short"})
        assert r.status_code == 400


@pytest.mark.asyncio
async def test_password_reset_by_email(mongo):
    await f.plan(mongo, "starter", "Starter", 999, 10)
    async with client() as c:
        await c.post("/v1/admin/auth/register", json=REGISTRATION)
        await c.post("/v1/admin/auth/register/verify", json={"email": "owner@sunrise.in", "code": "123456", "password": REGISTRATION["adminPassword"]})
        r = await c.post("/v1/admin/auth/password/forgot", json={"email": "owner@sunrise.in"})
        assert r.status_code == 200, r.text
        r = await c.post("/v1/admin/auth/password/reset", json={"email": "owner@sunrise.in", "code": "123456", "newPassword": "BrandNewPass!9"})
        assert r.status_code == 200, r.text
        r = await c.post("/v1/admin/auth/login", json={"email": "owner@sunrise.in", "password": "BrandNewPass!9"})
        assert r.status_code == 200, r.text
