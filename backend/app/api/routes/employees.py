from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query
from pymongo import ReturnDocument
from pymongo.asynchronous.database import AsyncDatabase

from app.core.deps import Principal, company_admin_principal, current_employee, invalidate_user
from app.db.mongo import get_db, icontains, new_id, paginate, sid, utcnow
from app.models import Role
from app.schemas.common import EmployeeCreate, EmployeeUpdate
from app.services.audit import record_audit
from app.services.phone import mobile_variants
from app.services.subscription import enforce_seat_limit, seat_usage

router = APIRouter()
admin_router = APIRouter()

MOBILE_IN_OTHER_COMPANY = (
    "This mobile number is already registered with another company. The employee must be "
    "removed there first, or contact support."
)


async def validate_branch(db: AsyncDatabase, company_id: str, branch_id: str | None) -> None:
    if branch_id and not await db.branches.find_one({"_id": branch_id, "company_id": company_id}, {"_id": 1}):
        raise HTTPException(400, "Branch does not belong to company")


async def branch_names(db: AsyncDatabase, company_id: str) -> dict[str, str]:
    return {b["_id"]: b["name"] async for b in db.branches.find({"company_id": company_id}, {"name": 1})}


def serialize(employee: dict, company_name: str | None = None, branches: dict[str, str] | None = None) -> dict:
    branch_id = employee.get("branch_id")
    return {
        "id": employee["_id"],
        "name": employee["name"],
        "mobile": employee["mobile"],
        "email": employee.get("email"),
        "employeeCode": employee["employee_code"],
        "companyId": employee["company_id"],
        "companyName": company_name,
        "branchId": branch_id,
        "branchName": (branches or {}).get(branch_id) if branch_id else None,
        "isActive": employee.get("is_active", True),
        "createdAt": employee.get("created_at"),
    }


@router.get("/me")
async def me(employee: dict = Depends(current_employee), db: AsyncDatabase = Depends(get_db)):
    company = await db.companies.find_one({"_id": employee["company_id"]}, {"name": 1})
    return serialize(employee, company["name"] if company else None, await branch_names(db, employee["company_id"]))


@admin_router.get("")
async def list_employees(
    page: int = Query(1, ge=1),
    page_size: int = Query(500, alias="pageSize", ge=1, le=1000),
    q: str | None = Query(None, max_length=100),
    active: bool | None = None,
    branch_id: UUID | None = Query(None, alias="branchId"),
    principal: Principal = Depends(company_admin_principal),
    db: AsyncDatabase = Depends(get_db),
):
    query: dict = {"company_id": principal.company_id}
    if active is not None:
        query["is_active"] = active
    if branch_id:
        query["branch_id"] = sid(branch_id)
    if q and q.strip():
        term = icontains(q)
        query["$or"] = [{"name": term}, {"mobile": term}, {"employee_code": term}, {"email": term}]
    branches = await branch_names(db, principal.company_id)
    result = await paginate(
        db.employees, query, [("name", 1), ("_id", 1)], page, page_size,
        lambda e: serialize(e, branches=branches),
    )
    result["seats"] = await seat_usage(db, principal.company_id)
    return result


async def _check_unique(
    db: AsyncDatabase,
    company_id: str,
    *,
    mobile: str | None = None,
    code: str | None = None,
    exclude: str | None = None,
    active: bool = True,
) -> None:
    clashes = []
    if mobile:
        clashes.append({"mobile": {"$in": mobile_variants(mobile)}})
    if code:
        clashes.append({"employee_code": code})
    if clashes:
        query: dict = {"company_id": company_id, "$or": clashes}
        if exclude:
            query["_id"] = {"$ne": exclude}
        if await db.employees.find_one(query, {"_id": 1}):
            raise HTTPException(409, "Mobile or employee code already exists")
    # OTP login looks employees up by mobile alone, so an active number may belong to
    # only one company; otherwise any firm could lock another firm's employee out.
    if mobile and active and await db.employees.find_one(
        {"mobile": {"$in": mobile_variants(mobile)}, "is_active": True, "company_id": {"$ne": company_id}}, {"_id": 1}
    ):
        raise HTTPException(409, MOBILE_IN_OTHER_COMPANY)


