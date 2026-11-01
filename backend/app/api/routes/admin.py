from datetime import timedelta
from decimal import Decimal

from fastapi import APIRouter, Depends
from pymongo.asynchronous.database import AsyncDatabase

from app.core.deps import Principal, company_admin_principal
from app.db.mongo import get_db
from app.models import ApprovalStatus
from app.services.reports import day_bucket, ist_day_start, ist_last_days, ist_today
from app.services.subscription import seat_usage

router = APIRouter()

DAILY_DAYS = 14
TOP_CATEGORY_DAYS = 30
_AMOUNT = {"$ifNull": ["$net_amount", 0]}


def _money(value) -> Decimal:
    return Decimal(str(value or 0)).quantize(Decimal("0.01"))


@router.get("/dashboard")
async def dashboard(
    principal: Principal = Depends(company_admin_principal),
    db: AsyncDatabase = Depends(get_db),
):
    company_id = principal.company_id
    by_status = {
        row["_id"]: row
        async for row in await db.invoices.aggregate([
            {"$match": {"company_id": company_id}},
            {"$group": {"_id": "$approval_status", "count": {"$sum": 1}, "amount": {"$sum": _AMOUNT}}},
        ])
    }
    today_start = ist_day_start(ist_today())
    today_uploads = await db.invoices.count_documents({
        "company_id": company_id,
        "uploaded_at": {"$gte": today_start, "$lt": today_start + timedelta(days=1)},
    })

    window_start, days = ist_last_days(DAILY_DAYS)
    per_day = {
        row["_id"]: row
        async for row in await db.invoices.aggregate([
            {"$match": {"company_id": company_id, "uploaded_at": {"$gte": window_start}}},
            {"$group": {"_id": day_bucket("uploaded_at"), "count": {"$sum": 1}, "amount": {"$sum": _AMOUNT}}},
        ])
    }

    category_start, _ = ist_last_days(TOP_CATEGORY_DAYS)
    top = await (await db.invoices.aggregate([
        {"$match": {"company_id": company_id, "uploaded_at": {"$gte": category_start}, "category_id": {"$ne": None}}},
        {"$group": {"_id": "$category_id", "count": {"$sum": 1}, "amount": {"$sum": _AMOUNT}}},
        {"$sort": {"count": -1, "_id": 1}},
        {"$limit": 5},
    ])).to_list(length=5)
    names = {
        c["_id"]: c["name"]
        async for c in db.expense_categories.find({"_id": {"$in": [row["_id"] for row in top]}}, {"name": 1})
    }

    def status(key: ApprovalStatus) -> dict:
        return by_status.get(key.value, {})

    return {
        "pendingCount": status(ApprovalStatus.pending).get("count", 0),
        "approvedCount": status(ApprovalStatus.approved).get("count", 0),
        "rejectedCount": status(ApprovalStatus.rejected).get("count", 0),
        "returnedCount": status(ApprovalStatus.returned).get("count", 0),
        "todayUploads": today_uploads,
        "approvedAmount": _money(status(ApprovalStatus.approved).get("amount")),
        "pendingAmount": _money(status(ApprovalStatus.pending).get("amount")),
        "daily": [
            {"date": day, "count": per_day.get(day, {}).get("count", 0), "amount": _money(per_day.get(day, {}).get("amount"))}
            for day in days
        ],
        "topCategories": [
            {"name": names.get(row["_id"], "Uncategorised"), "count": row["count"], "amount": _money(row["amount"])}
            for row in top
        ],
        "seats": await seat_usage(db, company_id),
    }
