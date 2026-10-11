"""Production-hardening behaviour: headers, limits, storage, payments, config."""
import hashlib
import hmac
import json
from datetime import datetime, timedelta, timezone

import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select

from app.core.config import Settings, settings
from app.core.security import hash_password
from app.main import app
from app.models import (
    Branch,
    Company,
    CompanyStatus,
    Employee,
    PaymentOrder,
    PaymentStatus,
    Role,
    Subscription,
    SubscriptionPlan,
    SubscriptionStatus,
    User,
)

JPEG = b"\xff\xd8\xff\xe0" + b"\x00" * 64


async def seed(session_factory, *, expired: bool = False, employees: int = 1):
    async with session_factory() as db:
        db.add(SubscriptionPlan(code="starter", name="Starter", monthly_price_inr=999, max_employees=50))
        db.add(SubscriptionPlan(code="growth", name="Growth", monthly_price_inr=2999, max_employees=200))
        company = Company(name="Prod Co", activation_code="PROD", status=CompanyStatus.active)
        db.add(company)
        await db.flush()
        branch = Branch(company_id=company.id, name="HQ", code="HQ")
        admin = User(company_id=company.id, role=Role.company_admin, email="admin@prod.co", password_hash=hash_password("Password!123"))
        superuser = User(role=Role.super_admin, email="root@prod.co", password_hash=hash_password("RootPassword!1"))
        db.add_all([branch, admin, superuser])
        await db.flush()
        for i in range(employees):
            user = User(company_id=company.id, role=Role.employee)
            db.add(user)
            await db.flush()
            db.add(Employee(company_id=company.id, user_id=user.id, branch_id=branch.id, name=f"Emp {i:03d}", employee_code=f"E{i:03d}", mobile=f"98765{i:05d}"))
        now = datetime.now(timezone.utc)
        ends = now - timedelta(days=1) if expired else now + timedelta(days=30)
        db.add(Subscription(company_id=company.id, plan_code="starter", seats=50, starts_at=now - timedelta(days=60), ends_at=ends, status=SubscriptionStatus.active))
        await db.commit()
        return company.id


def client():
    return AsyncClient(transport=ASGITransport(app=app, raise_app_exceptions=False), base_url="http://test")


async def admin_headers(c, email="admin@prod.co", password="Password!123"):
    response = await c.post("/v1/admin/auth/login", json={"email": email, "password": password})
    assert response.status_code == 200, response.text
    return {"Authorization": f"Bearer {response.json()['accessToken']}"}


@pytest.mark.asyncio
async def test_security_headers_and_request_id(db_engine):
    async with client() as c:
        response = await c.get("/health", headers={"X-Request-Id": "abc123"})
    assert response.status_code == 200
    assert response.headers["x-request-id"] == "abc123"
    assert response.headers["x-content-type-options"] == "nosniff"
    assert response.headers["x-frame-options"] == "DENY"


@pytest.mark.asyncio
async def test_ready_checks_database(db_engine):
    async with client() as c:
        response = await c.get("/ready")
    assert response.status_code in (200, 503)
    assert "database" in response.json()["checks"]


@pytest.mark.asyncio
async def test_unhandled_error_is_json_with_cors(db_engine, monkeypatch):
    _, session_factory, _ = db_engine
    await seed(session_factory)
    import app.api.routes.admin as admin_routes

    monkeypatch.setattr(admin_routes, "datetime", None)  # forces an AttributeError inside the handler
    async with client() as c:
        headers = await admin_headers(c)
        headers["Origin"] = settings.cors_origin_list[0]
        response = await c.get("/v1/admin/dashboard", headers=headers)
    assert response.status_code == 500
    body = response.json()
    assert body["message"].startswith("Something went wrong")
    assert body["requestId"]
    assert response.headers.get("access-control-allow-origin") == settings.cors_origin_list[0]


