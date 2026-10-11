"""Composite indexes for the hot list/dashboard queries.

Revision ID: 0003
Revises: 0002

Idempotent: 0001 runs create_all() so fresh databases already have these.
"""
from alembic import op

revision = "0003"
down_revision = "0002"
branch_labels = None
depends_on = None

INDEXES = [
    ("ix_invoices_company_uploaded", "invoices", "company_id, uploaded_at"),
    ("ix_invoices_company_status_uploaded", "invoices", "company_id, approval_status, uploaded_at"),
    ("ix_invoices_employee_updated", "invoices", "employee_id, updated_at"),
    ("ix_notifications_employee_created", "notifications", "employee_id, created_at"),
    ("ix_notifications_company_type_created", "notifications", "company_id, type, created_at"),
    ("ix_otp_mobile_created", "otp_challenges", "mobile, created_at"),
    ("ix_employees_company_active", "employees", "company_id, is_active"),
    ("ix_subscriptions_company_status_ends", "subscriptions", "company_id, status, ends_at"),
]


def upgrade() -> None:
    for name, table, columns in INDEXES:
        op.execute(f"CREATE INDEX IF NOT EXISTS {name} ON {table} ({columns})")


def downgrade() -> None:
    for name, _, _ in INDEXES:
        op.execute(f"DROP INDEX IF EXISTS {name}")
