from fastapi import APIRouter, Depends, Query
from pymongo.asynchronous.database import AsyncDatabase

from app.core.deps import Principal, company_admin_principal, current_employee
from app.core.ratelimit import enforce
from app.db.mongo import get_db, paginate
from app.schemas.common import Announcement, NotificationRead
from app.services.audit import record_audit
from app.services.notifications import announce

router = APIRouter()
admin_router = APIRouter()

ANNOUNCEMENT = "companyAnnouncement"


def serialize(item: dict) -> dict:
    return {
        "id": item["_id"],
        "type": item["type"],
        "title": item["title"],
        "body": item["body"],
        "createdAt": item.get("created_at"),
        "read": bool(item.get("read")),
        "invoiceServerId": item.get("invoice_id"),
        "sentAt": item.get("sent_at"),
    }


@router.get("")
async def list_notifications(
    page: int = Query(1, ge=1),
    page_size: int = Query(200, alias="pageSize", ge=1, le=500),
    employee: dict = Depends(current_employee),
    db: AsyncDatabase = Depends(get_db),
):
    query = {"company_id": employee["company_id"], "employee_id": employee["_id"]}
    return await paginate(db.notifications, query, [("created_at", -1), ("_id", 1)], page, page_size, serialize)


@router.post("/read")
async def mark_read(
    body: NotificationRead,
    employee: dict = Depends(current_employee),
    db: AsyncDatabase = Depends(get_db),
):
    result = await db.notifications.update_many(
        {
            "company_id": employee["company_id"],
            "employee_id": employee["_id"],
            "_id": {"$in": [str(x) for x in body.ids[:500]]},
            "read": False,
        },
        {"$set": {"read": True}},
    )
    return {"updated": result.modified_count}


@admin_router.post("/announcements", status_code=201)
async def create_announcement(
    body: Announcement,
    principal: Principal = Depends(company_admin_principal),
    db: AsyncDatabase = Depends(get_db),
):
    await enforce(f"announce:{principal.company_id}", 20, 3600, "Announcement limit reached; try again later")
    count = await announce(db, principal.company_id, body.title, body.body)
    await record_audit(db, principal, "announcement.sent", "announcement", None, f"Sent \"{body.title}\" to {count} employees")
    return {"created": count}


@admin_router.get("/announcements")
async def announcement_history(
    limit: int = Query(50, ge=1, le=200),
    principal: Principal = Depends(company_admin_principal),
    db: AsyncDatabase = Depends(get_db),
):
    """One row per broadcast with recipient and read counts."""
    cursor = await db.notifications.aggregate([
        {"$match": {"company_id": principal.company_id, "type": ANNOUNCEMENT}},
        {"$group": {
            "_id": {"title": "$title", "body": "$body", "created_at": "$created_at"},
            "recipients": {"$sum": 1},
            "read": {"$sum": {"$cond": ["$read", 1, 0]}},
        }},
        {"$sort": {"_id.created_at": -1}},
        {"$limit": limit},
    ])
    items = []
    async for row in cursor:
        title = row["_id"].get("title")
        if title and title.strip():
            items.append({
                "title": title,
                "body": row["_id"].get("body"),
                "createdAt": row["_id"].get("created_at"),
                "recipients": row["recipients"],
                "read": row["read"],
            })
    return {"items": items}


@admin_router.get("")
async def admin_notifications(
    page: int = Query(1, ge=1),
    page_size: int = Query(100, alias="pageSize", ge=1, le=500),
    type: str | None = Query(None, max_length=40),
    exclude_type: str | None = Query(None, alias="excludeType", max_length=40),
    principal: Principal = Depends(company_admin_principal),
    db: AsyncDatabase = Depends(get_db),
):
    query: dict = {"company_id": principal.company_id}
    if type and exclude_type:
        query["type"] = {"$eq": type, "$ne": exclude_type}
    elif type:
        query["type"] = type
    elif exclude_type:
        query["type"] = {"$ne": exclude_type}
    return await paginate(db.notifications, query, [("created_at", -1), ("_id", 1)], page, page_size, serialize)
