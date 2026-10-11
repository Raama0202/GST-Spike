from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.deps import Principal, company_admin_principal, employee_principal
from app.db.session import get_db
from app.models import Branch, Company, ExpenseCategory
from app.schemas.common import CompanySettings, NamedResource

router = APIRouter()
admin_router = APIRouter()


@router.get("/config")
async def company_config(
    principal: Principal = Depends(employee_principal),
    db: AsyncSession = Depends(get_db),
):
    company = await db.get(Company, principal.company_id)
    categories = (
        await db.scalars(
            select(ExpenseCategory).where(
                ExpenseCategory.company_id == principal.company_id,
                ExpenseCategory.is_active.is_(True),
            ).order_by(ExpenseCategory.sort_order, ExpenseCategory.name)
        )
    ).all()
    branches = (
        await db.scalars(
            select(Branch).where(
                Branch.company_id == principal.company_id, Branch.is_active.is_(True)
            ).order_by(Branch.name)
        )
    ).all()
    return {
        "companyId": company.id,
        "companyName": company.name,
        "industry": company.industry,
        "logoUrl": company.logo_url,
        "primaryColorHex": company.primary_color_hex,
        "requiresGps": company.requires_gps,
        "duplicateCheckEnabled": company.duplicate_check_enabled,
        "minOcrConfidenceWarn": float(company.min_ocr_confidence_warn),
        "features": company.features_json,
        "categories": [
            {"id": x.id, "name": x.name, "parentId": x.parent_id, "sortOrder": x.sort_order}
            for x in categories
        ],
        "branches": [{"id": x.id, "name": x.name, "code": x.code} for x in branches],
        "updatedAt": company.updated_at,
    }


@admin_router.get("/settings")
async def get_settings(
    principal: Principal = Depends(company_admin_principal),
    db: AsyncSession = Depends(get_db),
):
    return await db.get(Company, principal.company_id)


@admin_router.patch("/settings")
async def update_settings(
    body: CompanySettings,
    principal: Principal = Depends(company_admin_principal),
    db: AsyncSession = Depends(get_db),
):
    company = await db.get(Company, principal.company_id)
    nullable = {"industry", "logo_url"}
    values = {k: v for k, v in body.model_dump(exclude_unset=True).items() if v is not None or k in nullable}
    if "features" in values:
        values["features_json"] = values.pop("features")
    for field, value in values.items():
        setattr(company, field, value)
    await db.commit()
    await db.refresh(company)
    return company


def resource_json(item):
    return {
        "id": item.id,
        "name": item.name,
        "code": getattr(item, "code", None),
        "parentId": getattr(item, "parent_id", None),
        "sortOrder": getattr(item, "sort_order", 0),
        "isActive": item.is_active,
    }


async def _list(model, company_id, db):
    return {"items": [resource_json(x) for x in (
        await db.scalars(select(model).where(model.company_id == company_id).order_by(model.name))
    ).all()]}


async def _validate_parent(db: AsyncSession, company_id: UUID, parent_id: UUID | None) -> None:
    if parent_id and not await db.scalar(
        select(ExpenseCategory.id).where(
            ExpenseCategory.id == parent_id, ExpenseCategory.company_id == company_id
        )
    ):
        raise HTTPException(400, "Parent category does not belong to company")


@admin_router.get("/categories")
async def categories(principal: Principal = Depends(company_admin_principal), db: AsyncSession = Depends(get_db)):
    return await _list(ExpenseCategory, principal.company_id, db)


@admin_router.post("/categories", status_code=201)
async def create_category(body: NamedResource, principal: Principal = Depends(company_admin_principal), db: AsyncSession = Depends(get_db)):
    await _validate_parent(db, principal.company_id, body.parent_id)
    item = ExpenseCategory(company_id=principal.company_id, name=body.name, parent_id=body.parent_id, sort_order=body.sort_order, is_active=body.is_active)
    db.add(item); await db.commit(); await db.refresh(item)
    return resource_json(item)


@admin_router.patch("/categories/{item_id}")
async def update_category(item_id: UUID, body: NamedResource, principal: Principal = Depends(company_admin_principal), db: AsyncSession = Depends(get_db)):
    item = await db.scalar(select(ExpenseCategory).where(ExpenseCategory.id == item_id, ExpenseCategory.company_id == principal.company_id))
    if not item: raise HTTPException(404, "Category not found")
    if body.parent_id == item_id:
        raise HTTPException(400, "Category cannot be its own parent")
    await _validate_parent(db, principal.company_id, body.parent_id)
    for key in ("name", "parent_id", "sort_order", "is_active"): setattr(item, key, getattr(body, key))
    await db.commit(); return resource_json(item)


@admin_router.delete("/categories/{item_id}", status_code=204)
async def delete_category(item_id: UUID, principal: Principal = Depends(company_admin_principal), db: AsyncSession = Depends(get_db)):
    item = await db.scalar(select(ExpenseCategory).where(ExpenseCategory.id == item_id, ExpenseCategory.company_id == principal.company_id))
    if not item: raise HTTPException(404, "Category not found")
    item.is_active = False; await db.commit()


@admin_router.get("/branches")
async def branches(principal: Principal = Depends(company_admin_principal), db: AsyncSession = Depends(get_db)):
    return await _list(Branch, principal.company_id, db)


@admin_router.post("/branches", status_code=201)
async def create_branch(body: NamedResource, principal: Principal = Depends(company_admin_principal), db: AsyncSession = Depends(get_db)):
    if not body.code: raise HTTPException(400, "Branch code is required")
    item = Branch(company_id=principal.company_id, name=body.name, code=body.code, is_active=body.is_active)
    db.add(item); await db.commit(); await db.refresh(item)
    return resource_json(item)


@admin_router.patch("/branches/{item_id}")
async def update_branch(item_id: UUID, body: NamedResource, principal: Principal = Depends(company_admin_principal), db: AsyncSession = Depends(get_db)):
    item = await db.scalar(select(Branch).where(Branch.id == item_id, Branch.company_id == principal.company_id))
    if not item: raise HTTPException(404, "Branch not found")
    item.name, item.code, item.is_active = body.name, body.code or item.code, body.is_active
    await db.commit(); return resource_json(item)


@admin_router.delete("/branches/{item_id}", status_code=204)
async def delete_branch(item_id: UUID, principal: Principal = Depends(company_admin_principal), db: AsyncSession = Depends(get_db)):
    item = await db.scalar(select(Branch).where(Branch.id == item_id, Branch.company_id == principal.company_id))
    if not item: raise HTTPException(404, "Branch not found")
    item.is_active = False; await db.commit()
