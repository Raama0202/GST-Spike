import logging
from datetime import timedelta
from hashlib import sha256
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Request, Response
from pymongo import ReturnDocument
from pymongo.asynchronous.database import AsyncDatabase

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
from app.db.mongo import as_utc, get_db, utcnow
from app.models import CompanyStatus, OtpPurpose, Role
from app.schemas.common import (
    AdminLogin,
    ChangePassword,
    EmailOnly,
    FirmRegistration,
    OTPRequest,
    OTPVerify,
    PasswordReset,
    RefreshRequest,
    RegistrationVerify,
)
from app.services.companies import EmailTaken, GstinTaken, company_doc, create_company_with_admin
from app.services.email import EmailUnavailable
from app.services.audit import record_audit
from app.services.gstin_verify import blocking_reason, check_doc, verify_gstin
from app.services.otp import create_challenge, mask_email, mask_mobile, verify_challenge
from app.services.phone import mobile_variants
from app.services.sms import SMSUnavailable
from app.services.subscription import require_active_subscription

logger = logging.getLogger(__name__)

router = APIRouter()
admin_router = APIRouter()

SIGNUP_REQUEST_HOURS = 24
EMAIL_LOCKOUT_FACTOR = 5
EMAIL_TAKEN = "An account with this email already exists. Sign in or reset your password."
GSTIN_TAKEN = "This GSTIN is already registered. Ask your firm's admin to add you, or contact support."
NO_EMAIL_FOR_OTP = (
    "Login codes are sent by email, and no email address is saved for you. "
    "Ask your administrator to add your email in the admin console, then try again."
)


def employee_json(employee: dict, company: dict, branch: dict | None = None) -> dict:
    return {
        "id": employee["_id"],
        "name": employee["name"],
        "mobile": employee["mobile"],
        "email": employee.get("email"),
        "employeeCode": employee["employee_code"],
        "companyId": employee["company_id"],
        "companyName": company["name"],
        "branchId": employee.get("branch_id"),
        "branchName": branch["name"] if branch else None,
    }


def _hash_refresh(token: str) -> str:
    return sha256(token.encode()).hexdigest()


async def issue_tokens(db: AsyncDatabase, user: dict, employee_id: str | None = None) -> tuple[str, str, int]:
    role = Role(user["role"]).value
    version = user.get("token_version", 0)
    access, expires = create_token(user["_id"], role, user.get("company_id"), employee_id, token_version=version)
    refresh, _ = create_token(user["_id"], role, user.get("company_id"), employee_id, "refresh", version)
    await db.users.update_one({"_id": user["_id"]}, {"$set": {"refresh_token_hash": _hash_refresh(refresh)}})
    return access, refresh, expires


def _admin_session(user: dict, tokens: tuple[str, str, int], billing_required: bool = False) -> dict:
    access, refresh, expires = tokens
    return {
        "accessToken": access,
        "refreshToken": refresh,
        "expiresIn": expires,
        "billingRequired": billing_required,
        "user": {"id": user["_id"], "email": user.get("email"), "role": user["role"], "companyId": user.get("company_id")},
    }


def _employee_otp_channel(employee: dict) -> str:
    """Email codes are free (Brevo/SMTP); SMS is used when the employee has no email."""
    preference = settings.employee_otp_channel.strip().lower()
    email = employee.get("email")
    if preference == "email":
        if not email:
            raise HTTPException(400, "No email is registered for this employee; ask your administrator to add one")
        return "email"
    if preference == "sms":
        return "sms"
    if email and settings.email_configured:
        return "email"
    if settings.sms_configured:
        return "sms"
    if email:
        raise EmailUnavailable()
    if settings.email_configured:
        raise HTTPException(400, NO_EMAIL_FOR_OTP)
    raise SMSUnavailable()


# ── Employee (mobile app) ────────────────────────────────────────────────────


