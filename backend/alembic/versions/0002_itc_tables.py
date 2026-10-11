"""ITC tables for GSTR-2A/2B import, matching, and supplier reminders.

Revision ID: 0002
Revises: 0001

Note: migration 0001 uses Base.metadata.create_all(), which already creates
ITC tables when models are present. This revision is a no-op in that case and
only creates ITC objects for databases that upgraded from a pre-ITC 0001.
"""

from alembic import op
import sqlalchemy as sa

revision = "0002"
down_revision = "0001"
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    if "gstr_imports" in inspector.get_table_names():
        return

    gstr_return = sa.Enum("2A", "2B", name="gstrreturntype")
    gstr_source = sa.Enum("excel", "gsp", name="gstrimportsource")
    gstr_status = sa.Enum("processing", "ready", "failed", name="gstrimportstatus")
    match_status = sa.Enum(
        "matched",
        "partial",
        "missing_in_2b",
        "missing_in_books",
        "mismatch",
        name="itcmatchstatus",
    )
    reminder_channel = sa.Enum(
        "whatsapp", "email", "sms_intent", "manual", name="reminderchannel"
    )
    reminder_status = sa.Enum(
        "sent_link", "manual_followup", "resolved", name="reminderstatus"
    )

    gstr_return.create(bind, checkfirst=True)
    gstr_source.create(bind, checkfirst=True)
    gstr_status.create(bind, checkfirst=True)
    match_status.create(bind, checkfirst=True)
    reminder_channel.create(bind, checkfirst=True)
    reminder_status.create(bind, checkfirst=True)

    op.create_table(
        "gstr_imports",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("company_id", sa.Uuid(), sa.ForeignKey("companies.id"), nullable=False, index=True),
        sa.Column("period", sa.String(7), nullable=False, index=True),
        sa.Column("return_type", gstr_return, nullable=False, index=True),
        sa.Column("source", gstr_source, nullable=False),
        sa.Column("status", gstr_status, nullable=False),
        sa.Column("uploaded_by", sa.Uuid(), sa.ForeignKey("users.id")),
        sa.Column("original_filename", sa.String(255)),
        sa.Column("row_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("error_message", sa.Text()),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_table(
        "gstr_inward_rows",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("company_id", sa.Uuid(), sa.ForeignKey("companies.id"), nullable=False, index=True),
        sa.Column("import_id", sa.Uuid(), sa.ForeignKey("gstr_imports.id"), nullable=False, index=True),
        sa.Column("period", sa.String(7), nullable=False, index=True),
        sa.Column("return_type", gstr_return, nullable=False, index=True),
        sa.Column("supplier_gstin", sa.String(20), index=True),
        sa.Column("supplier_name", sa.String(200)),
        sa.Column("invoice_number", sa.String(120), index=True),
        sa.Column("invoice_date", sa.Date()),
        sa.Column("taxable_amount", sa.Numeric(14, 2)),
        sa.Column("cgst_amount", sa.Numeric(14, 2)),
        sa.Column("sgst_amount", sa.Numeric(14, 2)),
        sa.Column("igst_amount", sa.Numeric(14, 2)),
        sa.Column("net_amount", sa.Numeric(14, 2)),
        sa.Column("place_of_supply", sa.String(10)),
        sa.Column("document_type", sa.String(40)),
        sa.Column("raw_json", sa.JSON(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index(
        "ix_gstr_inward_dedupe",
        "gstr_inward_rows",
        ["company_id", "period", "return_type", "supplier_gstin", "invoice_number", "invoice_date"],
    )
    op.create_table(
        "itc_matches",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("company_id", sa.Uuid(), sa.ForeignKey("companies.id"), nullable=False, index=True),
        sa.Column("period", sa.String(7), nullable=False, index=True),
        sa.Column("return_type", gstr_return, nullable=False),
        sa.Column("invoice_id", sa.Uuid(), sa.ForeignKey("invoices.id"), index=True),
        sa.Column("gstr_row_id", sa.Uuid(), sa.ForeignKey("gstr_inward_rows.id"), index=True),
        sa.Column("status", match_status, nullable=False, index=True),
        sa.Column("amount_delta", sa.Numeric(14, 2)),
        sa.Column("notes", sa.Text()),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index("ix_itc_match_period_status", "itc_matches", ["company_id", "period", "status"])
    op.create_table(
        "supplier_reminders",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("company_id", sa.Uuid(), sa.ForeignKey("companies.id"), nullable=False, index=True),
        sa.Column("invoice_id", sa.Uuid(), sa.ForeignKey("invoices.id"), nullable=False, index=True),
        sa.Column("itc_match_id", sa.Uuid(), sa.ForeignKey("itc_matches.id")),
        sa.Column("channel", reminder_channel, nullable=False),
        sa.Column("status", reminder_status, nullable=False, index=True),
        sa.Column("contact_phone", sa.String(20)),
        sa.Column("contact_email", sa.String(320)),
        sa.Column("message_preview", sa.Text()),
        sa.Column("promised_by", sa.Date()),
        sa.Column("called", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("resolved_at", sa.DateTime(timezone=True)),
        sa.Column("created_by", sa.Uuid(), sa.ForeignKey("users.id")),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
    )


def downgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    if "supplier_reminders" in inspector.get_table_names():
        op.drop_table("supplier_reminders")
    if "itc_matches" in inspector.get_table_names():
        op.drop_index("ix_itc_match_period_status", table_name="itc_matches")
        op.drop_table("itc_matches")
    if "gstr_inward_rows" in inspector.get_table_names():
        op.drop_index("ix_gstr_inward_dedupe", table_name="gstr_inward_rows")
        op.drop_table("gstr_inward_rows")
    if "gstr_imports" in inspector.get_table_names():
        op.drop_table("gstr_imports")
