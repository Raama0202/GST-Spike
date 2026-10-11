from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.deps import Principal, company_admin_principal
from app.db.session import get_db
from app.models import ApprovalStatus, Invoice

router = APIRouter()


@router.get("/dashboard")
async def dashboard(
    principal: Principal = Depends(company_admin_principal),
    db: AsyncSession = Depends(get_db),
):
    day_start = datetime.now(timezone.utc).replace(hour=0, minute=0, second=0, microsecond=0)
    rows = (
        await db.execute(
            select(Invoice.approval_status, func.count(Invoice.id))
            .where(Invoice.company_id == principal.company_id)
            .group_by(Invoice.approval_status)
        )
    ).all()
    counts = {status.value: count for status, count in rows}
    today_uploads = await db.scalar(
        select(func.count(Invoice.id)).where(
            Invoice.company_id == principal.company_id,
            Invoice.uploaded_at >= day_start,
            Invoice.uploaded_at < day_start + timedelta(days=1),
        )
    )
    return {
        "pendingCount": counts.get(ApprovalStatus.pending.value, 0),
        "todayUploads": today_uploads or 0,
        "approvedCount": counts.get(ApprovalStatus.approved.value, 0),
        "rejectedCount": counts.get(ApprovalStatus.rejected.value, 0),
        "returnedCount": counts.get(ApprovalStatus.returned.value, 0),
    }