@router.post("/otp/request")
async def request_otp(body: OTPRequest, request: Request, db: AsyncDatabase = Depends(get_db)):
    await enforce(f"otp-ip:{client_ip(request)}", settings.otp_ip_rate_per_hour, 3600, "Too many OTP requests from this network; try again later")
    employees = await db.employees.find({"mobile": {"$in": mobile_variants(body.mobile)}, "is_active": True}).limit(2).to_list(2)
    if not employees:
        raise HTTPException(404, "No active employee is registered for this mobile")
    if len(employees) > 1:
        raise HTTPException(409, "Mobile belongs to multiple companies; contact administrator")
    employee = employees[0]
    await require_active_subscription(db, employee["company_id"])
    demo_code = settings.demo_otp_for(body.mobile)
    channel = "sms" if demo_code else _employee_otp_channel(employee)
    destination = employee["email"] if channel == "email" else body.mobile
    await create_challenge(db, body.mobile, channel=channel, destination=destination, demo_code=demo_code)
    return {
        "ok": True,
        "channel": channel,
        "destination": mask_email(destination) if channel == "email" else mask_mobile(destination),
    }


@router.post("/otp/verify")
async def verify_otp(body: OTPVerify, request: Request, db: AsyncDatabase = Depends(get_db)):
    await enforce(f"otp-verify-ip:{client_ip(request)}", settings.otp_ip_rate_per_hour * 2, 3600)
    if not await verify_challenge(db, body.mobile, body.otp):
        raise HTTPException(401, "Invalid or expired OTP")
    employee = await db.employees.find_one({"mobile": {"$in": mobile_variants(body.mobile)}, "is_active": True})
    user = await db.users.find_one({"_id": employee["user_id"]}) if employee else None
    if not employee or not user or not user.get("is_active"):
        raise HTTPException(401, "Employee disabled")
    await require_active_subscription(db, employee["company_id"])
    company = await db.companies.find_one({"_id": employee["company_id"]})
    branch = await db.branches.find_one({"_id": employee["branch_id"]}) if employee.get("branch_id") else None
    access, refresh, expires = await issue_tokens(db, user, employee["_id"])
    return {
        "accessToken": access,
        "refreshToken": refresh,
        "expiresIn": expires,
        "employee": employee_json(employee, company, branch),
    }


@router.post("/token/refresh")
async def refresh_token(body: RefreshRequest, request: Request, db: AsyncDatabase = Depends(get_db)):
    await enforce(f"refresh-ip:{client_ip(request)}", 120, 60)
    try:
        claims = decode_token(body.refresh_token, "refresh")
        user = await db.users.find_one({"_id": str(UUID(claims["sub"]))})
    except Exception:
        raise HTTPException(401, "Invalid or expired refresh token")
    presented_hash = _hash_refresh(body.refresh_token)
    if (
        not user
        or not user.get("is_active")
        or user.get("refresh_token_hash") != presented_hash
        or claims.get("tv", 0) != user.get("token_version", 0)
    ):
        raise HTTPException(401, "Refresh token revoked")
    employee_id = claims.get("employee_id")
    role = Role(user["role"]).value
    version = user.get("token_version", 0)
    access, _ = create_token(user["_id"], role, user.get("company_id"), employee_id, token_version=version)
    refresh, _ = create_token(user["_id"], role, user.get("company_id"), employee_id, "refresh", version)
    # Compare-and-swap so two concurrent refreshes with the same token can't both win.
    rotated = await db.users.update_one(
        {"_id": user["_id"], "refresh_token_hash": presented_hash},
        {"$set": {"refresh_token_hash": _hash_refresh(refresh)}},
    )
    if rotated.modified_count != 1:
        raise HTTPException(401, "Refresh token revoked")
    return {"accessToken": access, "refreshToken": refresh, "expiresIn": settings.jwt_access_minutes * 60}