@pytest.mark.asyncio
async def test_oversized_body_rejected(db_engine, monkeypatch):
    monkeypatch.setattr(settings, "max_request_mb", 1)
    async with client() as c:
        response = await c.post(
            "/v1/admin/auth/login",
            content=b"x" * (1024 * 1024 + 10),
            headers={"Content-Type": "application/json"},
        )
    assert response.status_code == 413


@pytest.mark.asyncio
async def test_login_rate_limit_and_lockout(db_engine, monkeypatch):
    _, session_factory, _ = db_engine
    await seed(session_factory)
    monkeypatch.setattr(settings, "login_rate_per_minute", 100)
    monkeypatch.setattr(settings, "login_lockout_failures", 3)
    async with client() as c:
        for _ in range(3):
            bad = await c.post("/v1/admin/auth/login", json={"email": "admin@prod.co", "password": "wrong"})
            assert bad.status_code == 401
        locked = await c.post("/v1/admin/auth/login", json={"email": "admin@prod.co", "password": "Password!123"})
    assert locked.status_code == 429
    assert "retry-after" in locked.headers


@pytest.mark.asyncio
async def test_change_password_revokes_old_refresh(db_engine):
    _, session_factory, _ = db_engine
    await seed(session_factory)
    async with client() as c:
        login = await c.post("/v1/admin/auth/login", json={"email": "admin@prod.co", "password": "Password!123"})
        tokens = login.json()
        headers = {"Authorization": f"Bearer {tokens['accessToken']}"}
        wrong = await c.post("/v1/admin/auth/password", headers=headers, json={"currentPassword": "nope", "newPassword": "BrandNewPass!9"})
        assert wrong.status_code == 400
        ok = await c.post("/v1/admin/auth/password", headers=headers, json={"currentPassword": "Password!123", "newPassword": "BrandNewPass!9"})
        assert ok.status_code == 200
        stale = await c.post("/v1/auth/token/refresh", json={"refreshToken": tokens["refreshToken"]})
        assert stale.status_code == 401
        relogin = await c.post("/v1/admin/auth/login", json={"email": "admin@prod.co", "password": "BrandNewPass!9"})
        assert relogin.status_code == 200


@pytest.mark.asyncio
async def test_pagination_returns_totals(db_engine):
    _, session_factory, _ = db_engine
    await seed(session_factory, employees=25)
    async with client() as c:
        headers = await admin_headers(c)
        page = await c.get("/v1/admin/employees", headers=headers, params={"page": 2, "pageSize": 10})
        searched = await c.get("/v1/admin/employees", headers=headers, params={"q": "Emp 02"})
    body = page.json()
    assert body["total"] == 25 and body["page"] == 2 and body["pageSize"] == 10
    assert len(body["items"]) == 10
    assert searched.json()["total"] == 5  # Emp 020..024


@pytest.mark.asyncio
async def test_disabled_employee_loses_access_immediately(db_engine):
    _, session_factory, _ = db_engine
    await seed(session_factory)
    async with client() as c:
        await c.post("/v1/auth/otp/request", json={"mobile": "9876500000"})
        auth = (await c.post("/v1/auth/otp/verify", json={"mobile": "9876500000", "otp": "123456"})).json()
        emp_headers = {"Authorization": f"Bearer {auth['accessToken']}"}
        assert (await c.get("/v1/employees/me", headers=emp_headers)).status_code == 200
        headers = await admin_headers(c)
        await c.delete(f"/v1/admin/employees/{auth['employee']['id']}", headers=headers)
        assert (await c.get("/v1/employees/me", headers=emp_headers)).status_code == 401


