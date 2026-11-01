import re
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query
from pymongo import ReturnDocument
from pymongo.asynchronous.database import AsyncDatabase

from app.core.config import settings as app_settings
from app.core.deps import Principal, company_admin_principal, employee_principal
from app.core.ratelimit import enforce
from app.core.security import verify_password_async
from app.db.mongo import get_db, new_id, paginate, sid, utcnow
from app.schemas.common import CompanyDelete, CompanySettings, NamedResource
from app.services import gstin as gst
from app.services.audit import audit_json, record_audit
from app.services.companies import all_gstins, purge_company, settings_json
from app.services.gstin_verify import company_gstin_check
from app.services.subscription import invalidate_company

router = APIRouter()
admin_router = APIRouter()


@router.get("/config")
async def company_config(
    principal: Principal = Depends(employee_principal),
    db: AsyncDatabase = Depends(get_db),
):
    company = await db.companies.find_one({"_id": principal.company_id})
    if not company:
        raise HTTPException(404, "Company not found")
    categories = await db.expense_categories.find(
        {"company_id": principal.company_id, "is_active": True}
    ).sort([("sort_order", 1), ("name", 1)]).to_list(None)
    branches = await db.branches.find(
        {"company_id": principal.company_id, "is_active": True}
    ).sort([("name", 1)]).to_list(None)
    return {
        "companyId": company["_id"],
        "companyName": company["name"],
        "legalName": company.get("legal_name"),
        "gstin": company.get("gstin"),
        # Every GSTIN/name the firm uses, so scanners never record the firm itself as the vendor.
        "gstins": all_gstins(company),
        "nameAliases": company.get("name_aliases") or [],
        "industry": company.get("industry"),
        "logoUrl": company.get("logo_url"),
        "primaryColorHex": company.get("primary_color_hex"),
        "requiresGps": bool(company.get("requires_gps")),
        "duplicateCheckEnabled": company.get("duplicate_check_enabled", True),
        "minOcrConfidenceWarn": settings_json(company)["min_ocr_confidence_warn"],
        "features": company.get("features_json") or {},
        "gstinLiveCheck": app_settings.gstin_verify_configured,
        "categories": [
            {"id": x["_id"], "name": x["name"], "parentId": x.get("parent_id"), "sortOrder": x.get("sort_order", 0)}
            for x in categories
        ],
        "branches": [{"id": x["_id"], "name": x["name"], "code": x.get("code")} for x in branches],
        "updatedAt": company.get("updated_at"),
    }


@admin_router.get("/settings")
async def get_settings(
    principal: Principal = Depends(company_admin_principal),
    db: AsyncDatabase = Depends(get_db),
):
    company = await db.companies.find_one({"_id": principal.company_id})
    if not company:
        raise HTTPException(404, "Company not found")
    return settings_json(company)


@admin_router.patch("/settings")
async def update_settings(
    body: CompanySettings,
    principal: Principal = Depends(company_admin_principal),
    db: AsyncDatabase = Depends(get_db),
):
    nullable = {"industry", "logo_url", "legal_name", "gstin", "primary_color_hex"}
    values = {k: v for k, v in body.model_dump(exclude_unset=True).items() if v is not None or k in nullable}
    # Feature flags are plan entitlements, managed by the platform (super admin) only.
    values.pop("features", None)
    if "gstin" in values:
        values["state_code"] = gst.state_code(values["gstin"])
        if values["gstin"] and await db.companies.find_one(
            {"gstin": values["gstin"], "_id": {"$ne": principal.company_id}}, {"_id": 1}
        ):
            raise HTTPException(409, "This GSTIN is already registered to another company")
        values["gstin_check"] = await company_gstin_check(values["gstin"])
    values["updated_at"] = utcnow()
    company = await db.companies.find_one_and_update(
        {"_id": principal.company_id}, {"$set": values}, return_document=ReturnDocument.AFTER
    )
    if not company:
        raise HTTPException(404, "Company not found")
    await invalidate_company(principal.company_id)
    changed = sorted(k for k in values if k not in ("updated_at", "state_code"))
    await record_audit(db, principal, "settings.updated", "company", principal.company_id, "Updated " + ", ".join(changed))
    return settings_json(company)


