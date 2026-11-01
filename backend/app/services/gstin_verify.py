"""Live GSTIN verification through a GST API provider (GSP), with caching.

The GST portal does not issue API keys to businesses; its taxpayer search is reached
through licensed GSPs and API providers. They all return the GSTN "search taxpayer"
record (`lgnm`, `tradeNam`, `sts`, `rgdt`, `pradr`, ...), so one normaliser serves
every provider. Without credentials, or when the provider is down, callers still get
the offline format/checksum result and the reason the live check did not run.
"""
from __future__ import annotations

import json
import logging
from datetime import datetime
from typing import Any

import httpx
from fastapi import HTTPException
from pymongo.asynchronous.database import AsyncDatabase

from app.core.cache import get_json, get_store, set_json
from app.core.config import settings
from app.db.mongo import utcnow
from app.services import gstin as gst

logger = logging.getLogger(__name__)

TIMEOUT = httpx.Timeout(15.0, connect=5.0)
SANDBOX_BASE = "https://api.sandbox.co.in"
APPYFLOW_URL = "https://appyflow.in/api/verifyGST"
SANDBOX_TOKEN_KEY = "gstin-verify:sandbox-token"
SANDBOX_TOKEN_SECONDS = 23 * 3600
NOT_FOUND_CACHE_SECONDS = 3600

ACTIVE, CANCELLED, SUSPENDED, INACTIVE = "active", "cancelled", "suspended", "inactive"
NOT_FOUND, INVALID_FORMAT, UNVERIFIED = "not_found", "invalid_format", "unverified"
BLOCKING_STATUSES = (NOT_FOUND, CANCELLED)

STATE_NAMES = {
    "01": "Jammu and Kashmir", "02": "Himachal Pradesh", "03": "Punjab", "04": "Chandigarh",
    "05": "Uttarakhand", "06": "Haryana", "07": "Delhi", "08": "Rajasthan", "09": "Uttar Pradesh",
    "10": "Bihar", "11": "Sikkim", "12": "Arunachal Pradesh", "13": "Nagaland", "14": "Manipur",
    "15": "Mizoram", "16": "Tripura", "17": "Meghalaya", "18": "Assam", "19": "West Bengal",
    "20": "Jharkhand", "21": "Odisha", "22": "Chhattisgarh", "23": "Madhya Pradesh", "24": "Gujarat",
    "26": "Dadra and Nagar Haveli and Daman and Diu", "27": "Maharashtra", "29": "Karnataka", "30": "Goa",
    "31": "Lakshadweep", "32": "Kerala", "33": "Tamil Nadu", "34": "Puducherry",
    "35": "Andaman and Nicobar Islands", "36": "Telangana", "37": "Andhra Pradesh", "38": "Ladakh",
    "97": "Other Territory", "99": "Centre Jurisdiction",
}


class GstinLookupError(Exception):
    """The provider could not give an answer (down, busy, or misconfigured)."""


def _message(status: str, cancelled_on: str | None = None) -> str:
    return {
        ACTIVE: "Active GST registration.",
        CANCELLED: "GST registration is cancelled"
        + (f" (from {cancelled_on})" if cancelled_on else "")
        + ". ITC cannot be claimed on bills issued after cancellation.",
        SUSPENDED: "GST registration is suspended. ITC on this supplier's bills is at risk.",
        INACTIVE: "GST registration is not active.",
        NOT_FOUND: "No GST registration exists for this GSTIN.",
        INVALID_FORMAT: "Not a valid GSTIN: the format or check digit is wrong.",
        UNVERIFIED: "The format is valid. Live verification with the GST portal is not set up.",
    }[status]


