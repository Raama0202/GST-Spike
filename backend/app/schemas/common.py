import json
from datetime import date, datetime
from decimal import Decimal
from typing import Any, Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator

from app.services import gstin as gstin_service
from app.services.phone import canonical_mobile

MAX_INVOICE_DATA_CHARS = 20_000


class ORMModel(BaseModel):
    model_config = ConfigDict(from_attributes=True, populate_by_name=True)


class OTPRequest(BaseModel):
    mobile: str = Field(max_length=25)

    @field_validator("mobile")
    @classmethod
    def _canonical(cls, value: str) -> str:
        return canonical_mobile(value)


class OTPVerify(OTPRequest):
    otp: str = Field(pattern=r"^[0-9]{6}$")


class RefreshRequest(BaseModel):
    refresh_token: str = Field(alias="refreshToken")


class AdminLogin(BaseModel):
    email: EmailStr
    password: str


class ChangePassword(BaseModel):
    current_password: str = Field(alias="currentPassword")
    new_password: str = Field(min_length=10, max_length=128, alias="newPassword")


class BillingOrderCreate(BaseModel):
    plan_code: str = Field(alias="planCode")
    seats: int = Field(gt=0, le=10000)
    months: int = Field(default=1, ge=1, le=36)


class BillingVerify(BaseModel):
    razorpay_order_id: str = Field(alias="razorpayOrderId")
    razorpay_payment_id: str = Field(alias="razorpayPaymentId")
    razorpay_signature: str = Field(alias="razorpaySignature")


class EmployeeProfile(ORMModel):
    id: UUID
    name: str
    mobile: str
    employee_code: str = Field(alias="employeeCode")
    company_id: UUID = Field(alias="companyId")
    company_name: str = Field(alias="companyName")
    branch_id: UUID | None = Field(alias="branchId")
    branch_name: str | None = Field(alias="branchName")


class TokenResponse(BaseModel):
    access_token: str = Field(alias="accessToken")
    refresh_token: str = Field(alias="refreshToken")
    expires_in: int = Field(alias="expiresIn")
    employee: EmployeeProfile | None = None


class DuplicateCheck(BaseModel):
    invoice_number: str = Field(alias="invoiceNumber")
    gstin: str | None = None
    invoice_date: date | None = Field(default=None, alias="invoiceDate")
    net_amount: Decimal | None = Field(default=None, alias="netAmount")


def _bounded_dict(value: dict[str, Any]) -> dict[str, Any]:
    if len(json.dumps(value, default=str)) > MAX_INVOICE_DATA_CHARS:
        raise ValueError("invoice data is too large")
    return value


class InvoicePayload(BaseModel):
    branch_id: UUID | None = Field(default=None, alias="branchId")
    category_id: UUID | None = Field(default=None, alias="categoryId")
    device_id: str | None = Field(default=None, max_length=200, alias="deviceId")
    latitude: Decimal | None = Field(default=None, ge=-90, le=90)
    longitude: Decimal | None = Field(default=None, ge=-180, le=180)
    ocr_confidence: Decimal | None = Field(default=None, alias="ocrConfidence")
    ocr_data: dict[str, Any] = Field(default_factory=dict, alias="ocrData")
    edited_data: dict[str, Any] = Field(default_factory=dict, alias="editedData")
    duplicate_override: bool = Field(default=False, alias="duplicateOverride")

    _bounded = field_validator("ocr_data", "edited_data")(_bounded_dict)


class InvoiceResubmit(BaseModel):
    edited_data: dict[str, Any] = Field(alias="editedData")
    category_id: UUID | None = Field(default=None, alias="categoryId")
    note: str | None = Field(default=None, max_length=500)

    _bounded = field_validator("edited_data")(_bounded_dict)


class InvoiceEdit(BaseModel):
    edited_data: dict[str, Any] | None = Field(default=None, alias="editedData")
    category_id: UUID | None = Field(default=None, alias="categoryId")

    _bounded = field_validator("edited_data")(_bounded_dict)


class NotificationRead(BaseModel):
    ids: list[UUID]