@admin_router.post("/delete", status_code=204)
async def delete_company(body: CompanyDelete, principal: Principal = Depends(company_admin_principal), db: AsyncDatabase = Depends(get_db)):
    """Permanent account deletion requested by the firm itself (App Store 5.1.1(v))."""
    await enforce(f"company-delete:{principal.user.id}", 5, 3600, "Too many attempts; try again later")
    user = await db.users.find_one({"_id": principal.user.id}, {"password_hash": 1})
    company = await db.companies.find_one({"_id": principal.company_id}, {"name": 1})
    if not user or not company:
        raise HTTPException(404, "Company not found")
    if not await verify_password_async(body.password, user.get("password_hash")):
        raise HTTPException(400, "Password is incorrect")
    if body.confirm_name.strip().casefold() != company["name"].strip().casefold():
        raise HTTPException(400, "Type the company name exactly as shown to confirm")
    await purge_company(db, principal.company_id)
    await record_audit(
        db, principal, "company.deleted", "company", principal.company_id,
        f"{company['name']} deleted by its admin", company_id=None, details={"name": company["name"]},
    )


@admin_router.get("/audit")
async def audit_log(
    page: int = Query(1, ge=1),
    page_size: int = Query(50, alias="pageSize", ge=1, le=200),
    action: str | None = Query(None, max_length=60),
    principal: Principal = Depends(company_admin_principal),
    db: AsyncDatabase = Depends(get_db),
):
    query: dict = {"company_id": principal.company_id}
    if action:
        query["action"] = {"$regex": "^" + re.escape(action)}
    return await paginate(db.audit_logs, query, [("created_at", -1), ("_id", 1)], page, page_size, audit_json)


def resource_json(item: dict) -> dict:
    return {
        "id": item["_id"],
        "name": item["name"],
        "code": item.get("code"),
        "parentId": item.get("parent_id"),
        "sortOrder": item.get("sort_order", 0),
        "isActive": item.get("is_active", True),
    }


async def _list(collection, company_id: str) -> dict:
    rows = await collection.find({"company_id": company_id}).sort([("name", 1)]).to_list(None)
    return {"items": [resource_json(x) for x in rows]}


async def _validate_parent(db: AsyncDatabase, company_id: str, parent_id: str | None) -> None:
    if parent_id and not await db.expense_categories.find_one({"_id": parent_id, "company_id": company_id}, {"_id": 1}):
        raise HTTPException(400, "Parent category does not belong to company")


async def _reject_cycle(db: AsyncDatabase, company_id: str, item_id: str, parent_id: str | None) -> None:
    seen = {item_id}
    while parent_id:
        if parent_id in seen:
            raise HTTPException(400, "A category cannot be placed under its own sub-category")
        seen.add(parent_id)
        parent = await db.expense_categories.find_one({"_id": parent_id, "company_id": company_id}, {"parent_id": 1})
        parent_id = parent.get("parent_id") if parent else None


@admin_router.get("/categories")
async def categories(principal: Principal = Depends(company_admin_principal), db: AsyncDatabase = Depends(get_db)):
    return await _list(db.expense_categories, principal.company_id)


@admin_router.post("/categories", status_code=201)
async def create_category(body: NamedResource, principal: Principal = Depends(company_admin_principal), db: AsyncDatabase = Depends(get_db)):
    parent_id = sid(body.parent_id)
    await _validate_parent(db, principal.company_id, parent_id)
    now = utcnow()
    item = {
        "_id": new_id(), "company_id": principal.company_id, "name": body.name, "parent_id": parent_id,
        "sort_order": body.sort_order, "is_active": body.is_active, "created_at": now, "updated_at": now,
    }
    await db.expense_categories.insert_one(item)
    await record_audit(db, principal, "category.created", "category", item["_id"], f"Added category {body.name}")
    return resource_json(item)


