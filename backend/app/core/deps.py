from dataclasses import dataclass
from uuid import UUID

import jwt
from fastapi import Depends, Header, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pymongo.asynchronous.database import AsyncDatabase

from app.core.cache import get_json, get_store, set_json
from app.core.config import settings
from app.core.ratelimit import enforce
from app.core.security import decode_token
from app.db.mongo import get_db
from app.models import Role
from app.services.subscription import ensure_company_active

bearer = HTTPBearer(auto_error=False)


@dataclass(frozen=True)
class AuthUser:
    """Snapshot of the authenticated user; load the document when you need to write."""

    id: str
    role: Role
    company_id: str | None
    email: str | None
    token_version: int = 0


@dataclass
class Principal:
    user: AuthUser
    company_id: str | None
    employee_id: str | None


def _user_key(user_id: str) -> str:
    return f"user:{user_id}"


async def invalidate_user(user_id: str) -> None:
    """Call after disabling a user or changing their role/password."""
    await get_store().delete(_user_key(user_id))


async def _load_user(db: AsyncDatabase, user_id: str) -> AuthUser | None:
    cached = await get_json(_user_key(user_id))
    if cached is not None:
        if not cached:
            return None
        return AuthUser(
            id=user_id, role=Role(cached["role"]), company_id=cached.get("companyId"),
            email=cached.get("email"), token_version=cached.get("tv", 0),
        )
    user = await db.users.find_one({"_id": user_id, "is_active": True}, {"role": 1, "company_id": 1, "email": 1, "token_version": 1})
    if not user:
        await set_json(_user_key(user_id), {}, settings.auth_cache_seconds)
        return None
    auth = AuthUser(
        id=user["_id"], role=Role(user["role"]), company_id=user.get("company_id"),
        email=user.get("email"), token_version=user.get("token_version", 0),
    )
    await set_json(
        _user_key(user_id),
        {"role": auth.role.value, "companyId": auth.company_id, "email": auth.email, "tv": auth.token_version},
        settings.auth_cache_seconds,
    )
    return auth


def _optional_uuid(value: str | None) -> str | None:
    return str(UUID(value)) if value else None


async def current_principal(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer),
    x_company_id: UUID | None = Header(default=None, alias="X-Company-Id"),
    db: AsyncDatabase = Depends(get_db),
) -> Principal:
    return await _authenticate(credentials, x_company_id, db, check_subscription=True)


async def billing_admin_principal(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer),
    x_company_id: UUID | None = Header(default=None, alias="X-Company-Id"),
    db: AsyncDatabase = Depends(get_db),
) -> Principal:
    """Company admin whose subscription may have lapsed (so they can renew)."""
    principal = await _authenticate(credentials, x_company_id, db, check_subscription=False)
    if principal.user.role != Role.company_admin or not principal.company_id:
        raise HTTPException(403, "Company admin role required")
    return principal


async def _authenticate(
    credentials: HTTPAuthorizationCredentials | None,
    x_company_id: UUID | None,
    db: AsyncDatabase,
    *,
    check_subscription: bool,
) -> Principal:
    if not credentials:
        raise HTTPException(401, "Authentication required")
    try:
        claims = decode_token(credentials.credentials)
        user_id = str(UUID(claims["sub"]))
        token_company = _optional_uuid(claims.get("company_id"))
        employee_id = _optional_uuid(claims.get("employee_id"))
    except (jwt.InvalidTokenError, KeyError, ValueError):
        raise HTTPException(401, "Invalid or expired token")
    await enforce(f"user:{user_id}", settings.api_rate_per_minute, 60)
    user = await _load_user(db, user_id)
    if not user:
        raise HTTPException(401, "User disabled")
    if claims.get("tv", 0) != user.token_version:
        raise HTTPException(401, "Session expired; please sign in again")
    if token_company and x_company_id and token_company != str(x_company_id):
        raise HTTPException(403, "Company header does not match token")
    if user.company_id != token_company:
        raise HTTPException(403, "Tenant mismatch")
    if token_company and check_subscription:
        await ensure_company_active(db, token_company)
    return Principal(user=user, company_id=token_company, employee_id=employee_id)


async def employee_principal(principal: Principal = Depends(current_principal)) -> Principal:
    if principal.user.role != Role.employee or not principal.employee_id or not principal.company_id:
        raise HTTPException(403, "Employee role required")
    return principal


async def admin_principal(principal: Principal = Depends(current_principal)) -> Principal:
    if principal.user.role not in (Role.company_admin, Role.super_admin):
        raise HTTPException(403, "Admin role required")
    return principal


async def company_admin_principal(principal: Principal = Depends(admin_principal)) -> Principal:
    if principal.user.role != Role.company_admin or not principal.company_id:
        raise HTTPException(403, "Company admin role required")
    return principal


async def super_principal(principal: Principal = Depends(current_principal)) -> Principal:
    if principal.user.role != Role.super_admin:
        raise HTTPException(403, "Super admin role required")
    return principal


async def current_employee(
    principal: Principal = Depends(employee_principal),
    db: AsyncDatabase = Depends(get_db),
) -> dict:
    employee = await db.employees.find_one(
        {"_id": principal.employee_id, "company_id": principal.company_id, "is_active": True}
    )
    if not employee:
        raise HTTPException(403, "Employee disabled")
    return employee
