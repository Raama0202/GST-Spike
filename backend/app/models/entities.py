import enum
from datetime import date, datetime, timezone
from decimal import Decimal
from uuid import UUID

from sqlalchemy import (
    JSON,
    BigInteger,
    Boolean,
    Date,
    DateTime,
    Enum,
    ForeignKey,
    Index,
    Numeric,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, TimestampMixin, UUIDMixin


class Role(str, enum.Enum):
    super_admin = "super_admin"
    company_admin = "company_admin"
    employee = "employee"


class CompanyStatus(str, enum.Enum):
    active = "active"
    pending = "pending"
    suspended = "suspended"


class SubscriptionStatus(str, enum.Enum):
    active = "active"
    expired = "expired"
    cancelled = "cancelled"


class ApprovalStatus(str, enum.Enum):
    pending = "pending"
    approved = "approved"
    rejected = "rejected"
    returned = "returned"


class GstrReturnType(str, enum.Enum):
    gstr_2a = "2A"
    gstr_2b = "2B"


class GstrImportSource(str, enum.Enum):
    excel = "excel"
    gsp = "gsp"


class GstrImportStatus(str, enum.Enum):
    processing = "processing"
    ready = "ready"
    failed = "failed"


class ItcMatchStatus(str, enum.Enum):
    matched = "matched"
    partial = "partial"
    missing_in_2b = "missing_in_2b"
    missing_in_books = "missing_in_books"
    mismatch = "mismatch"


class ReminderChannel(str, enum.Enum):
    whatsapp = "whatsapp"
    email = "email"
    sms_intent = "sms_intent"
    manual = "manual"


class ReminderStatus(str, enum.Enum):
    sent_link = "sent_link"
    manual_followup = "manual_followup"
    resolved = "resolved"


class PaymentStatus(str, enum.Enum):
    created = "created"
    authorized = "authorized"
    paid = "paid"
    failed = "failed"


class Company(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "companies"
    name: Mapped[str] = mapped_column(String(200))
    industry: Mapped[str | None] = mapped_column(String(120))
    logo_url: Mapped[str | None] = mapped_column(String(500))
    primary_color_hex: Mapped[str] = mapped_column(String(8), default="0B5FFF")
    activation_code: Mapped[str] = mapped_column(String(32), unique=True, index=True)
    status: Mapped[CompanyStatus] = mapped_column(Enum(CompanyStatus), default=CompanyStatus.pending)
    requires_gps: Mapped[bool] = mapped_column(Boolean, default=False)
    duplicate_check_enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    min_ocr_confidence_warn: Mapped[Decimal] = mapped_column(Numeric(4, 3), default=Decimal("0.55"))
    features_json: Mapped[dict] = mapped_column(JSON, default=dict)


class User(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "users"
    company_id: Mapped[UUID | None] = mapped_column(ForeignKey("companies.id"), index=True)
    email: Mapped[str | None] = mapped_column(String(320), unique=True, index=True)
    password_hash: Mapped[str | None] = mapped_column(String(255))
    role: Mapped[Role] = mapped_column(Enum(Role), index=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    refresh_token_hash: Mapped[str | None] = mapped_column(String(64))
    employee: Mapped["Employee | None"] = relationship(back_populates="user", uselist=False)


class OTPChallenge(Base, UUIDMixin):
    __tablename__ = "otp_challenges"
    __table_args__ = (Index("ix_otp_mobile_created", "mobile", "created_at"),)
    mobile: Mapped[str] = mapped_column(String(20), index=True)
    code_hash: Mapped[str] = mapped_column(String(64))
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    consumed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    attempts: Mapped[int] = mapped_column(default=0)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )


class SubscriptionPlan(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "subscription_plans"
    code: Mapped[str] = mapped_column(String(50), unique=True)
    name: Mapped[str] = mapped_column(String(100))
    monthly_price_inr: Mapped[Decimal] = mapped_column(Numeric(12, 2))
    max_employees: Mapped[int | None]
    features_json: Mapped[dict] = mapped_column(JSON, default=dict)


class Subscription(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "subscriptions"
    __table_args__ = (Index("ix_subscriptions_company_status_ends", "company_id", "status", "ends_at"),)
    company_id: Mapped[UUID] = mapped_column(ForeignKey("companies.id"), index=True)
    plan_code: Mapped[str] = mapped_column(ForeignKey("subscription_plans.code"))
    seats: Mapped[int]
    starts_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    ends_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    status: Mapped[SubscriptionStatus] = mapped_column(Enum(SubscriptionStatus), default=SubscriptionStatus.active)


class Branch(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "branches"
    __table_args__ = (UniqueConstraint("company_id", "code", name="uq_branches_company_code"),)
    company_id: Mapped[UUID] = mapped_column(ForeignKey("companies.id"), index=True)
    name: Mapped[str] = mapped_column(String(150))
    code: Mapped[str] = mapped_column(String(30))
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)


class ExpenseCategory(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "expense_categories"
    __table_args__ = (UniqueConstraint("company_id", "name", name="uq_expense_categories_company_name"),)
    company_id: Mapped[UUID] = mapped_column(ForeignKey("companies.id"), index=True)
    name: Mapped[str] = mapped_column(String(150))
    parent_id: Mapped[UUID | None] = mapped_column(ForeignKey("expense_categories.id"))
    sort_order: Mapped[int] = mapped_column(default=0)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)


class Employee(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "employees"
    __table_args__ = (
        UniqueConstraint("company_id", "mobile", name="uq_employees_company_mobile"),
        UniqueConstraint("company_id", "employee_code", name="uq_employees_company_code"),
        Index("ix_employees_company_active", "company_id", "is_active"),
    )
    company_id: Mapped[UUID] = mapped_column(ForeignKey("companies.id"), index=True)
    user_id: Mapped[UUID] = mapped_column(ForeignKey("users.id"), unique=True)
    branch_id: Mapped[UUID | None] = mapped_column(ForeignKey("branches.id"))
    name: Mapped[str] = mapped_column(String(150))
    employee_code: Mapped[str] = mapped_column(String(50))
    mobile: Mapped[str] = mapped_column(String(20), index=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    user: Mapped[User] = relationship(back_populates="employee")
    branch: Mapped[Branch | None] = relationship()


class Invoice(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "invoices"
    __table_args__ = (
        UniqueConstraint("company_id", "idempotency_key"),
        Index("ix_invoice_duplicate", "company_id", "invoice_number", "gstin", "invoice_date"),
        Index("ix_invoices_company_uploaded", "company_id", "uploaded_at"),
        Index("ix_invoices_company_status_uploaded", "company_id", "approval_status", "uploaded_at"),
        Index("ix_invoices_employee_updated", "employee_id", "updated_at"),
    )
    company_id: Mapped[UUID] = mapped_column(ForeignKey("companies.id"), index=True)
    employee_id: Mapped[UUID] = mapped_column(ForeignKey("employees.id"), index=True)
    branch_id: Mapped[UUID | None] = mapped_column(ForeignKey("branches.id"))
    category_id: Mapped[UUID | None] = mapped_column(ForeignKey("expense_categories.id"))
    idempotency_key: Mapped[str] = mapped_column(String(100))
    invoice_number: Mapped[str | None] = mapped_column(String(120), index=True)
    gstin: Mapped[str | None] = mapped_column(String(20), index=True)
    vendor_name: Mapped[str | None] = mapped_column(String(200))
    invoice_date: Mapped[date | None] = mapped_column(Date)
    taxable_amount: Mapped[Decimal | None] = mapped_column(Numeric(14, 2))
    cgst_amount: Mapped[Decimal | None] = mapped_column(Numeric(14, 2))
    sgst_amount: Mapped[Decimal | None] = mapped_column(Numeric(14, 2))
    igst_amount: Mapped[Decimal | None] = mapped_column(Numeric(14, 2))
    total_tax: Mapped[Decimal | None] = mapped_column(Numeric(14, 2))
    net_amount: Mapped[Decimal | None] = mapped_column(Numeric(14, 2))
    currency: Mapped[str] = mapped_column(String(3), default="INR")
    ocr_confidence: Mapped[Decimal | None] = mapped_column(Numeric(5, 4))
    ocr_data: Mapped[dict] = mapped_column(JSON, default=dict)
    edited_data: Mapped[dict] = mapped_column(JSON, default=dict)
    original_image_path: Mapped[str]
    compressed_image_path: Mapped[str]
    thumbnail_image_path: Mapped[str]
    approval_status: Mapped[ApprovalStatus] = mapped_column(Enum(ApprovalStatus), default=ApprovalStatus.pending, index=True)
    admin_remarks: Mapped[str | None] = mapped_column(Text)
    latitude: Mapped[Decimal | None] = mapped_column(Numeric(10, 7))
    longitude: Mapped[Decimal | None] = mapped_column(Numeric(10, 7))
    device_id: Mapped[str | None] = mapped_column(String(100))
    duplicate_override: Mapped[bool] = mapped_column(Boolean, default=False)
    uploaded_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), index=True
    )
    reviewed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    reviewed_by: Mapped[UUID | None] = mapped_column(ForeignKey("users.id"))


class Notification(Base, UUIDMixin):
    __tablename__ = "notifications"
    __table_args__ = (
        Index("ix_notifications_employee_created", "employee_id", "created_at"),
        Index("ix_notifications_company_type_created", "company_id", "type", "created_at"),
    )
    company_id: Mapped[UUID] = mapped_column(ForeignKey("companies.id"), index=True)
    employee_id: Mapped[UUID] = mapped_column(ForeignKey("employees.id"), index=True)
    type: Mapped[str] = mapped_column(String(40))
    title: Mapped[str] = mapped_column(String(200))
    body: Mapped[str] = mapped_column(Text)
    invoice_id: Mapped[UUID | None] = mapped_column(ForeignKey("invoices.id"))
    read: Mapped[bool] = mapped_column(Boolean, default=False)
    sent_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), index=True
    )


class Device(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "devices"
    __table_args__ = (UniqueConstraint("company_id", "device_id"),)
    company_id: Mapped[UUID] = mapped_column(ForeignKey("companies.id"), index=True)
    employee_id: Mapped[UUID] = mapped_column(ForeignKey("employees.id"), index=True)
    device_id: Mapped[str] = mapped_column(String(100))
    platform: Mapped[str] = mapped_column(String(30))
    app_version: Mapped[str] = mapped_column(String(30))
    fcm_token: Mapped[str | None] = mapped_column(String(500))


class AuditLog(Base, UUIDMixin):
    __tablename__ = "audit_logs"
    company_id: Mapped[UUID | None] = mapped_column(ForeignKey("companies.id"), index=True)
    actor_user_id: Mapped[UUID | None] = mapped_column(ForeignKey("users.id"))
    action: Mapped[str] = mapped_column(String(100))
    entity_type: Mapped[str] = mapped_column(String(100))
    entity_id: Mapped[str | None] = mapped_column(String(100))
    details_json: Mapped[dict] = mapped_column(JSON, default=dict)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )


class GstrImport(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "gstr_imports"
    company_id: Mapped[UUID] = mapped_column(ForeignKey("companies.id"), index=True)
    period: Mapped[str] = mapped_column(String(7), index=True)  # YYYY-MM
    return_type: Mapped[GstrReturnType] = mapped_column(Enum(GstrReturnType), index=True)
    source: Mapped[GstrImportSource] = mapped_column(Enum(GstrImportSource), default=GstrImportSource.excel)
    status: Mapped[GstrImportStatus] = mapped_column(Enum(GstrImportStatus), default=GstrImportStatus.processing)
    uploaded_by: Mapped[UUID | None] = mapped_column(ForeignKey("users.id"))
    original_filename: Mapped[str | None] = mapped_column(String(255))
    row_count: Mapped[int] = mapped_column(default=0)
    error_message: Mapped[str | None] = mapped_column(Text)


class GstrInwardRow(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "gstr_inward_rows"
    __table_args__ = (
        Index(
            "ix_gstr_inward_dedupe",
            "company_id",
            "period",
            "return_type",
            "supplier_gstin",
            "invoice_number",
            "invoice_date",
        ),
    )
    company_id: Mapped[UUID] = mapped_column(ForeignKey("companies.id"), index=True)
    import_id: Mapped[UUID] = mapped_column(ForeignKey("gstr_imports.id"), index=True)
    period: Mapped[str] = mapped_column(String(7), index=True)
    return_type: Mapped[GstrReturnType] = mapped_column(Enum(GstrReturnType), index=True)
    supplier_gstin: Mapped[str | None] = mapped_column(String(20), index=True)
    supplier_name: Mapped[str | None] = mapped_column(String(200))
    invoice_number: Mapped[str | None] = mapped_column(String(120), index=True)
    invoice_date: Mapped[date | None] = mapped_column(Date)
    taxable_amount: Mapped[Decimal | None] = mapped_column(Numeric(14, 2))
    cgst_amount: Mapped[Decimal | None] = mapped_column(Numeric(14, 2))
    sgst_amount: Mapped[Decimal | None] = mapped_column(Numeric(14, 2))
    igst_amount: Mapped[Decimal | None] = mapped_column(Numeric(14, 2))
    net_amount: Mapped[Decimal | None] = mapped_column(Numeric(14, 2))
    place_of_supply: Mapped[str | None] = mapped_column(String(10))
    document_type: Mapped[str | None] = mapped_column(String(40))
    raw_json: Mapped[dict] = mapped_column(JSON, default=dict)


class ItcMatch(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "itc_matches"
    __table_args__ = (
        Index("ix_itc_match_period_status", "company_id", "period", "status"),
    )
    company_id: Mapped[UUID] = mapped_column(ForeignKey("companies.id"), index=True)
    period: Mapped[str] = mapped_column(String(7), index=True)
    return_type: Mapped[GstrReturnType] = mapped_column(Enum(GstrReturnType), default=GstrReturnType.gstr_2b)
    invoice_id: Mapped[UUID | None] = mapped_column(ForeignKey("invoices.id"), index=True)
    gstr_row_id: Mapped[UUID | None] = mapped_column(ForeignKey("gstr_inward_rows.id"), index=True)
    status: Mapped[ItcMatchStatus] = mapped_column(Enum(ItcMatchStatus), index=True)
    amount_delta: Mapped[Decimal | None] = mapped_column(Numeric(14, 2))
    notes: Mapped[str | None] = mapped_column(Text)


class SupplierReminder(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "supplier_reminders"
    company_id: Mapped[UUID] = mapped_column(ForeignKey("companies.id"), index=True)
    invoice_id: Mapped[UUID] = mapped_column(ForeignKey("invoices.id"), index=True)
    itc_match_id: Mapped[UUID | None] = mapped_column(ForeignKey("itc_matches.id"))
    channel: Mapped[ReminderChannel] = mapped_column(Enum(ReminderChannel))
    status: Mapped[ReminderStatus] = mapped_column(Enum(ReminderStatus), index=True)
    contact_phone: Mapped[str | None] = mapped_column(String(20))
    contact_email: Mapped[str | None] = mapped_column(String(320))
    message_preview: Mapped[str | None] = mapped_column(Text)
    promised_by: Mapped[date | None] = mapped_column(Date)
    called: Mapped[bool] = mapped_column(Boolean, default=False)
    resolved_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_by: Mapped[UUID | None] = mapped_column(ForeignKey("users.id"))


class PaymentOrder(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "payment_orders"
    company_id: Mapped[UUID] = mapped_column(ForeignKey("companies.id"), index=True)
    plan_code: Mapped[str] = mapped_column(ForeignKey("subscription_plans.code"))
    seats: Mapped[int]
    months: Mapped[int]
    amount_paise: Mapped[int] = mapped_column(BigInteger)
    currency: Mapped[str] = mapped_column(String(3), default="INR")
    provider: Mapped[str] = mapped_column(String(20), default="razorpay")
    provider_order_id: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    provider_payment_id: Mapped[str | None] = mapped_column(String(64))
    status: Mapped[PaymentStatus] = mapped_column(Enum(PaymentStatus), default=PaymentStatus.created, index=True)
    failure_reason: Mapped[str | None] = mapped_column(Text)
    paid_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    subscription_id: Mapped[UUID | None] = mapped_column(ForeignKey("subscriptions.id"))
    created_by: Mapped[UUID | None] = mapped_column(ForeignKey("users.id"))


class PaymentEvent(Base, UUIDMixin):
    __tablename__ = "payment_events"
    provider_event_id: Mapped[str] = mapped_column(String(100), unique=True)
    event_type: Mapped[str] = mapped_column(String(60))
    payload: Mapped[dict] = mapped_column(JSON, default=dict)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), index=True
    )
