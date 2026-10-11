from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.deps import current_employee
from app.db.session import get_db
from app.models import Device, Employee
from app.schemas.common import DeviceRegister

router = APIRouter()


@router.post("/register")
async def register_device(
    body: DeviceRegister,
    employee: Employee = Depends(current_employee),
    db: AsyncSession = Depends(get_db),
):
    device = await db.scalar(
        select(Device).where(
            Device.company_id == employee.company_id, Device.device_id == body.device_id
        )
    )
    if device:
        device.employee_id = employee.id
        device.platform = body.platform
        device.app_version = body.app_version
        device.fcm_token = body.fcm_token
    else:
        device = Device(
            company_id=employee.company_id,
            employee_id=employee.id,
            device_id=body.device_id,
            platform=body.platform,
            app_version=body.app_version,
            fcm_token=body.fcm_token,
        )
        db.add(device)
    await db.commit()
    await db.refresh(device)
    return {"id": device.id, "registered": True}
