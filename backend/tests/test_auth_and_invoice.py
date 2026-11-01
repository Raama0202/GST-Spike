import pytest
from httpx import ASGITransport, AsyncClient

import factories as f
from app.main import app
from app.models import Role

JPEG = b"\xff\xd8\xff\xe0" + b"\x00" * 64


async def seed_company(db):
    await f.plan(db)
    company = await f.company(db, activation_code="TEST")
    branch = await f.branch(db, company["_id"])
    await f.user(db, company["_id"], Role.company_admin, email="boss@test.com", password="Password!123")
    await f.employee(db, company["_id"], branch_id=branch["_id"])
    await f.subscription(db, company["_id"])
    return company["_id"], branch["_id"]


@pytest.mark.asyncio
async def test_otp_auth_and_idempotent_invoice_upload(mongo):
    await seed_company(mongo)

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        response = await client.post("/v1/auth/otp/request", json={"mobile": "9999999999"})
        assert response.status_code == 200, response.text
        assert response.json()["channel"] == "sms"
        response = await client.post("/v1/auth/otp/verify", json={"mobile": "9999999999", "otp": "123456"})
        assert response.status_code == 200, response.text
        auth = response.json()
        assert auth["employee"]["branchName"] == "HQ"
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
        first = await client.post("/v1/invoices/upload", headers=headers, data=data, files=files)
        assert first.status_code == 201, first.text
        second = await client.post("/v1/invoices/upload", headers=headers, data=data, files=files)
        assert second.status_code == 201
        assert second.json()["id"] == first.json()["id"]
        mine = await client.get("/v1/invoices/mine", headers=headers)
        assert len(mine.json()["items"]) == 1
        assert mine.json()["items"][0]["netAmount"] == 11700

    stored = await mongo.invoices.find_one({})
    assert str(stored["net_amount"]) == "11700.00"


@pytest.mark.asyncio
async def test_admin_login(mongo):
    await seed_company(mongo)

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        response = await client.post("/v1/admin/auth/login", json={"email": "boss@test.com", "password": "Password!123"})
        assert response.status_code == 200
        assert response.json()["user"]["role"] == "company_admin"
