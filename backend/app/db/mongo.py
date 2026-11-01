"""MongoDB (Atlas) client, collections, indexes and small document helpers.

Documents use string UUIDs for `_id` so every id the API returns is the same
shape clients already store. Money is Decimal128 (exact), timestamps are UTC
datetimes, and calendar dates (invoice dates) are "YYYY-MM-DD" strings so
range queries and month prefixes work without timezone surprises.
"""
from __future__ import annotations

import logging
import re
from collections.abc import Callable
from datetime import date, datetime, timezone
from decimal import Decimal
from typing import Any
from urllib.parse import unquote
from uuid import UUID, uuid4

from bson.codec_options import CodecOptions, TypeCodec, TypeRegistry
from bson.decimal128 import Decimal128
from pymongo import ASCENDING, DESCENDING, AsyncMongoClient, IndexModel
from pymongo.asynchronous.collection import AsyncCollection
from pymongo.asynchronous.database import AsyncDatabase

from app.core.config import settings

logger = logging.getLogger(__name__)

DEFAULT_DB_NAME = "gst_expenses"


class DecimalCodec(TypeCodec):
    python_type = Decimal  # type: ignore[assignment]
    bson_type = Decimal128  # type: ignore[assignment]

    def transform_python(self, value: Decimal) -> Decimal128:
        return Decimal128(value)

    def transform_bson(self, value: Decimal128) -> Decimal:
        return value.to_decimal()


def _fallback_encoder(value: Any) -> Any:
    if isinstance(value, date) and not isinstance(value, datetime):
        return value.isoformat()
    if isinstance(value, UUID):
        return str(value)
    raise TypeError(f"Cannot store {type(value).__name__} in MongoDB")


CODEC_OPTIONS: CodecOptions = CodecOptions(
    tz_aware=True,
    tzinfo=timezone.utc,
    type_registry=TypeRegistry([DecimalCodec()], fallback_encoder=_fallback_encoder),
)

_client: AsyncMongoClient | None = None


def get_client() -> AsyncMongoClient:
    global _client
    if _client is None:
        kwargs: dict[str, Any] = {
            "appname": "gst-expense-api",
            "maxPoolSize": settings.mongodb_max_pool_size,
            "serverSelectionTimeoutMS": settings.mongodb_timeout_ms,
            "connectTimeoutMS": settings.mongodb_timeout_ms,
            "retryWrites": True,
        }
        if settings.mongodb_uri.startswith("mongodb+srv://") or "tls=true" in settings.mongodb_uri.lower():
            import certifi

            kwargs["tlsCAFile"] = certifi.where()
        _client = AsyncMongoClient(settings.mongodb_uri, **kwargs)
    return _client


async def close_client() -> None:
    global _client
    if _client is not None:
        await _client.close()
        _client = None


def database_name() -> str:
    if settings.mongodb_db:
        return settings.mongodb_db
    _, _, rest = settings.mongodb_uri.partition("://")
    _, slash, path = rest.partition("/")
    name = unquote(path.split("?", 1)[0]) if slash else ""
    return name or DEFAULT_DB_NAME


def get_database() -> AsyncDatabase:
    return get_client().get_database(database_name(), codec_options=CODEC_OPTIONS)


async def get_db() -> AsyncDatabase:
    """FastAPI dependency."""
    return get_database()


# ── Indexes ──────────────────────────────────────────────────────────────────

_STRING = {"$type": "string"}
AUDIT_RETENTION_SECONDS = 400 * 86400

