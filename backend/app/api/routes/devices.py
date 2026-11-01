from fastapi import APIRouter, Depends, Path
from pymongo import ReturnDocument
from pymongo.asynchronous.database import AsyncDatabase

from app.core.deps import current_employee
from app.db.mongo import get_db, new_id, utcnow
from app.schemas.common import DeviceRegister

router = APIRouter()


@router.post("/register")
async def register_device(
    body: DeviceRegister,
    employee: dict = Depends(current_employee),
    db: AsyncDatabase = Depends(get_db),
):
    now = utcnow()
    device = await db.devices.find_one_and_update(
        {"company_id": employee["company_id"], "device_id": body.device_id},
        {
            "$set": {
                "employee_id": employee["_id"],
                "platform": body.platform,
                "app_version": body.app_version,
                "fcm_token": body.fcm_token,
                "updated_at": now,
            },
            "$setOnInsert": {"_id": new_id(), "created_at": now},
        },
        upsert=True,
        return_document=ReturnDocument.AFTER,
    )
    if body.fcm_token:
        # A push token belongs to one app install; whoever registered it last owns it,
        # so the previous user of a shared phone stops receiving this person's alerts.
        await db.devices.delete_many({"fcm_token": body.fcm_token, "_id": {"$ne": device["_id"]}})
    return {"id": device["_id"], "registered": True}


@router.delete("/{device_id}", status_code=204)
async def unregister_device(
    device_id: str = Path(max_length=200),
    employee: dict = Depends(current_employee),
    db: AsyncDatabase = Depends(get_db),
):
    await db.devices.delete_one({"company_id": employee["company_id"], "device_id": device_id, "employee_id": employee["_id"]})