class DeviceRegister(BaseModel):
    device_id: str = Field(min_length=1, max_length=200, alias="deviceId")
    platform: Literal["android", "ios"]
    app_version: str = Field(max_length=50, alias="appVersion")
    fcm_token: str | None = Field(default=None, max_length=4096, alias="fcmToken")


def _normalize_mobile(value: str | None) -> str | None:
    return None if value is None else canonical_mobile(value)


def _strip_required(value: str | None) -> str | None:
    if value is None:
        return None
    value = value.strip()
    if not value:
        raise ValueError("must not be blank")
    return value


def _normalize_gstin(value: str | None) -> str | None:
    if value is None:
        return None
    cleaned = gstin_service.compact(value)
    if not cleaned:
        return None
    if not gstin_service.is_valid(cleaned):
        raise ValueError("Enter a valid 15-character GSTIN (check the last character)")
    return cleaned


def _normalize_gstin_list(values: list[str] | None) -> list[str] | None:
    if values is None:
        return None
    cleaned = [_normalize_gstin(value) for value in values]
    return list(dict.fromkeys(value for value in cleaned if value))


def _clean_aliases(values: list[str] | None) -> list[str] | None:
    if values is None:
        return None
    cleaned = [" ".join(value.split())[:200] for value in values if value and value.strip()]
    return list(dict.fromkeys(cleaned))[:20]


def _lower_email(value: str | None) -> str | None:
    return value.strip().lower() if value else None


class EmployeeCreate(BaseModel):
    name: str = Field(max_length=150)
    mobile: str
    email: EmailStr | None = None
    employee_code: str = Field(max_length=50, alias="employeeCode")
    branch_id: UUID | None = Field(default=None, alias="branchId")
    is_active: bool = Field(default=True, alias="isActive")

    _mobile = field_validator("mobile")(_normalize_mobile)
    _required = field_validator("name", "employee_code")(_strip_required)
    _email = field_validator("email")(_lower_email)


class EmployeeUpdate(BaseModel):
    name: str | None = Field(default=None, max_length=150)
    mobile: str | None = None
    email: EmailStr | None = None
    employee_code: str | None = Field(default=None, max_length=50, alias="employeeCode")
    branch_id: UUID | None = Field(default=None, alias="branchId")
    is_active: bool | None = Field(default=None, alias="isActive")

    _mobile = field_validator("mobile")(_normalize_mobile)
    _required = field_validator("name", "employee_code")(_strip_required)
    _email = field_validator("email")(_lower_email)


class NamedResource(BaseModel):
    name: str = Field(max_length=150)
    code: str | None = Field(default=None, max_length=30)
    parent_id: UUID | None = Field(default=None, alias="parentId")
    sort_order: int = Field(default=0, alias="sortOrder")
    is_active: bool = Field(default=True, alias="isActive")

    _required = field_validator("name")(_strip_required)


class CompanySettings(BaseModel):
    name: str | None = Field(default=None, max_length=200)
    industry: str | None = Field(default=None, max_length=120)
    logo_url: str | None = Field(default=None, max_length=500, alias="logoUrl")
    primary_color_hex: str | None = Field(default=None, max_length=8, alias="primaryColorHex")
    requires_gps: bool | None = Field(default=None, alias="requiresGps")
    duplicate_check_enabled: bool | None = Field(default=None, alias="duplicateCheckEnabled")
    min_ocr_confidence_warn: Decimal | None = Field(default=None, ge=0, le=1, alias="minOcrConfidenceWarn")
    features: dict[str, Any] | None = None
    legal_name: str | None = Field(default=None, max_length=200, alias="legalName")
    gstin: str | None = None
    additional_gstins: list[str] | None = Field(default=None, max_length=50, alias="additionalGstins")
    name_aliases: list[str] | None = Field(default=None, max_length=20, alias="nameAliases")

    _required = field_validator("name")(_strip_required)
    _gstin = field_validator("gstin")(_normalize_gstin)
    _gstins = field_validator("additional_gstins")(_normalize_gstin_list)
    _aliases = field_validator("name_aliases")(_clean_aliases)


class Announcement(BaseModel):
    title: str = Field(min_length=1, max_length=200, pattern=r"\S")
    body: str = Field(min_length=1, max_length=4000, pattern=r"\S")


class InvoiceDecision(BaseModel):
    remarks: str | None = Field(default=None, max_length=1000)


