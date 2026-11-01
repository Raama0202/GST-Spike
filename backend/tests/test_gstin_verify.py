"""Live GSTIN verification through Sandbox, AppyFlow or a custom GSP (HTTP mocked)."""
import json

import httpx
import pytest
from httpx import ASGITransport, AsyncClient

import factories as f
from app.core.config import settings
from app.main import app
from app.models import Role
from app.services import gstin as gst
from app.services import gstin_verify

JPEG = b"\xff\xd8\xff\xe0" + b"\x00" * 64


def valid(prefix14: str) -> str:
    return prefix14 + gst.check_char(prefix14)


ACTIVE_GSTIN = valid("29AFSPB9500E1Z")
CANCELLED_GSTIN = valid("27AAACC1234C1Z")
UNKNOWN_GSTIN = valid("36AAAAA0000A1Z")


def taxpayer(gstin: str, status: str = "Active", cxdt: str = "") -> dict:
    return {
        "gstin": gstin, "lgnm": "Vicky Private Limited", "tradeNam": "Vicky Traders", "sts": status,
        "rgdt": "18/10/2019", "cxdt": cxdt, "dty": "Regular", "ctb": "Private Limited Company",
        "lstupdt": "18/10/2019", "nba": ["Supplier of Services"], "einvoiceStatus": "No",
        "pradr": {"addr": {"bno": "26", "st": "Whitefield Main Road", "loc": "Bangalore", "dst": "Bengaluru Urban",
                           "stcd": "Karnataka", "pncd": "560048"}},
    }


def client():
    return AsyncClient(transport=ASGITransport(app=app, raise_app_exceptions=False), base_url="http://test")


@pytest.fixture
def provider(monkeypatch):
    """Configure a provider and capture the HTTP calls made to it."""
    calls: list[httpx.Request] = []

    def use(name: str, handler, **extra):
        monkeypatch.setattr(settings, "gstin_verify_provider", name)
        monkeypatch.setattr(settings, "gstin_verify_api_key", "key_live_x")
        monkeypatch.setattr(settings, "gstin_verify_api_secret", "secret_live_x")
        for key, value in extra.items():
            monkeypatch.setattr(settings, key, value)

        def record(request: httpx.Request) -> httpx.Response:
            calls.append(request)
            return handler(request)

        monkeypatch.setattr(gstin_verify, "_transport", lambda: httpx.MockTransport(record))
        return calls

    return use


def sandbox_handler(request: httpx.Request) -> httpx.Response:
    if request.url.path == "/authenticate":
        assert request.headers["x-api-secret"] == "secret_live_x"
        return httpx.Response(200, json={"code": 200, "data": {"access_token": "jwt-token"}})
    assert request.headers["authorization"] == "jwt-token"
    gstin = json.loads(request.content)["gstin"]
    if gstin == ACTIVE_GSTIN:
        return httpx.Response(200, json={"code": 200, "data": {"data": taxpayer(gstin), "status_cd": "1"}})
    if gstin == CANCELLED_GSTIN:
        return httpx.Response(200, json={"code": 200, "data": {"data": taxpayer(gstin, "Cancelled", "01/04/2024"), "status_cd": "1"}})
    return httpx.Response(200, json={"code": 200, "data": {"error": {"error_cd": "FO8000", "message": "No records found"}, "status_cd": "0"}})


@pytest.mark.asyncio
async def test_sandbox_verification_normalises_and_caches(mongo, provider):
    calls = provider("sandbox", sandbox_handler)
    result = await gstin_verify.verify_gstin(ACTIVE_GSTIN.lower())
    assert result["status"] == "active" and result["liveCheck"] and result["source"] == "sandbox"
    assert result["legalName"] == "Vicky Private Limited" and result["tradeName"] == "Vicky Traders"
    assert result["registrationDate"] == "2019-10-18" and result["stateName"] == "Karnataka"
    assert result["address"].endswith("Karnataka - 560048") and result["einvoiceEnabled"] is False
    assert len(calls) == 2  # sign in + search

    again = await gstin_verify.verify_gstin(ACTIVE_GSTIN)
    assert again["cached"] is True and len(calls) == 2
    await gstin_verify.verify_gstin(ACTIVE_GSTIN, refresh=True)
    assert len(calls) == 3  # token reused, search repeated

    cancelled = await gstin_verify.verify_gstin(CANCELLED_GSTIN)
    assert cancelled["status"] == "cancelled" and cancelled["cancellationDate"] == "2024-04-01"
    assert "cancelled" in cancelled["message"]
    unknown = await gstin_verify.verify_gstin(UNKNOWN_GSTIN)
    assert unknown["status"] == "not_found"


