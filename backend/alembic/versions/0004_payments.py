"""Payment orders and provider webhook events (Razorpay).

Revision ID: 0004
Revises: 0003

Idempotent: 0001 runs create_all() so fresh databases already have these.
"""
from alembic import op

revision = "0004"
down_revision = "0003"
branch_labels = None
depends_on = None


def upgrade() -> None:
    from app.models import PaymentEvent, PaymentOrder

    bind = op.get_bind()
    PaymentOrder.__table__.create(bind, checkfirst=True)
    PaymentEvent.__table__.create(bind, checkfirst=True)


def downgrade() -> None:
    from app.models import PaymentEvent, PaymentOrder

    bind = op.get_bind()
    PaymentEvent.__table__.drop(bind, checkfirst=True)
    PaymentOrder.__table__.drop(bind, checkfirst=True)