@pytest.mark.asyncio
async def test_upload_rejects_non_images_and_serves_signed_media(db_engine):
    _, session_factory, _ = db_engine
    await seed(session_factory)
    async with client() as c:
        await c.post("/v1/auth/otp/request", json={"mobile": "9876500000"})
        auth = (await c.post("/v1/auth/otp/verify", json={"mobile": "9876500000", "otp": "123456"})).json()
        headers = {"Authorization": f"Bearer {auth['accessToken']}"}
        data = {"idempotencyKey": "k1", "payload": '{"editedData":{"invoiceNumber":"A1","netAmount":100}}'}
        fake = {name: (f"{name}.jpg", b"<html>not an image</html>", "image/jpeg") for name in ("original", "compressed", "thumbnail")}
        rejected = await c.post("/v1/invoices/upload", headers=headers, data=data, files=fake)
        assert rejected.status_code == 400

        real = {name: (f"{name}.jpg", JPEG + name.encode(), "image/jpeg") for name in ("original", "compressed", "thumbnail")}
        created = await c.post("/v1/invoices/upload", headers=headers, data=data, files=real)
        assert created.status_code == 201
        mine = (await c.get("/v1/invoices/mine", headers=headers)).json()
        url = mine["items"][0]["imageUrl"]
        assert url.startswith("/v1/media/") and "sig=" in url
        image = await c.get(url)
        assert image.status_code == 200 and image.content.startswith(b"\xff\xd8\xff")
        tampered = await c.get(url.replace("sig=", "sig=0"))
        assert tampered.status_code == 403
        assert (await c.get("/uploads/anything.jpg")).status_code == 404


@pytest.mark.asyncio
async def test_announcement_bulk_insert_and_grouped_history(db_engine):
    _, session_factory, _ = db_engine
    await seed(session_factory, employees=30)
    async with client() as c:
        headers = await admin_headers(c)
        sent = await c.post("/v1/admin/notifications/announcements", headers=headers, json={"title": "Deadline", "body": "Upload by 28th"})
        history = await c.get("/v1/admin/notifications/announcements", headers=headers)
    assert sent.json()["created"] == 30
    items = history.json()["items"]
    assert len(items) == 1 and items[0]["recipients"] == 30 and items[0]["read"] == 0


@pytest.mark.asyncio
async def test_billing_returns_503_until_configured(db_engine, monkeypatch):
    _, session_factory, _ = db_engine
    await seed(session_factory)
    monkeypatch.setattr(settings, "razorpay_key_id", "")
    async with client() as c:
        headers = await admin_headers(c)
        overview = await c.get("/v1/admin/billing", headers=headers)
        order = await c.post("/v1/admin/billing/orders", headers=headers, json={"planCode": "starter", "seats": 5})
        hook = await c.post("/v1/payments/razorpay/webhook", content=b"{}")
    assert overview.status_code == 200 and overview.json()["paymentsEnabled"] is False
    assert order.status_code == 503
    assert hook.status_code == 503


def _configure_razorpay(monkeypatch):
    monkeypatch.setattr(settings, "razorpay_key_id", "rzp_test_key")
    monkeypatch.setattr(settings, "razorpay_key_secret", "secret_abc")
    monkeypatch.setattr(settings, "razorpay_webhook_secret", "whsec_abc")
    import app.api.routes.billing as billing_routes

    counter = {"n": 0}

    async def fake_order(amount_paise, receipt, notes):
        counter["n"] += 1
        return {"id": f"order_test_{counter['n']}", "amount": amount_paise}

    monkeypatch.setattr(billing_routes, "create_provider_order", fake_order)