@pytest.mark.asyncio
async def test_appyflow_custom_and_failures(mongo, provider):
    def appyflow(request: httpx.Request) -> httpx.Response:
        assert request.url.params["key_secret"] == "key_live_x"
        if request.url.params["gstNo"] == ACTIVE_GSTIN:
            return httpx.Response(200, json={"taxpayerInfo": taxpayer(ACTIVE_GSTIN), "filing": []})
        return httpx.Response(200, json={"error": True, "message": "Invalid GSTIN or no records found"})

    provider("appyflow", appyflow)
    assert (await gstin_verify.verify_gstin(ACTIVE_GSTIN))["status"] == "active"
    assert (await gstin_verify.verify_gstin(UNKNOWN_GSTIN))["status"] == "not_found"

    def custom(request: httpx.Request) -> httpx.Response:
        assert request.headers["x-gsp-key"] == "key_live_x"
        return httpx.Response(200, json={"result": {"taxpayer": taxpayer(CANCELLED_GSTIN, "Suspended")}})

    provider("custom", custom, gstin_verify_base_url="https://gsp.example/search?gstin={gstin}", gstin_verify_key_header="x-gsp-key")
    assert (await gstin_verify.verify_gstin(CANCELLED_GSTIN))["status"] == "suspended"

    provider("appyflow", lambda request: httpx.Response(200, json={"error": True, "message": "Insufficient wallet balance"}))
    down = await gstin_verify.verify_gstin(valid("07AAAAA1111A1Z"))
    assert down["status"] == "unverified" and down["error"] and "balance" in down["message"]

    provider("appyflow", lambda request: httpx.Response(503))
    down = await gstin_verify.verify_gstin(valid("07BBBBB1111A1Z"))
    assert down["status"] == "unverified" and down["liveCheck"] is False


@pytest.mark.asyncio
async def test_offline_results_without_provider(mongo):
    bad = await gstin_verify.verify_gstin("29ABCDE1234F1Z0")
    assert bad["status"] == "invalid_format" and not bad["formatValid"]
    offline = await gstin_verify.verify_gstin(ACTIVE_GSTIN)
    assert offline["status"] == "unverified" and offline["formatValid"] and offline["stateName"] == "Karnataka"


async def seed(db):
    await f.plan(db, "starter", "Starter", 999, 50)
    company = await f.company(db, "Acme Builders", activation_code="ACME")
    await f.user(db, company["_id"], Role.company_admin, email="admin@acme.in", password="AdminPass!123")
    await f.employee(db, company["_id"], name="Ravi", code="E1", mobile="9876500001")
    await f.subscription(db, company["_id"], "starter", 10)
    return company


@pytest.mark.asyncio
async def test_endpoints_registration_and_bills(mongo, provider):
    provider("sandbox", sandbox_handler)
    await seed(mongo)
    async with client() as c:
        r = await c.post("/v1/public/gstin/check", json={"gstin": ACTIVE_GSTIN})
        assert r.status_code == 200 and r.json()["legalName"] == "Vicky Private Limited"
        assert "address" not in r.json()

        registration = {
            "companyName": "Ghost Traders", "gstin": CANCELLED_GSTIN, "adminName": "Ghost Owner", "adminEmail": "a@ghost.in",
            "adminPassword": "GhostPass!234", "mobile": "9848022338",
        }
        r = await c.post("/v1/admin/auth/register", json=registration)
        assert r.status_code == 400 and "cancelled" in r.json()["message"]

        r = await c.post("/v1/auth/otp/request", json={"mobile": "9876500001"})
        r = await c.post("/v1/auth/otp/verify", json={"mobile": "9876500001", "otp": "123456"})
        body = r.json()
        emp = {"Authorization": f"Bearer {body['accessToken']}", "X-Company-Id": body["employee"]["companyId"]}
        r = await c.get(f"/v1/gstin/{ACTIVE_GSTIN}", headers=emp)
        assert r.status_code == 200 and r.json()["status"] == "active"
        config = (await c.get("/v1/company/config", headers=emp)).json()
        assert config["gstinLiveCheck"] is True

        payload = {"editedData": {"invoiceNumber": "INV-9", "gstin": CANCELLED_GSTIN, "vendorName": "Ghost", "netAmount": 100}}
        files = {kind: (f"{kind}.jpg", JPEG + kind.encode(), "image/jpeg") for kind in ("original", "compressed", "thumbnail")}
        r = await c.post("/v1/invoices/upload", headers=emp, data={"idempotencyKey": "g1", "payload": json.dumps(payload)}, files=files)
        assert r.status_code == 201, r.text
        invoice_id = r.json()["id"]

        login = await c.post("/v1/admin/auth/login", json={"email": "admin@acme.in", "password": "AdminPass!123"})
        adm = {"Authorization": f"Bearer {login.json()['accessToken']}"}
        detail = (await c.get(f"/v1/admin/invoices/{invoice_id}", headers=adm)).json()
        assert detail["gstinCheck"]["status"] == "cancelled" and detail["gstinCheck"]["legalName"] == "Vicky Private Limited"
        flagged = (await c.get("/v1/admin/invoices", headers=adm, params={"gstinStatus": "problem"})).json()
        assert flagged["total"] == 1

        r = await c.patch(f"/v1/admin/invoices/{invoice_id}", headers=adm, json={"editedData": {"gstin": ACTIVE_GSTIN}})
        assert r.status_code == 200
        detail = (await c.get(f"/v1/admin/invoices/{invoice_id}", headers=adm)).json()
        assert detail["gstinCheck"]["status"] == "active"
        r = await c.post(f"/v1/admin/invoices/{invoice_id}/verify-gstin", headers=adm)
        assert r.status_code == 200 and r.json()["gstinCheck"]["status"] == "active"

        r = await c.patch("/v1/admin/company/settings", headers=adm, json={"gstin": UNKNOWN_GSTIN})
        assert r.status_code == 400 and "No GST registration" in r.json()["message"]
        r = await c.patch("/v1/admin/company/settings", headers=adm, json={"gstin": ACTIVE_GSTIN})
        assert r.status_code == 200 and r.json()["gstin_check"]["status"] == "active"
