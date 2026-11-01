from pymongo.asynchronous.database import AsyncDatabase

from app.db.mongo import new_id, utcnow
from app.services.push import push_in_background

ANNOUNCE_BATCH = 1000


def notification_doc(
    company_id: str,
    employee_id: str,
    notification_type: str,
    title: str,
    body: str,
    invoice_id: str | None = None,
    created_at=None,
) -> dict:
    return {
        "_id": new_id(),
        "company_id": company_id,
        "employee_id": employee_id,
        "type": notification_type,
        "title": title,
        "body": body,
        "invoice_id": invoice_id,
        "read": False,
        "sent_at": None,
        "created_at": created_at or utcnow(),
    }


async def notify_employee(
    db: AsyncDatabase,
    company_id: str,
    employee_id: str,
    notification_type: str,
    title: str,
    body: str,
    invoice_id: str | None = None,
) -> dict:
    item = notification_doc(company_id, employee_id, notification_type, title, body, invoice_id)
    await db.notifications.insert_one(item)
    data = {"type": notification_type, "notificationId": item["_id"]}
    if invoice_id:
        data["invoiceId"] = invoice_id
    push_in_background(db, company_id, [employee_id], title, body, data, [item["_id"]])
    return item


async def announce(db: AsyncDatabase, company_id: str, title: str, body: str) -> int:
    employee_ids = [
        row["_id"]
        async for row in db.employees.find({"company_id": company_id, "is_active": True}, {"_id": 1})
    ]
    now = utcnow()
    for start in range(0, len(employee_ids), ANNOUNCE_BATCH):
        batch = employee_ids[start:start + ANNOUNCE_BATCH]
        await db.notifications.insert_many(
            [notification_doc(company_id, employee_id, "companyAnnouncement", title, body, created_at=now) for employee_id in batch],
            ordered=False,
        )
    if employee_ids:
        push_in_background(db, company_id, employee_ids, title, body, {"type": "companyAnnouncement"})
    return len(employee_ids)