@pytest.mark.asyncio
async def test_expired_company_can_pay_and_is_reactivated(db_engine, monkeypatch):
    _, session_factory, _ = db_engine
    company_id = await seed(session_factory, expired=True)
    _configure_razorpay(monkeypatch)
    async with client() as c:
        login = await c.post("/v1/admin/auth/login", json={"email": "admin@prod.co", "password": "Password!123"})
        assert login.status_code == 200 and login.json()["billingRequired"] is True
        headers = {"Authorization": f"Bearer {login.json()['accessToken']}"}
        assert (await c.get("/v1/admin/dashboard", headers=headers)).status_code == 403

        order = await c.post("/v1/admin/billing/orders", headers=headers, json={"planCode": "growth", "seats": 80, "months": 3})
        assert order.status_code == 201, order.text
        body = order.json()
        assert body["amountPaise"] == round(2999 * 3 * 1.18 * 100)

        bad = await c.post("/v1/admin/billing/verify", headers=headers, json={"razorpayOrderId": body["orderId"], "razorpayPaymentId": "pay_1", "razorpaySignature": "bad"})
        assert bad.status_code == 400
        sig = hmac.new(b"secret_abc", f"{body['orderId']}|pay_1".encode(), hashlib.sha256).hexdigest()
        ok = await c.post("/v1/admin/billing/verify", headers=headers, json={"razorpayOrderId": body["orderId"], "razorpayPaymentId": "pay_1", "razorpaySignature": sig})
        assert ok.status_code == 200 and ok.json()["status"] == "paid"
        assert (await c.get("/v1/admin/dashboard", headers=headers)).status_code == 200

        # Webhook for the same order must not extend a second time.
        event = json.dumps({"event": "payment.captured", "payload": {"payment": {"entity": {"id": "pay_1", "order_id": body["orderId"]}}}}).encode()
        wsig = hmac.new(b"whsec_abc", event, hashlib.sha256).hexdigest()
        for _ in range(2):
            hook = await c.post("/v1/payments/razorpay/webhook", content=event, headers={"X-Razorpay-Signature": wsig, "X-Razorpay-Event-Id": "evt_1"})
            assert hook.status_code == 200
        forged = await c.post("/v1/payments/razorpay/webhook", content=event, headers={"X-Razorpay-Signature": "0" * 64})
        assert forged.status_code == 400

        root = await admin_headers(c, "root@prod.co", "RootPassword!1")
        payments = await c.get("/v1/super/payments", headers=root)
        assert payments.json()["total"] == 1 and payments.json()["items"][0]["companyName"] == "Prod Co"

    async with session_factory() as db:
        subscription = await db.scalar(select(Subscription).where(Subscription.company_id == company_id))
        assert subscription.plan_code == "growth" and subscription.seats == 80
        days = (subscription.ends_at.replace(tzinfo=timezone.utc) - datetime.now(timezone.utc)).days
        assert 88 <= days <= 90
        order = await db.scalar(select(PaymentOrder))
        assert order.status == PaymentStatus.paid


@pytest.mark.asyncio
async def test_super_companies_paginated(db_engine):
    _, session_factory, _ = db_engine
    await seed(session_factory)
    async with client() as c:
        root = await admin_headers(c, "root@prod.co", "RootPassword!1")
        response = await c.get("/v1/super/companies", headers=root, params={"pageSize": 5})
    body = response.json()
    assert body["total"] == 1 and body["items"][0]["name"] == "Prod Co"


def test_image_sniffing():
    from app.services.storage import sniff_image_type

    assert sniff_image_type(b"\xff\xd8\xff\xe0" + b"\0" * 12) == "image/jpeg"
    assert sniff_image_type(b"\x89PNG\r\n\x1a\n" + b"\0" * 8) == "image/png"
    assert sniff_image_type(b"RIFF\0\0\0\0WEBPVP8 ") == "image/webp"
    assert sniff_image_type(b"\0\0\0\x18ftypheic\0\0\0\0") == "image/heic"
    assert sniff_image_type(b"\0\0\0\x18ftypisom\0\0\0\0") is None
    assert sniff_image_type(b"%PDF-1.7\n") is None


