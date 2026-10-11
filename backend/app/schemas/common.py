import re
from datetime import date, datetime
from decimal import Decimal
from typing import Any, Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator


class ORMModel(BaseModel):
    model_config = ConfigDict(from_attributes=True, populate_by_name=True)


class OTPRequest(BaseModel):
    mobile: str = Field(pattern=r"^\+?[0-9]{10,15}$")


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


class InvoicePayload(BaseModel):
    branch_id: UUID | None = Field(default=None, alias="branchId")
    category_id: UUID | None = Field(default=None, alias="categoryId")
    device_id: str | None = Field(default=None, alias="deviceId")
    latitude: Decimal | None = None
    longitude: Decimal | None = None
    ocr_confidence: Decimal | None = Field(default=None, alias="ocrConfidence")
    ocr_data: dict[str, Any] = Field(default_factory=dict, alias="ocrData")
    edited_data: dict[str, Any] = Field(default_factory=dict, alias="editedData")
    duplicate_override: bool = Field(default=False, alias="duplicateOverride")


class NotificationRead(BaseModel):
    ids: list[UUID]


class DeviceRegister(BaseModel):
    device_id: str = Field(alias="deviceId")
    platform: Literal["android", "ios"]
    app_version: str = Field(alias="appVersion")
    fcm_token: str | None = Field(default=None, alias="fcmToken")


_MOBILE_SEPARATORS = re.compile(r"[\s\-().]")
_MOBILE = re.compile(r"^\+?[0-9]{10,15}$")


def _normalize_mobile(value: str | None) -> str | None:
    if value is None:
        return None
    cleaned = _MOBILE_SEPARATORS.sub("", value)
    if not _MOBILE.fullmatch(cleaned):
        raise ValueError("Enter a valid mobile number (10-15 digits, optional leading +)")
    return cleaned


def _strip_required(value: str | None) -> str | None:
    if value is None:
        return None
    value = value.strip()
    if not value:
        raise ValueError("must not be blank")
    return value


class EmployeeCreate(BaseModel):
    name: str = Field(max_length=150)
    mobile: str
    employee_code: str = Field(max_length=50, alias="employeeCode")
    branch_id: UUID | None = Field(default=None, alias="branchId")
    is_active: bool = Field(default=True, alias="isActive")

    _mobile = field_validator("mobile")(_normalize_mobile)
    _required = field_validator("name", "employee_code")(_strip_required)


class EmployeeUpdate(BaseModel):
    name: str | None = Field(default=None, max_length=150)
    mobile: str | None = None
    employee_code: str | None = Field(default=None, max_length=50, alias="employeeCode")
    branch_id: UUID | None = Field(default=None, alias="branchId")
    is_active: bool | None = Field(default=None, alias="isActive")

    _mobile = field_validator("mobile")(_normalize_mobile)
    _required = field_validator("name", "employee_code")(_strip_required)


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

    _required = field_validator("name")(_strip_required)


class Announcement(BaseModel):
    title: str = Field(min_length=1, max_length=200, pattern=r"\S")
    body: str = Field(min_length=1, pattern=r"\S")


class InvoiceDecision(BaseModel):
    remarks: str | None = None


class PlanInput(BaseModel):
    code: str
    name: str
    monthly_price_inr: Decimal = Field(alias="monthlyPriceInr")
    max_employees: int | None = Field(alias="maxEmployees")
    features: dict[str, Any] = Field(default_factory=dict)


class CompanyCreate(BaseModel):
    name: str
    industry: str | None = None
    admin_email: EmailStr = Field(alias="adminEmail")
    admin_password: str = Field(min_length=8, alias="adminPassword")
    plan_code: str = Field(alias="planCode")
    seats: int = Field(gt=0)
    subscription_days: int = Field(default=30, gt=0, alias="subscriptionDays")


class ActivationRequest(BaseModel):
    activation_code: str = Field(alias="activationCode")


class ExtendSubscription(BaseModel):
    days: int = Field(gt=0)


class InvoiceFilter(BaseModel):
    status: str | None = None
    employee_id: UUID | None = None
    branch_id: UUID | None = None
    date_from: datetime | None = None
    date_to: datetime | None = None