class BulkDecision(BaseModel):
    ids: list[UUID] = Field(min_length=1, max_length=100)
    status: Literal["approved", "rejected", "returned"]
    remarks: str | None = Field(default=None, max_length=1000)


class PlanInput(BaseModel):
    code: str = Field(min_length=2, max_length=40, pattern=r"^[a-z0-9][a-z0-9_-]*$")
    name: str = Field(min_length=1, max_length=100)
    monthly_price_inr: Decimal = Field(ge=0, le=10_000_000, alias="monthlyPriceInr")
    max_employees: int | None = Field(default=None, ge=1, le=100_000, alias="maxEmployees")
    features: dict[str, Any] = Field(default_factory=dict)

    _required = field_validator("name")(_strip_required)

    @field_validator("code", mode="before")
    @classmethod
    def _lower_code(cls, value: str) -> str:
        return value.strip().lower() if isinstance(value, str) else value


class CompanyCreate(BaseModel):
    name: str = Field(max_length=200)
    industry: str | None = None
    legal_name: str | None = Field(default=None, max_length=200, alias="legalName")
    gstin: str | None = None
    admin_email: EmailStr = Field(alias="adminEmail")
    admin_password: str = Field(min_length=10, max_length=128, alias="adminPassword")
    plan_code: str = Field(alias="planCode")
    seats: int = Field(gt=0, le=100_000)
    subscription_days: int = Field(default=30, gt=0, le=3650, alias="subscriptionDays")

    _required = field_validator("name")(_strip_required)
    _gstin = field_validator("gstin")(_normalize_gstin)
    _email = field_validator("admin_email")(_lower_email)


class FirmRegistration(BaseModel):
    """Self-service sign-up: a new firm and its first admin."""
    company_name: str = Field(min_length=2, max_length=200, alias="companyName")
    legal_name: str | None = Field(default=None, max_length=200, alias="legalName")
    gstin: str | None = None
    industry: str | None = Field(default=None, max_length=120)
    admin_name: str = Field(min_length=2, max_length=150, alias="adminName")
    admin_email: EmailStr = Field(alias="adminEmail")
    admin_password: str = Field(min_length=10, max_length=128, alias="adminPassword")
    mobile: str | None = None

    _required = field_validator("company_name", "admin_name")(_strip_required)
    _gstin = field_validator("gstin")(_normalize_gstin)
    _mobile = field_validator("mobile")(_normalize_mobile)
    _email = field_validator("admin_email")(_lower_email)


class EmailOnly(BaseModel):
    email: EmailStr

    _email = field_validator("email")(_lower_email)


class EmailCode(EmailOnly):
    code: str = Field(pattern=r"^[0-9]{6}$")


class RegistrationVerify(EmailCode):
    password: str = Field(min_length=1, max_length=128)


class PasswordReset(EmailCode):
    new_password: str = Field(min_length=10, max_length=128, alias="newPassword")


class ActivationRequest(BaseModel):
    activation_code: str = Field(alias="activationCode")


class ExtendSubscription(BaseModel):
    days: int = Field(gt=0, le=3650)


class SubscriptionChange(BaseModel):
    plan_code: str = Field(alias="planCode")
    seats: int = Field(gt=0, le=100_000)
    ends_at: datetime | None = Field(default=None, alias="endsAt")


class CompanyUpdate(BaseModel):
    name: str | None = Field(default=None, max_length=200)
    legal_name: str | None = Field(default=None, max_length=200, alias="legalName")
    gstin: str | None = None
    industry: str | None = Field(default=None, max_length=120)

    _required = field_validator("name")(_strip_required)
    _gstin = field_validator("gstin")(_normalize_gstin)


class CompanyDelete(BaseModel):
    password: str = Field(min_length=1, max_length=128)
    confirm_name: str = Field(min_length=1, max_length=200, alias="confirmName")


class SuperCompanyDelete(BaseModel):
    confirm_name: str = Field(min_length=1, max_length=200, alias="confirmName")


class InvoiceFilter(BaseModel):
    status: str | None = None
    employee_id: UUID | None = None
    branch_id: UUID | None = None
    date_from: datetime | None = None
    date_to: datetime | None = None