def _base(gstin: str) -> dict[str, Any]:
    code = gst.state_code(gstin)
    return {
        "gstin": gstin,
        "formatValid": gst.is_valid(gstin),
        "status": UNVERIFIED,
        "statusText": None,
        "legalName": None,
        "tradeName": None,
        "registrationDate": None,
        "cancellationDate": None,
        "taxpayerType": None,
        "constitution": None,
        "address": None,
        "stateCode": code,
        "stateName": STATE_NAMES.get(code or ""),
        "natureOfBusiness": [],
        "einvoiceEnabled": None,
        "lastUpdated": None,
        "liveCheck": False,
        "source": None,
        "checkedAt": utcnow().isoformat(),
        "message": _message(UNVERIFIED),
    }


def _status(raw: str | None) -> str:
    text = (raw or "").strip().lower()
    if text.startswith("active") or text == "provisional":
        return ACTIVE
    if "cancel" in text:
        return CANCELLED
    if "suspend" in text:
        return SUSPENDED
    return INACTIVE


def _iso_date(value: Any) -> str | None:
    text = str(value or "").strip()
    for fmt in ("%d/%m/%Y", "%d-%m-%Y", "%Y-%m-%d"):
        try:
            return datetime.strptime(text, fmt).date().isoformat()
        except ValueError:
            continue
    return None


def _address(pradr: Any) -> str | None:
    addr = pradr.get("addr") if isinstance(pradr, dict) else None
    if not isinstance(addr, dict):
        return (pradr.get("adr") or None) if isinstance(pradr, dict) else None
    parts = [addr.get(key) for key in ("bno", "flno", "bnm", "st", "loc", "locality", "city", "dst", "stcd")]
    text = ", ".join(str(p).strip() for p in parts if p and str(p).strip())
    pin = str(addr.get("pncd") or "").strip()
    return (f"{text} - {pin}" if pin else text) or None


def _find_taxpayer(payload: Any, depth: int = 0) -> dict | None:
    """The GSTN taxpayer record wherever the provider nests it."""
    if depth > 5:
        return None
    if isinstance(payload, dict):
        if "lgnm" in payload or ("sts" in payload and "gstin" in payload):
            return payload
        for value in payload.values():
            found = _find_taxpayer(value, depth + 1)
            if found:
                return found
    elif isinstance(payload, list):
        for value in payload[:5]:
            found = _find_taxpayer(value, depth + 1)
            if found:
                return found
    return None


def normalise(taxpayer: dict, gstin: str, source: str) -> dict[str, Any]:
    result = _base(gstin)
    status = _status(taxpayer.get("sts"))
    cancelled_on = _iso_date(taxpayer.get("cxdt"))
    nature = taxpayer.get("nba")
    result.update({
        "status": status,
        "statusText": taxpayer.get("sts"),
        "legalName": (taxpayer.get("lgnm") or "").strip() or None,
        "tradeName": (taxpayer.get("tradeNam") or "").strip() or None,
        "registrationDate": _iso_date(taxpayer.get("rgdt")),
        "cancellationDate": cancelled_on,
        "taxpayerType": taxpayer.get("dty") or None,
        "constitution": taxpayer.get("ctb") or None,
        "address": _address(taxpayer.get("pradr")),
        "natureOfBusiness": nature if isinstance(nature, list) else [],
        "einvoiceEnabled": {"yes": True, "no": False}.get(str(taxpayer.get("einvoiceStatus") or "").lower()),
        "lastUpdated": _iso_date(taxpayer.get("lstupdt")),
        "liveCheck": True,
        "source": source,
        "message": _message(status, cancelled_on),
    })
    stcd = ((taxpayer.get("pradr") or {}).get("addr") or {}).get("stcd") if isinstance(taxpayer.get("pradr"), dict) else None
    if stcd and not result["stateName"]:
        result["stateName"] = stcd
    return result


def _not_found(gstin: str, source: str) -> dict[str, Any]:
    result = _base(gstin)
    result.update({"status": NOT_FOUND, "liveCheck": True, "source": source, "message": _message(NOT_FOUND)})
    return result


_NOT_FOUND_HINTS = ("no record", "not found", "invalid gstin", "fo8000", "does not exist", "no data found", "not a valid gstin")
_CREDENTIAL_HINTS = ("key", "token", "unauthor", "credential", "balance", "quota", "subscription", "wallet", "forbidden")


