from hashlib import sha256
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Request, Response
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.config import settings
from app.core.deps import Principal, admin_principal, invalidate_user
from app.core.ratelimit import (
    check_login_lockout,
    clear_login_failures,
    client_ip,
    enforce,
    record_login_failure,
)
from app.core.security import create_token, decode_token, hash_password_async, verify_password_async
from app.db.session import get_db
from app.models import Company, CompanyStatus, Employee, Role, User
from app.schemas.common import AdminLogin, ChangePassword, OTPRequest, OTPVerify, RefreshRequest
from app.services.otp import create_challenge, verify_challenge
from app.services.subscription import require_active_subscription

router = APIRouter()
admin_router = APIRouter()


def employee_json(employee: Employee, company: Company) -> dict:
    return {
        "id": employee.id,
        "name": employee.name,
        "mobile": employee.mobile,
        "employeeCode": employee.employee_code,
        "companyId": employee.company_id,
        "companyName": company.name,
        "branchId": employee.branch_id,
        "branchName": employee.branch.name if employee.branch else None,
    }


async def issue_tokens(db: AsyncSession, user: User, employee_id=None) -> tuple[str, str, int]:
    access, expires = create_token(user.id, user.role.value, user.company_id, employee_id)
    refresh, _ = create_token(user.id, user.role.value, user.company_id, employee_id, "refresh")
    user.refresh_token_hash = sha256(refresh.encode()).hexdigest()
    await db.commit()
    return access, refresh, expires


@router.post("/otp/request")
async def request_otp(body: OTPRequest, request: Request, db: AsyncSession = Depends(get_db)):
    await enforce(f"otp-ip:{client_ip(request)}", settings.otp_ip_rate_per_hour, 3600, "Too many OTP requests from this network; try again later")
    employees = (
        await db.scalars(
            select(Employee).where(Employee.mobile == body.mobile, Employee.is_active.is_(True)).limit(2)
        )
    ).all()
    if not employees:
        raise HTTPException(404, "No active employee is registered for this mobile")
    if len(employees) > 1:
        raise HTTPException(409, "Mobile belongs to multiple companies; contact administrator")
    await require_active_subscription(db, employees[0].company_id)
    await create_challenge(db, body.mobile)
    return {"ok": True}


@router.post("/otp/verify")
async def verify_otp(body: OTPVerify, request: Request, db: AsyncSession = Depends(get_db)):
    await enforce(f"otp-verify-ip:{client_ip(request)}", settings.otp_ip_rate_per_hour * 2, 3600)
    if not await verify_challenge(db, body.mobile, body.otp):
        raise HTTPException(401, "Invalid or expired OTP")
    employee = await db.scalar(
        select(Employee)
        .options(selectinload(Employee.branch), selectinload(Employee.user))
        .where(Employee.mobile == body.mobile, Employee.is_active.is_(True))
    )
    if not employee or not employee.user.is_active:
        raise HTTPException(401, "Employee disabled")
    company = await db.get(Company, employee.company_id)
    await require_active_subscription(db, employee.company_id)
    access, refresh, expires = await issue_tokens(db, employee.user, employee.id)
    return {
        "accessToken": access,
        "refreshToken": refresh,
        "expiresIn": expires,
        "employee": employee_json(employee, company),
    }


@router.post("/token/refresh")
async def refresh_token(body: RefreshRequest, request: Request, db: AsyncSession = Depends(get_db)):
    await enforce(f"refresh-ip:{client_ip(request)}", 120, 60)
    try:
        claims = decode_token(body.refresh_token, "refresh")
        user = await db.get(User, UUID(claims["sub"]))
    except Exception:
        raise HTTPException(401, "Invalid or expired refresh token")
    presented_hash = sha256(body.refresh_token.encode()).hexdigest()
    if not user or not user.is_active or user.refresh_token_hash != presented_hash:
        raise HTTPException(401, "Refresh token revoked")
    employee_id = claims.get("employee_id")
    access, _ = create_token(user.id, user.role.value, user.company_id, employee_id)
    refresh, _ = create_token(user.id, user.role.value, user.company_id, employee_id, "refresh")
    expires = settings.jwt_access_minutes * 60
    # Compare-and-swap so two concurrent refreshes with the same token can't both win.
    rotated = await db.execute(
        update(User)
        .where(User.id == user.id, User.refresh_token_hash == presented_hash)
        .values(refresh_token_hash=sha256(refresh.encode()).hexdigest())
        .execution_options(synchronize_session=False)
    )
    if rotated.rowcount != 1:
        await db.rollback()
        raise HTTPException(401, "Refresh token revoked")
    await db.commit()
    return {"accessToken": access, "refreshToken": refresh, "expiresIn": expires}


@router.post("/logout", status_code=204)
async def logout(body: RefreshRequest, db: AsyncSession = Depends(get_db)):
    try:
        claims = decode_token(body.refresh_token, "refresh")
        user = await db.get(User, UUID(claims["sub"]))
        if user and user.refresh_token_hash == sha256(body.refresh_token.encode()).hexdigest():
            user.refresh_token_hash = None
            await db.commit()
    except Exception:
        pass
    return Response(status_code=204)


@admin_router.post("/login")
async def admin_login(body: AdminLogin, request: Request, db: AsyncSession = Depends(get_db)):
    email = body.email.lower()
    await enforce(f"login-ip:{client_ip(request)}", settings.login_rate_per_minute * 4, 60, "Too many sign-in attempts; wait a minute")
    await enforce(f"login:{email}", settings.login_rate_per_minute, 60, "Too many sign-in attempts; wait a minute")
    await check_login_lockout(email)
    user = await db.scalar(select(User).where(User.email == email))
    password_ok = await verify_password_async(body.password, user.password_hash if user else None)
    if (
        not user
        or user.role not in (Role.company_admin, Role.super_admin)
        or not password_ok
        or not user.is_active
    ):
        await record_login_failure(email)
        raise HTTPException(401, "Invalid email or password")
    await clear_login_failures(email)
    billing_required = False
    if user.company_id:
        try:
            await require_active_subscription(db, user.company_id)
        except HTTPException as exc:
            # With online payments on, let an expired (not suspended) company sign in to renew.
            company = await db.get(Company, user.company_id)
            renewable = (
                settings.payments_configured
                and exc.detail == "Subscription expired"
                and company is not None
                and company.status != CompanyStatus.suspended
            )
            if not renewable:
                raise
            billing_required = True
    access, refresh, expires = await issue_tokens(db, user)
    return {
        "accessToken": access,
        "refreshToken": refresh,
        "expiresIn": expires,
        "billingRequired": billing_required,
        "user": {"id": user.id, "email": user.email, "role": user.role, "companyId": user.company_id},
    }


@admin_router.post("/password")
async def change_password(
    body: ChangePassword,
    principal: Principal = Depends(admin_principal),
    db: AsyncSession = Depends(get_db),
):
    await enforce(f"pwchange:{principal.user.id}", 5, 300, "Too many attempts; try again in a few minutes")
    user = await db.get(User, principal.user.id)
    if not user or not await verify_password_async(body.current_password, user.password_hash):
        raise HTTPException(400, "Current password is incorrect")
    if body.current_password == body.new_password:
        raise HTTPException(400, "New password must be different from the current one")
    user.password_hash = await hash_password_async(body.new_password)
    # Sign out every other session; the caller gets fresh tokens.
    access, refresh, expires = await issue_tokens(db, user)
    await invalidate_user(user.id)
    return {"accessToken": access, "refreshToken": refresh, "expiresIn": expires}
