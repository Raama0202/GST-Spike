"""Enumerations stored on MongoDB documents (as their string values).

Collections and their fields:

companies           name, legal_name, gstin, additional_gstins[], name_aliases[], state_code, industry,
                    logo_url, primary_color_hex, activation_code, status, requires_gps,
                    duplicate_check_enabled, min_ocr_confidence_warn, features_json
users               company_id, email, password_hash, role, is_active, refresh_token_hash, name, email_verified
employees           company_id, user_id, branch_id, name, employee_code, mobile, email, is_active
subscription_plans  code, name, monthly_price_inr, max_employees, features_json
subscriptions       company_id, plan_code, seats, starts_at, ends_at, status
branches            company_id, name, code, is_active
expense_categories  company_id, name, parent_id, sort_order, is_active
invoices            company_id, employee_id, branch_id, category_id, idempotency_key, invoice_number, gstin,
                    vendor_name, invoice_date ("YYYY-MM-DD"), taxable/cgst/sgst/igst/total_tax amounts, net_amount (invoice value),
                    ocr_confidence, ocr_data, edited_data, *_image_path, approval_status, admin_remarks,
                    latitude, longitude, device_id, duplicate_override, uploaded_at, reviewed_at, reviewed_by
notifications       company_id, employee_id, type, title, body, invoice_id, read, sent_at, created_at
otp_challenges      purpose, target, code_hash, expires_at, consumed_at, attempts, created_at
signup_requests     email, payload, expires_at
devices, audit_logs, gstr_imports, gstr_inward_rows, itc_matches, supplier_reminders,
payment_orders, payment_events, kv (cache / rate limits)
"""
import enum


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
    refunded = "refunded"


class OtpPurpose(str, enum.Enum):
    login = "login"
    signup = "signup"
    password_reset = "password_reset"


__all__ = [
    "ApprovalStatus",
    "CompanyStatus",
    "GstrImportSource",
    "GstrImportStatus",
    "GstrReturnType",
    "ItcMatchStatus",
    "OtpPurpose",
    "PaymentStatus",
    "ReminderChannel",
    "ReminderStatus",
    "Role",
    "SubscriptionStatus",
]