def _interpret(response: httpx.Response, gstin: str, source: str) -> dict[str, Any]:
    if response.status_code in (401, 403):
        raise GstinLookupError("The GST verification provider rejected the API credentials.")
    if response.status_code == 429:
        raise GstinLookupError("The GST verification provider is rate limiting requests; try again shortly.")
    if response.status_code >= 500:
        raise GstinLookupError("The GST portal is not responding right now; try again later.")
    try:
        payload = response.json()
    except ValueError as exc:
        raise GstinLookupError("The GST verification provider sent an unreadable response.") from exc
    taxpayer = _find_taxpayer(payload)
    if taxpayer:
        return normalise(taxpayer, gstin, source)
    text = json.dumps(payload, default=str).lower()
    if any(hint in text for hint in _NOT_FOUND_HINTS):
        return _not_found(gstin, source)
    if any(hint in text for hint in _CREDENTIAL_HINTS):
        raise GstinLookupError("The GST verification provider refused the request (check the API key and account balance).")
    logger.warning("Unexpected GSTIN verification response from %s: %s", source, text[:300])
    raise GstinLookupError("The GST verification provider sent an unexpected response.")


async def _sandbox_token(client: httpx.AsyncClient, base: str) -> str:
    cached = await get_json(SANDBOX_TOKEN_KEY)
    if cached:
        return cached
    response = await client.post(
        f"{base}/authenticate",
        headers={
            "x-api-key": settings.gstin_verify_api_key,
            "x-api-secret": settings.gstin_verify_api_secret,
            "x-api-version": "1.0.0",
        },
    )
    if response.status_code >= 400:
        raise GstinLookupError("Could not sign in to Sandbox; check GSTIN_VERIFY_API_KEY and GSTIN_VERIFY_API_SECRET.")
    body = response.json()
    token = (body.get("data") or {}).get("access_token") or body.get("access_token")
    if not token:
        raise GstinLookupError("Sandbox did not return an access token.")
    await set_json(SANDBOX_TOKEN_KEY, token, SANDBOX_TOKEN_SECONDS)
    return token


async def _lookup_sandbox(client: httpx.AsyncClient, gstin: str) -> dict[str, Any]:
    base = (settings.gstin_verify_base_url or SANDBOX_BASE).rstrip("/")
    for attempt in range(2):
        token = await _sandbox_token(client, base)
        response = await client.post(
            f"{base}/gst/compliance/public/gstin/search",
            json={"gstin": gstin},
            headers={
                "x-api-key": settings.gstin_verify_api_key,
                "authorization": token,
                "x-api-version": "1.0",
                "x-accept-cache": "true",
            },
        )
        if response.status_code in (401, 403) and attempt == 0:
            await get_store().delete(SANDBOX_TOKEN_KEY)  # token expired early; sign in again once
            continue
        return _interpret(response, gstin, "sandbox")
    raise GstinLookupError("Sandbox rejected the access token.")


async def _lookup_appyflow(client: httpx.AsyncClient, gstin: str) -> dict[str, Any]:
    response = await client.get(
        settings.gstin_verify_base_url or APPYFLOW_URL,
        params={"gstNo": gstin, "key_secret": settings.gstin_verify_api_key},
    )
    return _interpret(response, gstin, "appyflow")


async def _lookup_custom(client: httpx.AsyncClient, gstin: str) -> dict[str, Any]:
    headers = {settings.gstin_verify_key_header: settings.gstin_verify_api_key} if settings.gstin_verify_api_key else {}
    response = await client.get(settings.gstin_verify_base_url.replace("{gstin}", gstin), headers=headers)
    return _interpret(response, gstin, "custom")


_PROVIDERS = {"sandbox": _lookup_sandbox, "appyflow": _lookup_appyflow, "custom": _lookup_custom}


def _transport() -> httpx.AsyncBaseTransport | None:
    """Overridden in tests."""
    return None


