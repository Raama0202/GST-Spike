import json
from decimal import Decimal

import httpx
import pytest
from bson import Decimal128
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa

from app.core.config import settings
from app.db.mongo import new_id, utcnow
from app.services import push
from app.services.backup import dump, restore
from app.services.notifications import notify_employee
from tests import factories


@pytest.mark.asyncio
async def test_backup_round_trip_keeps_types(mongo, tmp_path):
    company = await factories.company(mongo, "Backup Co", gstin="36AABCU9603R1ZM")
    await factories.employee(mongo, company["_id"])
    await mongo.invoices.insert_one({"_id": new_id(), "company_id": company["_id"], "total_amount": Decimal128("1180.50"), "uploaded_at": utcnow()})
    await mongo.otp_challenges.insert_one({"_id": new_id(), "target": "x", "expires_at": utcnow()})

    archive = tmp_path / "b.tar.gz"
    manifest = await dump(mongo, archive)
    assert manifest["collections"]["companies"] == 1
    assert "otp_challenges" not in manifest["collections"]

    await mongo.invoices.delete_many({})
    await mongo.companies.delete_many({})
    counts = await restore(mongo, archive)
    assert counts["invoices"] == 1 and counts["companies"] == 1
    invoice = await mongo.invoices.find_one({})
    assert Decimal(str(invoice["total_amount"])) == Decimal("1180.50")
    assert invoice["uploaded_at"].year == utcnow().year

    again = await restore(mongo, archive)
    assert again["companies"] == 0
    assert await mongo.companies.count_documents({}) == 1


def _service_account() -> str:
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    pem = key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()).decode()
    return json.dumps({"project_id": "demo", "client_email": "push@demo.iam.gserviceaccount.com", "private_key": pem})


@pytest.mark.asyncio
async def test_push_sends_and_prunes_dead_tokens(mongo, monkeypatch):
    requests: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        if request.url.host == "oauth2.googleapis.com":
            return httpx.Response(200, json={"access_token": "tok", "expires_in": 3600})
        token = json.loads(request.content)["message"]["token"]
        if token == "dead":
            return httpx.Response(404, json={"error": {"status": "NOT_FOUND", "details": [{"errorCode": "UNREGISTERED"}]}})
        return httpx.Response(200, json={"name": "projects/demo/messages/1"})

    real_client = httpx.AsyncClient
    monkeypatch.setattr(push.httpx, "AsyncClient", lambda **kw: real_client(transport=httpx.MockTransport(handler), **kw))
    monkeypatch.setattr(settings, "fcm_service_account_json", _service_account())
    monkeypatch.setattr(push, "_access_token", None)
    push._service_account.cache_clear()

    try:
        company = await factories.company(mongo)
        employee = await factories.employee(mongo, company["_id"])
        for device_id, token in (("a", "live"), ("b", "dead")):
            await mongo.devices.insert_one({"_id": new_id(), "company_id": company["_id"], "employee_id": employee["_id"],
                                            "device_id": device_id, "fcm_token": token})

        item = await notify_employee(mongo, company["_id"], employee["_id"], "invoiceApproved", "Approved", "Bill approved", "inv-1")
        await push.drain_pushes()

        sends = [r for r in requests if r.url.host == "fcm.googleapis.com"]
        assert len(sends) == 2
        assert sends[0].headers["authorization"] == "Bearer tok"
        assert json.loads(sends[0].content)["message"]["data"]["invoiceId"] == "inv-1"
        assert (await mongo.devices.find_one({"device_id": "b"}))["fcm_token"] is None
        assert (await mongo.notifications.find_one({"_id": item["_id"]}))["sent_at"] is not None
    finally:
        push._service_account.cache_clear()


@pytest.mark.asyncio
async def test_push_disabled_without_credentials(mongo):
    push._service_account.cache_clear()
    assert not push.push_configured()
    company = await factories.company(mongo)
    employee = await factories.employee(mongo, company["_id"])
    item = await notify_employee(mongo, company["_id"], employee["_id"], "x", "t", "b")
    assert (await mongo.notifications.find_one({"_id": item["_id"]}))["sent_at"] is None