@admin_router.patch("/categories/{item_id}")
async def update_category(item_id: UUID, body: NamedResource, principal: Principal = Depends(company_admin_principal), db: AsyncDatabase = Depends(get_db)):
    key = {"_id": sid(item_id), "company_id": principal.company_id}
    if not await db.expense_categories.find_one(key, {"_id": 1}):
        raise HTTPException(404, "Category not found")
    parent_id = sid(body.parent_id)
    if parent_id == key["_id"]:
        raise HTTPException(400, "Category cannot be its own parent")
    await _validate_parent(db, principal.company_id, parent_id)
    await _reject_cycle(db, principal.company_id, key["_id"], parent_id)
    item = await db.expense_categories.find_one_and_update(
        key,
        {"$set": {"name": body.name, "parent_id": parent_id, "sort_order": body.sort_order,
                  "is_active": body.is_active, "updated_at": utcnow()}},
        return_document=ReturnDocument.AFTER,
    )
    await record_audit(db, principal, "category.updated", "category", item["_id"], f"Updated category {body.name}")
    return resource_json(item)


@admin_router.delete("/categories/{item_id}", status_code=204)
async def delete_category(item_id: UUID, principal: Principal = Depends(company_admin_principal), db: AsyncDatabase = Depends(get_db)):
    result = await db.expense_categories.update_one(
        {"_id": sid(item_id), "company_id": principal.company_id}, {"$set": {"is_active": False, "updated_at": utcnow()}}
    )
    if not result.matched_count:
        raise HTTPException(404, "Category not found")
    await record_audit(db, principal, "category.deactivated", "category", sid(item_id), "Deactivated a category")


@admin_router.get("/branches")
async def branches(principal: Principal = Depends(company_admin_principal), db: AsyncDatabase = Depends(get_db)):
    return await _list(db.branches, principal.company_id)


@admin_router.post("/branches", status_code=201)
async def create_branch(body: NamedResource, principal: Principal = Depends(company_admin_principal), db: AsyncDatabase = Depends(get_db)):
    if not body.code:
        raise HTTPException(400, "Branch code is required")
    now = utcnow()
    item = {
        "_id": new_id(), "company_id": principal.company_id, "name": body.name, "code": body.code,
        "is_active": body.is_active, "created_at": now, "updated_at": now,
    }
    await db.branches.insert_one(item)
    await record_audit(db, principal, "branch.created", "branch", item["_id"], f"Added branch {body.name}")
    return resource_json(item)


@admin_router.patch("/branches/{item_id}")
async def update_branch(item_id: UUID, body: NamedResource, principal: Principal = Depends(company_admin_principal), db: AsyncDatabase = Depends(get_db)):
    key = {"_id": sid(item_id), "company_id": principal.company_id}
    existing = await db.branches.find_one(key)
    if not existing:
        raise HTTPException(404, "Branch not found")
    item = await db.branches.find_one_and_update(
        key,
        {"$set": {"name": body.name, "code": body.code or existing.get("code"), "is_active": body.is_active, "updated_at": utcnow()}},
        return_document=ReturnDocument.AFTER,
    )
    await record_audit(db, principal, "branch.updated", "branch", item["_id"], f"Updated branch {body.name}")
    return resource_json(item)


@admin_router.delete("/branches/{item_id}", status_code=204)
async def delete_branch(item_id: UUID, principal: Principal = Depends(company_admin_principal), db: AsyncDatabase = Depends(get_db)):
    result = await db.branches.update_one(
        {"_id": sid(item_id), "company_id": principal.company_id}, {"$set": {"is_active": False, "updated_at": utcnow()}}
    )
    if not result.matched_count:
        raise HTTPException(404, "Branch not found")
    await record_audit(db, principal, "branch.deactivated", "branch", sid(item_id), "Deactivated a branch")