@router.post("/logout", status_code=204)
async def logout(body: RefreshRequest, db: AsyncDatabase = Depends(get_db)):
    try:
        claims = decode_token(body.refresh_token, "refresh")
        await db.users.update_one(
            {"_id": str(UUID(claims["sub"])), "refresh_token_hash": _hash_refresh(body.refresh_token)},
            {"$set": {"refresh_token_hash": None}},
        )
    except Exception:
        pass
    return Response(status_code=204)


# ── Admin console ────────────────────────────────────────────────────────────


@admin_router.post("/login")
async def admin_login(body: AdminLogin, request: Request, db: AsyncDatabase = Depends(get_db)):
    email = body.email.lower()
    ip = client_ip(request)
    await enforce(f"login-ip:{ip}", settings.login_rate_per_minute * 4, 60, "Too many sign-in attempts; wait a minute")
    await enforce(f"login:{email}", settings.login_rate_per_minute, 60, "Too many sign-in attempts; wait a minute")
    # Per (email, network) so a stranger can't lock the real admin out; the per-email
    # ceiling still stops a distributed guessing run.
    lock_key = f"{email}|{ip}"
    await check_login_lockout(lock_key)
    await check_login_lockout(email, settings.login_lockout_failures * EMAIL_LOCKOUT_FACTOR)
    user = await db.users.find_one({"email": email})
    password_ok = await verify_password_async(body.password, user.get("password_hash") if user else None)
    if (
        not user
        or user["role"] not in (Role.company_admin.value, Role.super_admin.value)
        or not password_ok
        or not user.get("is_active")
    ):
        await record_login_failure(lock_key)
        await record_login_failure(email)
        raise HTTPException(401, "Invalid email or password")
    await clear_login_failures(lock_key)
    billing_required = False
    if user.get("company_id"):
        try:
            await require_active_subscription(db, user["company_id"])
        except HTTPException as exc:
            # With online payments on, let an expired (not suspended) company sign in to renew.
            company = await db.companies.find_one({"_id": user["company_id"]}, {"status": 1})
            renewable = (
                settings.payments_configured
                and exc.detail == "Subscription expired"
                and company is not None
                and company["status"] != CompanyStatus.suspended.value
            )
            if not renewable:
                raise
            billing_required = True
    return _admin_session(user, await issue_tokens(db, user), billing_required)


@admin_router.post("/password")
async def change_password(
    body: ChangePassword,
    principal: Principal = Depends(admin_principal),
    db: AsyncDatabase = Depends(get_db),
):
    await enforce(f"pwchange:{principal.user.id}", 5, 300, "Too many attempts; try again in a few minutes")
    user = await db.users.find_one({"_id": principal.user.id})
    if not user or not await verify_password_async(body.current_password, user.get("password_hash")):
        raise HTTPException(400, "Current password is incorrect")
    if body.current_password == body.new_password:
        raise HTTPException(400, "New password must be different from the current one")
    user = await db.users.find_one_and_update(
        {"_id": user["_id"]},
        {
            "$set": {"password_hash": await hash_password_async(body.new_password), "updated_at": utcnow()},
            "$inc": {"token_version": 1},
        },
        return_document=ReturnDocument.AFTER,
    )
    # Every other session (and its access tokens) stops working; the caller gets fresh tokens.
    await invalidate_user(user["_id"])
    access, refresh, expires = await issue_tokens(db, user)
    await record_audit(db, principal, "admin.password_changed", "user", user["_id"], "Changed own password")
    return {"accessToken": access, "refreshToken": refresh, "expiresIn": expires}


# ── Self-service firm registration ──────────────────────────────────────────


def _require_signup_enabled() -> None:
    if not settings.allow_self_signup:
        raise HTTPException(403, "New firm registration is closed. Contact support to get an account.")


async def _signup_plan(db: AsyncDatabase) -> dict:
    plan = await db.subscription_plans.find_one({"code": settings.signup_plan_code})
    if plan is None:
        plan = await db.subscription_plans.find_one({}, sort=[("monthly_price_inr", 1)])
    if plan is None:
        logger.error("Self sign-up failed: no subscription plans exist (run `python -m app.seed`)")
        raise HTTPException(503, "Registration is temporarily unavailable. Please try again later.")
    return plan


