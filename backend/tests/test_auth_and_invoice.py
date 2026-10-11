from datetime import datetime, timedelta, timezone

import pytest
from httpx import ASGITransport, AsyncClient

from app.core.security import hash_password

JPEG = b"\xff\xd8\xff\xe0" + b"\x00" * 64
from app.main import app
from app.models import (
    Branch,
    Company,
    CompanyStatus,
    Employee,
    Role,
    Subscription,
    SubscriptionPlan,
    SubscriptionStatus,
    User,
)


async def seed_company(session_factory):
    async with session_factory() as db:
        plan = SubscriptionPlan(
            code="starter", name="Starter", monthly_price_inr=999, max_employees=10
        )
        db.add(plan)
        company = Company(
            name="Test Company", activation_code="TEST", status=CompanyStatus.active
        )
        db.add(company)
        await db.flush()
        branch = Branch(company_id=company.id, name="HQ", code="HQ")
        employee_user = User(company_id=company.id, role=Role.employee)
        admin = User(
            company_id=company.id,
            role=Role.company_admin,
            email="boss@test.com",
            password_hash=hash_password("Password!123"),
        )
        db.add_all([branch, employee_user, admin])
        await db.flush()
        db.add(
            Employee(
                company_id=company.id,
                user_id=employee_user.id,
                branch_id=branch.id,
                name="Tester",
                employee_code="E1",
                mobile="9999999999",
            )
        )
        now = datetime.now(timezone.utc)
        db.add(
            Subscription(
                company_id=company.id,
                plan_code="starter",
                seats=10,
                starts_at=now,
                ends_at=now + timedelta(days=30),
                status=SubscriptionStatus.active,
            )
        )
        await db.commit()
        return company.id, branch.id


@pytest.mark.asyncio
async def test_otp_auth_and_idempotent_invoice_upload(db_engine):
    _, session_factory, _ = db_engine
    await seed_company(session_factory)

    async with AsyncClient(
        transport=ASGITransport(app=app), base_url="http://test"
    ) as client:
        response = await client.post(
            "/v1/auth/otp/request", json={"mobile": "9999999999"}
        )
        assert response.status_code == 200
        response = await client.post(
            "/v1/auth/otp/verify", json={"mobile": "9999999999", "otp": "123456"}
        )
        assert response.status_code == 200
        auth = response.json()
        headers = {
            "Authorization": f"Bearer {auth['accessToken']}",
            "X-Company-Id": str(auth["employee"]["companyId"]),
            "X-Device-Id": "phone-1",
        }
        files = {
            "original": ("original.jpg", JPEG + b"original", "image/jpeg"),
            "compressed": ("compressed.jpg", JPEG + b"compressed", "image/jpeg"),
            "thumbnail": ("thumbnail.jpg", JPEG + b"thumbnail", "image/jpeg"),
        }
        data = {
            "idempotencyKey": "local-123",
            "payload": '{"editedData":{"invoiceNumber":"INV-1","gstin":"29ABCDE1234F1Z5","netAmount":11700}}',
        }
        first = await client.post(
            "/v1/invoices/upload", headers=headers, data=data, files=files
        )
        assert first.status_code == 201
        files = {name: (value[0], value[1], value[2]) for name, value in files.items()}
        second = await client.post(
            "/v1/invoices/upload", headers=headers, data=data, files=files
        )
        assert second.status_code == 201
        assert second.json()["id"] == first.json()["id"]
        mine = await client.get("/v1/invoices/mine", headers=headers)
        assert len(mine.json()["items"]) == 1


@pytest.mark.asyncio
async def test_admin_login(db_engine):
    _, session_factory, _ = db_engine
    await seed_company(session_factory)

    async with AsyncClient(
        transport=ASGITransport(app=app), base_url="http://test"
    ) as client:
        response = await client.post(
            "/v1/admin/auth/login",
            json={"email": "boss@test.com", "password": "Password!123"},
        )
        assert response.status_code == 200
        assert response.json()["user"]["role"] == "company_admin"
