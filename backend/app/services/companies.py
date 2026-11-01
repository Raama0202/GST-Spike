"""Company (firm) documents: creation with admin + subscription, deletion, and serializers."""
import asyncio
from datetime import timedelta
from decimal import Decimal
from secrets import token_urlsafe
from typing import Any

from pymongo.asynchronous.database import AsyncDatabase
from pymongo.errors import DuplicateKeyError

from app.db.mongo import new_id, utcnow
from app.models import CompanyStatus, Role, SubscriptionStatus
from app.services import gstin as gst

DEFAULT_CATEGORIES = ("Travel", "Fuel", "Food & Meals", "Office Supplies", "Materials", "Repairs & Maintenance", "Other")
DEFAULT_MIN_OCR_CONFIDENCE = Decimal("0.55")


class EmailTaken(Exception):
    pass


class GstinTaken(Exception):
    pass


def company_doc(
    name: str,
    *,
    industry: str | None = None,
    legal_name: str | None = None,
    gstin: str | None = None,
    status: CompanyStatus = CompanyStatus.pending,
    activation_code: str | None = None,
    features: dict[str, Any] | None = None,
) -> dict[str, Any]:
    now = utcnow()
    return {
        "_id": new_id(),
        "name": name.strip(),
        "legal_name": legal_name.strip() if legal_name else None,
        "gstin": gstin or None,
        "additional_gstins": [],
        "name_aliases": [],
        "state_code": gst.state_code(gstin),
        "industry": industry,
        "logo_url": None,
        "primary_color_hex": None,
        "activation_code": activation_code or token_urlsafe(9),
        "status": status.value,
        "requires_gps": False,
        "duplicate_check_enabled": True,
        "min_ocr_confidence_warn": DEFAULT_MIN_OCR_CONFIDENCE,
        "features_json": features or {},
        "created_at": now,
        "updated_at": now,
    }


async def create_company_with_admin(
    db: AsyncDatabase,
    company: dict[str, Any],
    *,
    admin_email: str,
    password_hash: str,
    admin_name: str | None = None,
    admin_mobile: str | None = None,
    plan_code: str,
    seats: int,
    days: int,
    with_defaults: bool = False,
) -> dict[str, Any]:
    """Insert the company, its first admin and an active subscription. Undoes the
    company if the admin email or GSTIN is already registered."""
    if await db.users.find_one({"email": admin_email}, {"_id": 1}):
        raise EmailTaken()
    if company.get("gstin") and await db.companies.find_one({"gstin": company["gstin"]}, {"_id": 1}):
        raise GstinTaken()
    try:
        await db.companies.insert_one(company)
    except DuplicateKeyError as exc:
        raise GstinTaken() from exc
    now = utcnow()
    user = {
        "_id": new_id(),
        "company_id": company["_id"],
        "email": admin_email,
        "name": admin_name,
        "mobile": admin_mobile,
        "password_hash": password_hash,
        "role": Role.company_admin.value,
        "is_active": True,
        "email_verified": with_defaults,
        "refresh_token_hash": None,
        "created_at": now,
        "updated_at": now,
    }
    try:
        await db.users.insert_one(user)
    except DuplicateKeyError as exc:
        await db.companies.delete_one({"_id": company["_id"]})
        raise EmailTaken() from exc
    await db.subscriptions.insert_one({
        "_id": new_id(),
        "company_id": company["_id"],
        "plan_code": plan_code,
        "seats": seats,
        "starts_at": now,
        "ends_at": now + timedelta(days=days),
        "status": SubscriptionStatus.active.value,
        "created_at": now,
    })
    if with_defaults:
        await db.branches.insert_one({
            "_id": new_id(), "company_id": company["_id"], "name": "Head Office", "code": "HO",
            "is_active": True, "created_at": now, "updated_at": now,
        })
        await db.expense_categories.insert_many([
            {"_id": new_id(), "company_id": company["_id"], "name": name, "parent_id": None,
             "sort_order": index, "is_active": True, "created_at": now, "updated_at": now}
            for index, name in enumerate(DEFAULT_CATEGORIES, 1)
        ])
    return user


def settings_json(company: dict[str, Any]) -> dict[str, Any]:
    """Company settings as the admin clients read them (snake_case keys)."""
    return {
        "id": company["_id"],
        "name": company["name"],
        "legal_name": company.get("legal_name"),
        "gstin": company.get("gstin"),
        "additional_gstins": company.get("additional_gstins") or [],
        "name_aliases": company.get("name_aliases") or [],
        "state_code": company.get("state_code"),
        "industry": company.get("industry"),
        "logo_url": company.get("logo_url"),
        "primary_color_hex": company.get("primary_color_hex"),
        "activation_code": company.get("activation_code"),
        "status": company.get("status"),
        "requires_gps": bool(company.get("requires_gps")),
        "duplicate_check_enabled": company.get("duplicate_check_enabled", True),
        "min_ocr_confidence_warn": float(company.get("min_ocr_confidence_warn") or DEFAULT_MIN_OCR_CONFIDENCE),
        "features_json": company.get("features_json") or {},
        "gstin_check": {k: v for k, v in (company.get("gstin_check") or {}).items() if k != "source"} or None,
        "created_at": company.get("created_at"),
        "updated_at": company.get("updated_at"),
    }


COMPANY_COLLECTIONS = (
    "invoices", "notifications", "devices", "employees", "users", "branches", "expense_categories",
    "subscriptions", "gstr_imports", "gstr_inward_rows", "itc_matches", "supplier_reminders", "audit_logs",
)
IMAGE_FIELDS = ("original_image_path", "compressed_image_path", "thumbnail_image_path")
_purges: set[asyncio.Task] = set()


async def _discard_images(keys: list[str]) -> None:
    from app.services.storage import discard

    for start in range(0, len(keys), 200):
        await discard(keys[start:start + 200])


async def purge_company(db: AsyncDatabase, company_id: str) -> int:
    """Permanently remove a firm and everything it owns. Payment orders stay (with the
    company name copied onto them) because they are the platform's own revenue records."""
    from app.core.deps import invalidate_user
    from app.services.subscription import invalidate_company

    company = await db.companies.find_one({"_id": company_id}, {"name": 1})
    if not company:
        return 0
    user_ids = [u["_id"] async for u in db.users.find({"company_id": company_id}, {"_id": 1})]
    keys = [
        row[field]
        async for row in db.invoices.find({"company_id": company_id}, {field: 1 for field in IMAGE_FIELDS})
        for field in IMAGE_FIELDS
        if row.get(field)
    ]
    await db.payment_orders.update_many({"company_id": company_id}, {"$set": {"company_name": company["name"]}})
    removed = 0
    for name in COMPANY_COLLECTIONS:
        removed += (await db[name].delete_many({"company_id": company_id})).deleted_count
    await db.companies.delete_one({"_id": company_id})
    for user_id in user_ids:
        await invalidate_user(user_id)
    await invalidate_company(company_id)
    if keys:
        # Image deletion can take minutes for large firms; the records are already gone.
        task = asyncio.create_task(_discard_images(keys))
        _purges.add(task)
        task.add_done_callback(_purges.discard)
    return removed


def all_gstins(company: dict[str, Any]) -> list[str]:
    values = [company.get("gstin"), *(company.get("additional_gstins") or [])]
    return list(dict.fromkeys(value for value in values if value))