@admin_router.post("", status_code=201)
async def create_employee(
    body: EmployeeCreate,
    principal: Principal = Depends(company_admin_principal),
    db: AsyncDatabase = Depends(get_db),
):
    company_id = principal.company_id
    if body.is_active:
        await enforce_seat_limit(db, company_id)
    branch_id = sid(body.branch_id)
    await validate_branch(db, company_id, branch_id)
    await _check_unique(db, company_id, mobile=body.mobile, code=body.employee_code, active=body.is_active)
    now = utcnow()
    user = {
        "_id": new_id(), "company_id": company_id, "role": Role.employee.value, "is_active": body.is_active,
        "refresh_token_hash": None, "created_at": now, "updated_at": now,
    }
    employee = {
        "_id": new_id(), "company_id": company_id, "user_id": user["_id"], "name": body.name,
        "mobile": body.mobile, "email": body.email, "employee_code": body.employee_code,
        "branch_id": branch_id, "is_active": body.is_active, "created_at": now, "updated_at": now,
    }
    await db.users.insert_one(user)
    try:
        await db.employees.insert_one(employee)
    except Exception:
        await db.users.delete_one({"_id": user["_id"]})
        raise
    await record_audit(db, principal, "employee.created", "employee", employee["_id"], f"Added {body.name} ({body.employee_code})")
    return serialize(employee, branches=await branch_names(db, company_id))


@admin_router.patch("/{employee_id}")
async def update_employee(
    employee_id: UUID,
    body: EmployeeUpdate,
    principal: Principal = Depends(company_admin_principal),
    db: AsyncDatabase = Depends(get_db),
):
    company_id = principal.company_id
    employee = await db.employees.find_one({"_id": sid(employee_id), "company_id": company_id})
    if not employee:
        raise HTTPException(404, "Employee not found")
    nullable = {"branch_id", "email"}
    values = {
        field: value
        for field, value in body.model_dump(exclude_unset=True).items()
        if value is not None or field in nullable
    }
    if "branch_id" in values:
        values["branch_id"] = sid(values["branch_id"])
        await validate_branch(db, company_id, values["branch_id"])
    becomes_active = values.get("is_active", employee.get("is_active", True))
    reactivating = bool(values.get("is_active")) and not employee.get("is_active")
    mobile_changed = "mobile" in values and values["mobile"] != employee["mobile"]
    await _check_unique(
        db, company_id,
        mobile=values["mobile"] if mobile_changed else (employee["mobile"] if reactivating else None),
        code=values.get("employee_code") if values.get("employee_code") != employee["employee_code"] else None,
        exclude=employee["_id"],
        active=becomes_active,
    )
    if reactivating:
        await enforce_seat_limit(db, company_id)
    values["updated_at"] = utcnow()
    employee = await db.employees.find_one_and_update(
        {"_id": employee["_id"]}, {"$set": values}, return_document=ReturnDocument.AFTER
    )
    user_changes: dict = {"is_active": employee["is_active"]}
    if not employee["is_active"]:
        user_changes["refresh_token_hash"] = None
    await db.users.update_one({"_id": employee["user_id"]}, {"$set": user_changes})
    await invalidate_user(employee["user_id"])
    changed = sorted(field for field in values if field != "updated_at")
    action = "employee.reactivated" if reactivating else "employee.deactivated" if values.get("is_active") is False else "employee.updated"
    await record_audit(db, principal, action, "employee", employee["_id"], f"{employee['name']}: {', '.join(changed)}")
    return serialize(employee, branches=await branch_names(db, company_id))


@admin_router.delete("/{employee_id}", status_code=204)
async def disable_employee(
    employee_id: UUID,
    principal: Principal = Depends(company_admin_principal),
    db: AsyncDatabase = Depends(get_db),
):
    employee = await db.employees.find_one_and_update(
        {"_id": sid(employee_id), "company_id": principal.company_id},
        {"$set": {"is_active": False, "updated_at": utcnow()}},
    )
    if not employee:
        raise HTTPException(404, "Employee not found")
    await db.users.update_one({"_id": employee["user_id"]}, {"$set": {"is_active": False, "refresh_token_hash": None}})
    await invalidate_user(employee["user_id"])
    await record_audit(db, principal, "employee.deactivated", "employee", employee["_id"], f"Deactivated {employee['name']}")
