from fastapi import APIRouter, Depends, Query
from sqlalchemy import Integer, cast, func, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.pagination import paginate
from app.core.deps import Principal, company_admin_principal, current_employee
from app.core.ratelimit import enforce
from app.db.session import get_db
from app.models import Employee, Notification
from app.schemas.common import Announcement, NotificationRead
from app.services.notifications import announce

router = APIRouter()
admin_router = APIRouter()


def serialize(item: Notification) -> dict:
    return {
        "id": item.id,
        "type": item.type,
        "title": item.title,
        "body": item.body,
        "createdAt": item.created_at,
        "read": item.read,
        "invoiceServerId": item.invoice_id,
        "sentAt": item.sent_at,
    }


@router.get("")
async def list_notifications(
    page: int = Query(1, ge=1),
    page_size: int = Query(200, alias="pageSize", ge=1, le=500),
    employee: Employee = Depends(current_employee),
    db: AsyncSession = Depends(get_db),
):
    query = select(Notification).where(
        Notification.company_id == employee.company_id,
        Notification.employee_id == employee.id,
    )
    return await paginate(db, query.order_by(Notification.created_at.desc(), Notification.id), page, page_size, serialize)


@router.post("/read")
async def mark_read(
    body: NotificationRead,
    employee: Employee = Depends(current_employee),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        update(Notification)
        .where(
            Notification.company_id == employee.company_id,
            Notification.employee_id == employee.id,
            Notification.id.in_(body.ids[:500]),
        )
        .values(read=True)
    )
    await db.commit()
    return {"updated": result.rowcount}


@admin_router.post("/announcements", status_code=201)
async def create_announcement(
    body: Announcement,
    principal: Principal = Depends(company_admin_principal),
    db: AsyncSession = Depends(get_db),
):
    await enforce(f"announce:{principal.company_id}", 20, 3600, "Announcement limit reached; try again later")
    count = await announce(db, principal.company_id, body.title, body.body)
    return {"created": count}


@admin_router.get("/announcements")
async def announcement_history(
    limit: int = Query(50, ge=1, le=200),
    principal: Principal = Depends(company_admin_principal),
    db: AsyncSession = Depends(get_db),
):
    """One row per broadcast with recipient and read counts."""
    rows = (
        await db.execute(
            select(
                Notification.title,
                Notification.body,
                Notification.created_at,
                func.count(Notification.id),
                func.sum(cast(Notification.read, Integer)),
            )
            .where(Notification.company_id == principal.company_id, Notification.type == "companyAnnouncement")
            .group_by(Notification.title, Notification.body, Notification.created_at)
            .order_by(Notification.created_at.desc())
            .limit(limit)
        )
    ).all()
    return {
        "items": [
            {"title": title, "body": body, "createdAt": created_at, "recipients": recipients, "read": int(read or 0)}
            for title, body, created_at, recipients, read in rows
            if title and title.strip()
        ]
    }


@admin_router.get("")
async def admin_notifications(
    page: int = Query(1, ge=1),
    page_size: int = Query(100, alias="pageSize", ge=1, le=500),
    type: str | None = Query(None, max_length=40),
    exclude_type: str | None = Query(None, alias="excludeType", max_length=40),
    principal: Principal = Depends(company_admin_principal),
    db: AsyncSession = Depends(get_db),
):
    query = select(Notification).where(Notification.company_id == principal.company_id)
    if type:
        query = query.where(Notification.type == type)
    if exclude_type:
        query = query.where(Notification.type != exclude_type)
    return await paginate(db, query.order_by(Notification.created_at.desc(), Notification.id), page, page_size, serialize)
