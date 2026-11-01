"""Push notifications through Firebase Cloud Messaging (HTTP v1 API).

Disabled unless FCM_SERVICE_ACCOUNT_JSON is set. Delivery is best effort and
never blocks or fails the request that produced the notification; the in-app
inbox (the `notifications` collection) stays the source of truth.
"""
import asyncio
import base64
import json
import logging
import time
from functools import lru_cache

import httpx
import jwt
from pymongo.asynchronous.database import AsyncDatabase

from app.core.config import settings
from app.db.mongo import utcnow

logger = logging.getLogger(__name__)

TOKEN_URL = "https://oauth2.googleapis.com/token"
SCOPE = "https://www.googleapis.com/auth/firebase.messaging"
TIMEOUT = httpx.Timeout(10.0, connect=5.0)
MAX_PARALLEL = 10
TOKEN_BATCH = 500

_access_token: tuple[str, float] | None = None
_token_lock = asyncio.Lock()
_background: set[asyncio.Task] = set()


@lru_cache
def _service_account() -> dict | None:
    raw = settings.fcm_service_account_json.strip()
    if not raw:
        return None
    try:
        if not raw.startswith("{"):
            raw = base64.b64decode(raw).decode()
        info = json.loads(raw)
    except (ValueError, UnicodeDecodeError):
        logger.error("FCM_SERVICE_ACCOUNT_JSON is not valid JSON or base64 JSON; push disabled")
        return None
    if not all(info.get(key) for key in ("project_id", "client_email", "private_key")):
        logger.error("FCM service account is missing project_id, client_email or private_key; push disabled")
        return None
    return info


def push_configured() -> bool:
    return _service_account() is not None


async def _get_access_token(client: httpx.AsyncClient, info: dict) -> str:
    global _access_token
    async with _token_lock:
        if _access_token and _access_token[1] - 60 > time.time():
            return _access_token[0]
        now = int(time.time())
        assertion = jwt.encode(
            {"iss": info["client_email"], "scope": SCOPE, "aud": TOKEN_URL, "iat": now, "exp": now + 3600},
            info["private_key"],
            algorithm="RS256",
        )
        response = await client.post(
            TOKEN_URL,
            data={"grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer", "assertion": assertion},
        )
        response.raise_for_status()
        body = response.json()
        _access_token = (body["access_token"], time.time() + int(body.get("expires_in", 3600)))
        return _access_token[0]


def _message(token: str, title: str, body: str, data: dict[str, str]) -> dict:
    return {
        "message": {
            "token": token,
            "notification": {"title": title[:200], "body": body[:1000]},
            "data": data,
            "android": {"priority": "HIGH", "notification": {"channel_id": "gst_expense_alerts"}},
            "apns": {"payload": {"aps": {"sound": "default"}}},
        }
    }


async def send_to_tokens(db: AsyncDatabase, tokens: list[str], title: str, body: str, data: dict[str, str]) -> int:
    """Send one message per token. Returns how many were accepted; prunes dead tokens."""
    info = _service_account()
    if not info or not tokens:
        return 0
    url = f"https://fcm.googleapis.com/v1/projects/{info['project_id']}/messages:send"
    dead: list[str] = []
    sent = 0
    gate = asyncio.Semaphore(MAX_PARALLEL)
    async with httpx.AsyncClient(timeout=TIMEOUT) as client:
        try:
            access = await _get_access_token(client, info)
        except Exception:  # noqa: BLE001
            logger.exception("Could not obtain an FCM access token")
            return 0
        headers = {"Authorization": f"Bearer {access}"}

        async def one(token: str) -> None:
            nonlocal sent
            async with gate:
                try:
                    response = await client.post(url, headers=headers, json=_message(token, title, body, data))
                except httpx.HTTPError as exc:
                    logger.warning("FCM send failed: %s", exc)
                    return
            if response.status_code == 200:
                sent += 1
            elif response.status_code in (400, 404) and ("UNREGISTERED" in response.text or "registration-token" in response.text):
                dead.append(token)
            else:
                logger.warning("FCM rejected a message: %s %s", response.status_code, response.text[:200])

        await asyncio.gather(*(one(token) for token in dict.fromkeys(tokens)))
    if dead:
        await db.devices.update_many({"fcm_token": {"$in": dead}}, {"$set": {"fcm_token": None}})
    return sent


async def push_to_employees(
    db: AsyncDatabase,
    company_id: str,
    employee_ids: list[str] | None,
    title: str,
    body: str,
    data: dict[str, str] | None = None,
) -> int:
    """Push to every registered device of the given employees (None = whole company)."""
    if not push_configured():
        return 0
    query: dict = {"company_id": company_id, "fcm_token": {"$nin": [None, ""]}}
    if employee_ids is not None:
        query["employee_id"] = {"$in": employee_ids}
    sent = 0
    batch: list[str] = []
    async for device in db.devices.find(query, {"fcm_token": 1}):
        batch.append(device["fcm_token"])
        if len(batch) >= TOKEN_BATCH:
            sent += await send_to_tokens(db, batch, title, body, data or {})
            batch = []
    if batch:
        sent += await send_to_tokens(db, batch, title, body, data or {})
    return sent


def push_in_background(
    db: AsyncDatabase,
    company_id: str,
    employee_ids: list[str] | None,
    title: str,
    body: str,
    data: dict[str, str] | None = None,
    notification_ids: list[str] | None = None,
) -> None:
    """Fire-and-forget push; marks the inbox rows as sent once FCM accepts them."""
    if not push_configured():
        return

    async def run() -> None:
        try:
            sent = await push_to_employees(db, company_id, employee_ids, title, body, data)
            if sent and notification_ids:
                await db.notifications.update_many({"_id": {"$in": notification_ids}}, {"$set": {"sent_at": utcnow()}})
        except Exception:  # noqa: BLE001
            logger.exception("Background push failed")

    task = asyncio.get_running_loop().create_task(run())
    _background.add(task)
    task.add_done_callback(_background.discard)


async def drain_pushes(timeout: float = 10.0) -> None:
    if _background:
        await asyncio.wait(set(_background), timeout=timeout)
