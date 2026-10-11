from dataclasses import dataclass
from uuid import UUID

import jwt
from fastapi import Depends, Header, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.cache import get_json, get_store, set_json
from app.core.config import settings
from app.core.ratelimit import enforce
from app.core.security import decode_token
from app.db.session import get_db
from app.models import Employee, Role, User
from app.services.subscription import ensure_company_active

bearer = HTTPBearer(auto_error=False)


@dataclass(frozen=True)
class AuthUser:
    """Snapshot of the authenticated user; load the ORM row when you need to write."""

    id: UUID
    role: Role
    company_id: UUID | None
    email: str | None


@dataclass
class Principal:
    user: AuthUser
    company_id: UUID | None
    employee_id: UUID | None


def _user_key(user_id: UUID) -> str:
    return f"user:{user_id}"


async def invalidate_user(user_id: UUID) -> None:
    """Call after disabling a user or changing their role/password."""
    await get_store().delete(_user_key(user_id))


async def _load_user(db: AsyncSession, user_id: UUID) -> AuthUser | None:
    cached = await get_json(_user_key(user_id))
    if cached is not None:
        if not cached:
            return None
        return AuthUser(
            id=user_id,
            role=Role(cached["role"]),
            company_id=UUID(cached["companyId"]) if cached.get("companyId") else None,
            email=cached.get("email"),
        )
    user = await db.scalar(select(User).where(User.id == user_id, User.is_active.is_(True)))
    if not user:
        await set_json(_user_key(user_id), {}, settings.auth_cache_seconds)
        return None
    auth = AuthUser(id=user.id, role=user.role, company_id=user.company_id, email=user.email)
    await set_json(
        _user_key(user_id),
        {"role": user.role.value, "companyId": str(user.company_id) if user.company_id else None, "email": user.email},
        settings.auth_cache_seconds,
    )
    return auth


async def current_principal(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer),
    x_company_id: UUID | None = Header(default=None, alias="X-Company-Id"),
    db: AsyncSession = Depends(get_db),
) -> Principal:
    return await _authenticate(credentials, x_company_id, db, check_subscription=True)


async def billing_admin_principal(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer),
    x_company_id: UUID | None = Header(default=None, alias="X-Company-Id"),
    db: AsyncSession = Depends(get_db),
) -> Principal:
    """Company admin whose subscription may have lapsed (so they can renew)."""
    principal = await _authenticate(credentials, x_company_id, db, check_subscription=False)
    if principal.user.role != Role.company_admin or not principal.company_id:
        raise HTTPException(403, "Company admin role required")
    return principal


async def _authenticate(
    credentials: HTTPAuthorizationCredentials | None,
    x_company_id: UUID | None,
    db: AsyncSession,
    *,
    check_subscription: bool,
) -> Principal:
    if not credentials:
        raise HTTPException(401, "Authentication required")
    try:
        claims = decode_token(credentials.credentials)
        user_id = UUID(claims["sub"])
        token_company = UUID(claims["company_id"]) if claims.get("company_id") else None
        employee_id = UUID(claims["employee_id"]) if claims.get("employee_id") else None
    except (jwt.InvalidTokenError, KeyError, ValueError):
        raise HTTPException(401, "Invalid or expired token")
    await enforce(f"user:{user_id}", settings.api_rate_per_minute, 60)
    user = await _load_user(db, user_id)
    if not user:
        raise HTTPException(401, "User disabled")
    if token_company and x_company_id and token_company != x_company_id:
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
    db: AsyncSession = Depends(get_db),
) -> Employee:
    employee = await db.scalar(
        select(Employee).where(
            Employee.id == principal.employee_id,
            Employee.company_id == principal.company_id,
            Employee.is_active.is_(True),
        )
    )
    if not employee:
        raise HTTPException(403, "Employee disabled")
    return employee