async def _lookup(gstin: str) -> dict[str, Any]:
    provider = _PROVIDERS[settings.gstin_verify_provider.strip().lower()]
    try:
        async with httpx.AsyncClient(timeout=TIMEOUT, transport=_transport()) as client:
            return await provider(client, gstin)
    except httpx.HTTPError as exc:
        raise GstinLookupError("Could not reach the GST verification provider; try again later.") from exc


def _cache_key(gstin: str) -> str:
    return f"gstin-verify:{gstin}"


async def verify_gstin(value: str | None, *, refresh: bool = False) -> dict[str, Any]:
    """Format check always; live portal check when a provider is configured (cached)."""
    gstin = gst.compact(value)
    if not gst.is_valid(gstin):
        result = _base(gstin)
        result.update({"status": INVALID_FORMAT, "message": _message(INVALID_FORMAT)})
        return result
    if not settings.gstin_verify_configured:
        return _base(gstin)
    if not refresh:
        cached = await get_json(_cache_key(gstin))
        if cached:
            return {**cached, "cached": True}
    try:
        result = await _lookup(gstin)
    except GstinLookupError as exc:
        logger.warning("GSTIN %s could not be verified: %s", gstin, exc)
        result = _base(gstin)
        result.update({"message": str(exc), "error": True})
        return result
    ttl = NOT_FOUND_CACHE_SECONDS if result["status"] == NOT_FOUND else settings.gstin_verify_cache_hours * 3600
    await set_json(_cache_key(gstin), result, ttl)
    return result


def check_doc(result: dict[str, Any]) -> dict[str, Any]:
    """The subset stored on invoices and companies."""
    return {
        "status": result["status"],
        "legal_name": result.get("legalName"),
        "trade_name": result.get("tradeName"),
        "cancellation_date": result.get("cancellationDate"),
        "message": result.get("message"),
        "source": result.get("source"),
        "checked_at": utcnow(),
    }


def check_json(doc: dict | None) -> dict | None:
    if not doc:
        return None
    return {
        "status": doc.get("status"),
        "legalName": doc.get("legal_name"),
        "tradeName": doc.get("trade_name"),
        "cancellationDate": doc.get("cancellation_date"),
        "message": doc.get("message"),
        "checkedAt": doc.get("checked_at"),
    }


async def check_invoice_gstin(db: AsyncDatabase, invoice_id: str, *, refresh: bool = False) -> dict | None:
    """Record the supplier GSTIN's portal status on an invoice. Never raises."""
    try:
        invoice = await db.invoices.find_one({"_id": invoice_id}, {"gstin": 1})
        if not invoice:
            return None
        if not invoice.get("gstin"):
            await db.invoices.update_one({"_id": invoice_id}, {"$unset": {"gstin_check": ""}})
            return None
        result = await verify_gstin(invoice["gstin"], refresh=refresh)
        if not result["liveCheck"] and result["status"] != INVALID_FORMAT:
            return None  # nothing new learnt; keep any earlier answer
        doc = check_doc(result)
        await db.invoices.update_one({"_id": invoice_id, "gstin": invoice["gstin"]}, {"$set": {"gstin_check": doc}})
        return doc
    except Exception:  # noqa: BLE001
        logger.exception("Supplier GSTIN check failed for invoice %s", invoice_id)
        return None


async def company_gstin_check(gstin: str | None) -> dict | None:
    """Portal check for a firm's own GSTIN; 400 when the portal says it is unusable."""
    if not gstin:
        return None
    result = await verify_gstin(gstin)
    if reason := blocking_reason(result):
        raise HTTPException(400, f"GSTIN {gstin}: {reason}")
    return check_doc(result) if result["liveCheck"] else None


def blocking_reason(result: dict[str, Any]) -> str | None:
    """Why a firm cannot register with this GSTIN, when the portal answered definitively."""
    if not settings.gstin_verify_enforce_signup or not result.get("liveCheck"):
        return None
    if result["status"] in BLOCKING_STATUSES:
        return result["message"]
    return None
