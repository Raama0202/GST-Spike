from datetime import datetime, timedelta, timezone

import pytest
from httpx import ASGITransport, AsyncClient

from app.core.security import hash_password
from app.main import app
from app.models import (
    Branch,
    Company,
    CompanyStatus,
    Employee,
    ExpenseCategory,
    Role,
    Subscription,
    SubscriptionPlan,
    SubscriptionStatus,
    User,
)


async def seed_demo(session_factory):
    async with session_factory() as db:
        plan = SubscriptionPlan(
            code="growth",
            name="Growth",
            monthly_price_inr=4999,
            max_employees=50,
        )
        db.add(plan)
        company = Company(
            name="Acme Construction",
            industry="Construction",
            activation_code="ACME-ACTIVATE",
            status=CompanyStatus.active,
            primary_color_hex="0B5FFF",
        )
        db.add(company)
        await db.flush()
        branch = Branch(company_id=company.id, name="Site A", code="A")
        category = ExpenseCategory(
            company_id=company.id, name="Cement", sort_order=1
        )
        employee_user = User(company_id=company.id, role=Role.employee)
        admin = User(
            company_id=company.id,
            role=Role.company_admin,
            email="acme@demo.com",
            password_hash=hash_password("DemoAdmin!123"),
        )
        super_admin = User(
            company_id=None,
            role=Role.super_admin,
            email="admin@gstexpenses.app",
            password_hash=hash_password("ChangeMeNow!123"),
        )
        db.add_all([branch, category, employee_user, admin, super_admin])
        await db.flush()
        db.add(
            Employee(
                company_id=company.id,
                user_id=employee_user.id,
                branch_id=branch.id,
                name="Ravi Kumar",
                employee_code="EMP001",
                mobile="9999999999",
            )
        )
        now = datetime.now(timezone.utc)
        db.add(
            Subscription(
                company_id=company.id,
                plan_code="growth",
                seats=50,
                starts_at=now,
                ends_at=now + timedelta(days=365),
                status=SubscriptionStatus.active,
            )
        )
        await db.commit()
        return str(branch.id)


@pytest.mark.asyncio
async def test_employee_upload_admin_approve_notification_sync(db_engine):
    """Full SaaS path: OTP → config → upload → admin approve → employee notified."""
    _, session_factory, _ = db_engine
    branch_id = await seed_demo(session_factory)

    async with AsyncClient(
        transport=ASGITransport(app=app), base_url="http://test"
    ) as client:
        assert (
            await client.post("/v1/auth/otp/request", json={"mobile": "9999999999"})
        ).status_code == 200
        verify = await client.post(
            "/v1/auth/otp/verify",
            json={"mobile": "9999999999", "otp": "123456"},
        )
        assert verify.status_code == 200
        auth = verify.json()
        emp_headers = {
            "Authorization": f"Bearer {auth['accessToken']}",
            "X-Company-Id": str(auth["employee"]["companyId"]),
            "X-Device-Id": "device-e2e",
        }

        config = await client.get("/v1/company/config", headers=emp_headers)
        assert config.status_code == 200
        assert config.json()["companyName"] == "Acme Construction"
        assert any(c["name"] == "Cement" for c in config.json()["categories"])

        dup = await client.post(
            "/v1/invoices/duplicate-check",
            headers=emp_headers,
            json={
                "invoiceNumber": "G-25-26/11469",
                "gstin": "37AARFS2045J1ZS",
                "invoiceDate": "2025-11-13",
                "netAmount": 62495.0,
            },
        )
        assert dup.status_code == 200
        assert dup.json()["isDuplicate"] is False

        payload = (
            '{"branchId":"%s","deviceId":"device-e2e","ocrConfidence":0.91,'
            '"ocrData":{"vendorName":"SRI VIJAYALAKSHMI ENTERPRISES",'
            '"gstin":"37AARFS2045J1ZS","invoiceNumber":"G-25-26/11469",'
            '"invoiceDate":"2025-11-13","taxableValue":52961.86,'
            '"cgst":4766.58,"sgst":4766.58,"netAmount":62495.0},'
            '"editedData":{"vendorName":"SRI VIJAYALAKSHMI ENTERPRISES",'
            '"gstin":"37AARFS2045J1ZS","invoiceNumber":"G-25-26/11469",'
            '"invoiceDate":"2025-11-13","taxableValue":52961.86,'
            '"cgst":4766.58,"sgst":4766.58,"netAmount":62495.0,'
            '"expenseCategoryName":"Cement"},'
            '"duplicateOverride":false}'
            % branch_id
        )
        files = {
            "original": ("original.jpg", b"\xff\xd8\xfforiginal", "image/jpeg"),
            "compressed": ("compressed.jpg", b"\xff\xd8\xffcomp", "image/jpeg"),
            "thumbnail": ("thumb.jpg", b"\xff\xd8\xffthumb", "image/jpeg"),
        }
        upload = await client.post(
            "/v1/invoices/upload",
            headers=emp_headers,
            data={"idempotencyKey": "vijay-bill-1", "payload": payload},
            files=files,
        )
        assert upload.status_code == 201, upload.text
        invoice_id = upload.json()["id"]

        admin_login = await client.post(
            "/v1/admin/auth/login",
            json={"email": "acme@demo.com", "password": "DemoAdmin!123"},
        )
        assert admin_login.status_code == 200
        admin_headers = {
            "Authorization": f"Bearer {admin_login.json()['accessToken']}"
        }

        dashboard = await client.get("/v1/admin/dashboard", headers=admin_headers)
        assert dashboard.status_code == 200
        assert dashboard.json()["pendingCount"] >= 1

        approve = await client.post(
            f"/v1/admin/invoices/{invoice_id}/approve",
            headers=admin_headers,
            json={"remarks": "Verified against original bill"},
        )
        assert approve.status_code == 200, approve.text

        notes = await client.get("/v1/notifications", headers=emp_headers)
        assert notes.status_code == 200
        assert any(n["type"] == "billApproved" for n in notes.json()["items"])

        mine = await client.get("/v1/invoices/mine", headers=emp_headers)
        assert mine.json()["items"][0]["approvalStatus"] == "approved"

        super_login = await client.post(
            "/v1/admin/auth/login",
            json={
                "email": "admin@gstexpenses.app",
                "password": "ChangeMeNow!123",
            },
        )
        assert super_login.status_code == 200
        super_headers = {
            "Authorization": f"Bearer {super_login.json()['accessToken']}"
        }
        companies = await client.get("/v1/super/companies", headers=super_headers)
        assert companies.status_code == 200
        assert any(
            c["name"] == "Acme Construction" for c in companies.json()["items"]
        )