def test_production_config_validation():
    unsafe = Settings(env="production", jwt_secret="short", cors_origins="*", storage_backend="local", redis_url="", _env_file=None)
    problems = unsafe.production_problems()
    assert any("JWT_SECRET" in p for p in problems)
    assert any("CORS_ORIGINS" in p for p in problems)
    assert any("STORAGE_BACKEND" in p for p in problems)
    assert any("REDIS_URL" in p for p in problems)
    assert unsafe.fixed_otp is None
    assert not unsafe.sms_configured

    safe = Settings(
        env="production",
        jwt_secret="x" * 48,
        cors_origins="https://admin.example.com",
        storage_backend="r2",
        r2_account_id="acc",
        r2_access_key_id="k",
        r2_secret_access_key="s",
        r2_bucket="b",
        redis_url="redis://localhost:6379/0",
        _env_file=None,
    )
    assert safe.production_problems() == []
    assert safe.r2_endpoint == "https://acc.r2.cloudflarestorage.com"


@pytest.mark.asyncio
async def test_otp_returns_503_without_sms_provider(db_engine, monkeypatch):
    _, session_factory, _ = db_engine
    await seed(session_factory)
    monkeypatch.setattr(settings, "sms_provider", "msg91")
    async with client() as c:
        response = await c.post("/v1/auth/otp/request", json={"mobile": "9876500000"})
    assert response.status_code == 503


def test_single_instance_and_demo_otp_config():
    base = dict(env="production", jwt_secret="x" * 48, cors_origins="https://admin.example.com", storage_backend="local", redis_url="", _env_file=None)
    single = Settings(allow_single_instance=True, **base)
    assert single.production_problems() == []
    assert any("redeploy" in w for w in single.production_warnings())

    bad_code = Settings(allow_single_instance=True, demo_otp_mobiles="9999999999", demo_otp_code="12", **base)
    assert any("DEMO_OTP_CODE" in p for p in bad_code.production_problems())
    assert bad_code.demo_otp_for("9999999999") is None

    demo = Settings(allow_single_instance=True, demo_otp_mobiles="9999999999", demo_otp_code="246810", **base)
    assert demo.demo_otp_for("9999999999") == "246810"
    assert demo.demo_otp_for("9876500000") is None


@pytest.mark.asyncio
async def test_demo_otp_mobile_logs_in_without_sms(db_engine, monkeypatch):
    _, session_factory, _ = db_engine
    await seed(session_factory, employees=2)
    monkeypatch.setattr(settings, "env", "production")
    monkeypatch.setattr(settings, "sms_provider", "msg91")
    monkeypatch.setattr(settings, "demo_otp_mobiles", "9876500000")
    monkeypatch.setattr(settings, "demo_otp_code", "246810")
    async with client() as c:
        assert (await c.post("/v1/auth/otp/request", json={"mobile": "9876500000"})).status_code == 200
        assert (await c.post("/v1/auth/otp/verify", json={"mobile": "9876500000", "otp": "123456"})).status_code == 401
        await c.post("/v1/auth/otp/request", json={"mobile": "9876500000"})
        ok = await c.post("/v1/auth/otp/verify", json={"mobile": "9876500000", "otp": "246810"})
        assert ok.status_code == 200, ok.text
        # Mobiles not on the demo list still need a real SMS provider.
        assert (await c.post("/v1/auth/otp/request", json={"mobile": "9876500001"})).status_code == 503


@pytest.mark.asyncio
async def test_r2_storage_roundtrip(monkeypatch):
    moto = pytest.importorskip("moto")
    import boto3

    from app.services import storage as storage_module

    monkeypatch.setattr(settings, "r2_endpoint_url", "")
    monkeypatch.setattr(settings, "r2_account_id", "")
    monkeypatch.setattr(settings, "r2_access_key_id", "test")
    monkeypatch.setattr(settings, "r2_secret_access_key", "test")
    monkeypatch.setattr(settings, "r2_bucket", "invoices")
    with moto.mock_aws():
        client_ = boto3.client("s3", region_name="us-east-1", aws_access_key_id="test", aws_secret_access_key="test")
        client_.create_bucket(Bucket="invoices")
        storage_module._r2_client.cache_clear()
        monkeypatch.setattr(storage_module, "_r2_client", lambda: client_)
        r2 = storage_module.R2Storage()
        await r2.put("c1/test.jpg", JPEG, "image/jpeg")
        assert client_.get_object(Bucket="invoices", Key="c1/test.jpg")["Body"].read() == JPEG
        url = r2.url("c1/test.jpg")
        assert "Signature" in url and "c1/test.jpg" in url
        assert await r2.ping()