INDEXES: dict[str, list[IndexModel]] = {
    "companies": [
        IndexModel([("activation_code", ASCENDING)], unique=True),
        IndexModel([("gstin", ASCENDING)], unique=True, partialFilterExpression={"gstin": _STRING}),
        IndexModel([("status", ASCENDING)]),
        IndexModel([("created_at", DESCENDING)]),
    ],
    "users": [
        IndexModel([("email", ASCENDING)], unique=True, partialFilterExpression={"email": _STRING}),
        IndexModel([("company_id", ASCENDING), ("role", ASCENDING)]),
    ],
    "otp_challenges": [
        IndexModel([("purpose", ASCENDING), ("target", ASCENDING), ("created_at", DESCENDING)]),
        IndexModel([("expires_at", ASCENDING)], expireAfterSeconds=86400),
    ],
    "signup_requests": [
        IndexModel([("email", ASCENDING)], unique=True),
        IndexModel([("expires_at", ASCENDING)], expireAfterSeconds=0),
    ],
    "subscription_plans": [IndexModel([("code", ASCENDING)], unique=True)],
    "subscriptions": [
        IndexModel([("company_id", ASCENDING), ("status", ASCENDING), ("ends_at", DESCENDING)]),
        IndexModel([("plan_code", ASCENDING)]),
        IndexModel([("status", ASCENDING), ("ends_at", ASCENDING)]),
    ],
    "branches": [IndexModel([("company_id", ASCENDING), ("code", ASCENDING)], unique=True)],
    "expense_categories": [IndexModel([("company_id", ASCENDING), ("name", ASCENDING)], unique=True)],
    "employees": [
        IndexModel([("company_id", ASCENDING), ("mobile", ASCENDING)], unique=True),
        IndexModel([("company_id", ASCENDING), ("employee_code", ASCENDING)], unique=True),
        IndexModel([("user_id", ASCENDING)], unique=True),
        IndexModel([("mobile", ASCENDING), ("is_active", ASCENDING)]),
        IndexModel([("company_id", ASCENDING), ("is_active", ASCENDING), ("name", ASCENDING)]),
    ],
    "invoices": [
        IndexModel([("company_id", ASCENDING), ("idempotency_key", ASCENDING)], unique=True),
        IndexModel([("company_id", ASCENDING), ("invoice_number", ASCENDING), ("gstin", ASCENDING)]),
        IndexModel([("company_id", ASCENDING), ("uploaded_at", DESCENDING)]),
        IndexModel([("company_id", ASCENDING), ("approval_status", ASCENDING), ("uploaded_at", DESCENDING)]),
        IndexModel([("company_id", ASCENDING), ("invoice_date", ASCENDING)]),
        IndexModel([("employee_id", ASCENDING), ("updated_at", DESCENDING)]),
        IndexModel([("company_id", ASCENDING), ("employee_id", ASCENDING), ("uploaded_at", DESCENDING)]),
        IndexModel([("company_id", ASCENDING), ("branch_id", ASCENDING), ("uploaded_at", DESCENDING)]),
        IndexModel([("company_id", ASCENDING), ("category_id", ASCENDING), ("uploaded_at", DESCENDING)]),
        IndexModel([("uploaded_at", DESCENDING)]),
    ],
    "notifications": [
        IndexModel([("employee_id", ASCENDING), ("created_at", DESCENDING)]),
        IndexModel([("company_id", ASCENDING), ("type", ASCENDING), ("created_at", DESCENDING)]),
        IndexModel([("company_id", ASCENDING), ("created_at", DESCENDING)]),
    ],
    "devices": [
        IndexModel([("company_id", ASCENDING), ("device_id", ASCENDING)], unique=True),
        IndexModel([("company_id", ASCENDING), ("employee_id", ASCENDING)]),
        IndexModel([("fcm_token", ASCENDING)], partialFilterExpression={"fcm_token": _STRING}),
    ],
    "audit_logs": [
        IndexModel([("company_id", ASCENDING), ("created_at", DESCENDING)]),
        IndexModel([("created_at", ASCENDING)], expireAfterSeconds=AUDIT_RETENTION_SECONDS),
    ],
    "gstr_imports": [IndexModel([("company_id", ASCENDING), ("created_at", DESCENDING)])],
    "gstr_inward_rows": [
        IndexModel([("company_id", ASCENDING), ("period", ASCENDING), ("return_type", ASCENDING)]),
        IndexModel([("import_id", ASCENDING)]),
    ],
    "itc_matches": [IndexModel([("company_id", ASCENDING), ("period", ASCENDING), ("return_type", ASCENDING), ("status", ASCENDING)])],
    "supplier_reminders": [IndexModel([("company_id", ASCENDING), ("status", ASCENDING), ("created_at", DESCENDING)])],
    "payment_orders": [
        IndexModel([("provider_order_id", ASCENDING)], unique=True),
        IndexModel([("company_id", ASCENDING), ("created_at", DESCENDING)]),
        IndexModel([("status", ASCENDING), ("created_at", DESCENDING)]),
    ],
    "payment_events": [
        IndexModel([("provider_event_id", ASCENDING)], unique=True),
        IndexModel([("created_at", ASCENDING)]),
    ],
    "kv": [IndexModel([("expires_at", ASCENDING)], expireAfterSeconds=0)],
}


async def ensure_indexes(db: AsyncDatabase | None = None) -> None:
    db = db if db is not None else get_database()
    for name, models in INDEXES.items():
        await db[name].create_indexes(models)


# ── Document helpers ─────────────────────────────────────────────────────────


def new_id() -> str:
    return str(uuid4())


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


def as_utc(value: datetime | None) -> datetime | None:
    if value is None:
        return None
    return value if value.tzinfo else value.replace(tzinfo=timezone.utc)


def sid(value: Any) -> str | None:
    """Normalise an id from a path/body (UUID or str) to the stored string form."""
    return str(value) if value is not None else None


def stamp(doc: dict[str, Any], *, timestamps: bool = True) -> dict[str, Any]:
    """Give a new document an `_id` and created/updated timestamps."""
    doc.setdefault("_id", new_id())
    if timestamps:
        now = utcnow()
        doc.setdefault("created_at", now)
        doc.setdefault("updated_at", now)
    return doc


def icontains(term: str) -> dict[str, str]:
    return {"$regex": re.escape(term.strip()), "$options": "i"}


async def paginate(
    collection: AsyncCollection,
    query: dict[str, Any],
    sort: list[tuple[str, int]],
    page: int,
    page_size: int,
    serialize: Callable[[dict[str, Any]], dict],
) -> dict:
    """One page of `query` as `{items, total, page, pageSize}`. `sort` must be stable."""
    total = await collection.count_documents(query)
    cursor = collection.find(query).sort(sort).skip((page - 1) * page_size).limit(page_size)
    rows = await cursor.to_list(length=page_size)
    return {"items": [serialize(row) for row in rows], "total": total, "page": page, "pageSize": page_size}


async def ping() -> bool:
    try:
        await get_client().admin.command("ping")
        return True
    except Exception as exc:  # noqa: BLE001
        logger.error("MongoDB ping failed: %s", exc)
        return False