async def _create_firm(db: AsyncDatabase, registration: dict) -> dict:
    plan = await _signup_plan(db)
    seats = settings.signup_trial_seats
    if plan.get("max_employees") is not None:
        seats = min(seats, plan["max_employees"])
    company = company_doc(
        registration["company_name"],
        industry=registration.get("industry"),
        legal_name=registration.get("legal_name"),
        gstin=registration.get("gstin"),
        status=CompanyStatus.active,
    )
    if registration.get("gstin_check"):
        company["gstin_check"] = registration["gstin_check"]
    try:
        user = await create_company_with_admin(
            db,
            company,
            admin_email=registration["admin_email"],
            password_hash=registration["password_hash"],
            admin_name=registration.get("admin_name"),
            admin_mobile=registration.get("mobile"),
            plan_code=plan["code"],
            seats=seats,
            days=settings.signup_trial_days,
            with_defaults=True,
        )
    except EmailTaken:
        raise HTTPException(409, EMAIL_TAKEN)
    except GstinTaken:
        raise HTTPException(409, GSTIN_TAKEN)
    logger.info("Firm registered: %s (%s)", company["name"], company["_id"])
    return user


@admin_router.get("/register/options")
async def registration_options():
    """Public: lets the sign-up screens show the right form before the user fills it in."""
    verify = settings.signup_verify_email
    return {
        "enabled": settings.allow_self_signup,
        "verificationRequired": verify,
        "available": settings.allow_self_signup and (settings.email_configured or not verify),
        "passwordReset": settings.email_configured,
        "trialDays": settings.signup_trial_days,
        "trialSeats": settings.signup_trial_seats,
    }


@admin_router.post("/register", status_code=201)
async def register_firm(body: FirmRegistration, request: Request, db: AsyncDatabase = Depends(get_db)):
    """Step 1: validate, then email a 6-digit code (or create directly when
    SIGNUP_VERIFY_EMAIL=false)."""
    _require_signup_enabled()
    await enforce(f"signup-ip:{client_ip(request)}", 10, 3600, "Too many registrations from this network; try again later")
    email = body.admin_email
    if await db.users.find_one({"email": email}, {"_id": 1}):
        raise HTTPException(409, EMAIL_TAKEN)
    if body.gstin and await db.companies.find_one({"gstin": body.gstin}, {"_id": 1}):
        raise HTTPException(409, GSTIN_TAKEN)
    portal = await verify_gstin(body.gstin) if body.gstin else None
    if portal and (reason := blocking_reason(portal)):
        raise HTTPException(400, f"GSTIN {body.gstin}: {reason}")
    registration = {
        "company_name": body.company_name,
        "legal_name": body.legal_name or (portal or {}).get("legalName"),
        "gstin_check": check_doc(portal) if portal and portal["liveCheck"] else None,
        "gstin": body.gstin,
        "industry": body.industry,
        "admin_name": body.admin_name,
        "admin_email": email,
        "mobile": body.mobile,
        "password_hash": await hash_password_async(body.admin_password),
    }
    if not settings.signup_verify_email:
        user = await _create_firm(db, registration)
        return {"verificationRequired": False, **_admin_session(user, await issue_tokens(db, user))}

    if not settings.email_configured:
        logger.error(
            "Firm registration needs an email provider: set EMAIL_PROVIDER=brevo with BREVO_API_KEY "
            "and EMAIL_FROM, or SIGNUP_VERIFY_EMAIL=false"
        )
        raise EmailUnavailable("Registration is temporarily unavailable because verification emails cannot be sent. Please contact support.")
    now = utcnow()
    await db.signup_requests.update_one(
        {"email": email},
        {"$set": {"payload": registration, "expires_at": now + timedelta(hours=SIGNUP_REQUEST_HOURS), "updated_at": now}},
        upsert=True,
    )
    await create_challenge(db, email, purpose=OtpPurpose.signup, channel="email")
    return {
        "verificationRequired": True,
        "destination": mask_email(email),
        "expiresInMinutes": settings.otp_ttl_minutes,
    }