@pytest.mark.asyncio
async def test_rotated_refresh_token_cannot_be_replayed_same_second(db_engine):
    _, session_factory, _ = db_engine
    await seed(session_factory)
    async with client() as c:
        login = (await c.post("/v1/admin/auth/login", json={"email": "admin@prod.co", "password": "Password!123"})).json()
        first = await c.post("/v1/auth/token/refresh", json={"refreshToken": login["refreshToken"]})
        assert first.status_code == 200
        assert first.json()["refreshToken"] != login["refreshToken"]
        replay = await c.post("/v1/auth/token/refresh", json={"refreshToken": login["refreshToken"]})
        assert replay.status_code == 401
        again = await c.post("/v1/auth/token/refresh", json={"refreshToken": first.json()["refreshToken"]})
        assert again.status_code == 200


@pytest.mark.asyncio
async def test_employee_validation_conflicts_and_seat_limit(db_engine):
    _, session_factory, _ = db_engine
    await seed(session_factory, employees=50)
    async with client() as c:
        h = await admin_headers(c)
        listed = (await c.get("/v1/admin/employees", headers=h)).json()["items"]
        first, second = listed[0], listed[1]

        # Editing into another employee's mobile is a clean 409, not a 500.
        r = await c.patch(f"/v1/admin/employees/{first['id']}", headers=h, json={"mobile": second["mobile"]})
        assert r.status_code == 409
        # Explicit nulls on required columns are ignored instead of crashing.
        r = await c.patch(f"/v1/admin/employees/{first['id']}", headers=h, json={"name": None})
        assert r.status_code in (200, 400)
        assert (await c.get("/v1/admin/employees", headers=h)).status_code == 200
        # Invalid mobiles are rejected up front; separators are normalised.
        r = await c.post("/v1/admin/employees", headers=h, json={"name": "X", "mobile": "12ab", "employeeCode": "NEW1"})
        assert r.status_code == 400

        # Seat limit (50) also applies when re-activating a disabled employee.
        assert (await c.delete(f"/v1/admin/employees/{first['id']}", headers=h)).status_code == 204
        r = await c.post("/v1/admin/employees", headers=h, json={"name": "New", "mobile": "91234 56789", "employeeCode": "NEW2"})
        assert r.status_code == 201, r.text
        assert r.json()["mobile"] == "9123456789"
        r = await c.patch(f"/v1/admin/employees/{first['id']}", headers=h, json={"isActive": True})
        assert r.status_code == 409


@pytest.mark.asyncio
async def test_settings_and_catalog_bad_input_are_not_500(db_engine):
    _, session_factory, _ = db_engine
    await seed(session_factory)
    async with client() as c:
        h = await admin_headers(c)
        r = await c.patch("/v1/admin/company/settings", headers=h, json={"name": None, "requiresGps": True})
        assert r.status_code == 200
        assert r.json()["name"] == "Prod Co"
        assert (await c.patch("/v1/admin/company/settings", headers=h, json={"minOcrConfidenceWarn": 5})).status_code == 400
        assert (await c.post("/v1/admin/company/categories", headers=h, json={"name": "Travel"})).status_code == 201
        assert (await c.post("/v1/admin/company/categories", headers=h, json={"name": "Travel"})).status_code == 409
        r = await c.get("/v1/admin/itc/matches/export", headers=h, params={"period": "2026-09", "status": "all"})
        assert r.status_code == 200
        assert r.json()["filename"].endswith("_all.csv")