@admin_router.post("/register/resend")
async def resend_registration_code(body: EmailOnly, request: Request, db: AsyncDatabase = Depends(get_db)):
    _require_signup_enabled()
    await enforce(f"signup-resend-ip:{client_ip(request)}", 10, 3600, "Too many requests; try again later")
    pending = await db.signup_requests.find_one({"email": body.email})
    if not pending or as_utc(pending["expires_at"]) < utcnow():
        raise HTTPException(404, "No pending registration for this email. Please register again.")
    await create_challenge(db, body.email, purpose=OtpPurpose.signup, channel="email")
    return {"ok": True, "destination": mask_email(body.email), "expiresInMinutes": settings.otp_ttl_minutes}


@admin_router.post("/register/verify", status_code=201)
async def verify_registration(body: RegistrationVerify, request: Request, db: AsyncDatabase = Depends(get_db)):
    """Step 2: the emailed code creates the firm (active, with a free trial) and signs the admin in."""
    _require_signup_enabled()
    await enforce(f"signup-verify-ip:{client_ip(request)}", 30, 3600, "Too many attempts; try again later")
    pending = await db.signup_requests.find_one({"email": body.email})
    if not pending or as_utc(pending["expires_at"]) < utcnow():
        raise HTTPException(400, "This registration has expired. Please register again.")
    # Binds the code to the details the person entering it submitted, so someone who
    # re-registers the same email with their own password can't ride the owner's code.
    if not await verify_password_async(body.password, pending["payload"].get("password_hash")):
        raise HTTPException(400, "The details for this registration changed. Please register again.")
    if not await verify_challenge(db, body.email, body.code, purpose=OtpPurpose.signup):
        raise HTTPException(400, "Invalid or expired code")
    user = await _create_firm(db, pending["payload"])
    await db.signup_requests.delete_one({"_id": pending["_id"]})
    return _admin_session(user, await issue_tokens(db, user))


# ── Password reset ───────────────────────────────────────────────────────────


@admin_router.post("/password/forgot")
async def forgot_password(body: EmailOnly, request: Request, db: AsyncDatabase = Depends(get_db)):
    """Always answers the same way so the endpoint can't be used to discover accounts."""
    await enforce(f"pwforgot-ip:{client_ip(request)}", 10, 3600, "Too many requests; try again later")
    if not settings.email_configured:
        raise EmailUnavailable()
    user = await db.users.find_one({"email": body.email, "is_active": True}, {"role": 1})
    if user and user["role"] in (Role.company_admin.value, Role.super_admin.value):
        try:
            await create_challenge(db, body.email, purpose=OtpPurpose.password_reset, channel="email")
        except HTTPException as exc:
            if exc.status_code != 429:
                raise
    return {"ok": True, "destination": mask_email(body.email), "expiresInMinutes": settings.otp_ttl_minutes}


@admin_router.post("/password/reset")
async def reset_password(body: PasswordReset, request: Request, db: AsyncDatabase = Depends(get_db)):
    await enforce(f"pwreset-ip:{client_ip(request)}", 20, 3600, "Too many attempts; try again later")
    if not await verify_challenge(db, body.email, body.code, purpose=OtpPurpose.password_reset):
        raise HTTPException(400, "Invalid or expired code")
    user = await db.users.find_one({"email": body.email, "is_active": True})
    if not user:
        raise HTTPException(400, "Invalid or expired code")
    await db.users.update_one(
        {"_id": user["_id"]},
        {"$set": {
            "password_hash": await hash_password_async(body.new_password),
            "refresh_token_hash": None,
            "email_verified": True,
            "updated_at": utcnow(),
        }, "$inc": {"token_version": 1}},
    )
    await invalidate_user(user["_id"])
    await clear_login_failures(body.email)
    return {"ok": True}
