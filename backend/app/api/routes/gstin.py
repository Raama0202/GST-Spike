"""GSTIN verification for every client: employee app, admin apps, web console."""
from fastapi import APIRouter, Depends, Path, Query, Request
from pydantic import BaseModel, Field

from app.core.config import settings
from app.core.deps import Principal, current_principal
from app.core.ratelimit import client_ip, enforce
from app.models import Role
from app.services.gstin_verify import verify_gstin

router = APIRouter()
public_router = APIRouter()

PUBLIC_FIELDS = ("gstin", "formatValid", "status", "legalName", "tradeName", "stateName", "liveCheck", "message")


class GstinCheck(BaseModel):
    gstin: str = Field(min_length=1, max_length=20)


@router.get("/status")
async def verification_status(principal: Principal = Depends(current_principal)):
    _ = principal
    return {"liveCheck": settings.gstin_verify_configured, "provider": settings.gstin_verify_provider.strip().lower() or None}


@router.get("/{gstin}")
async def verify(
    gstin: str = Path(max_length=20),
    refresh: bool = Query(False),
    principal: Principal = Depends(current_principal),
):
    scope = principal.company_id or principal.user.id
    # Each live lookup costs money on paid providers; cached answers are free.
    await enforce(f"gstin-verify:{scope}", 300, 3600, "Too many GSTIN checks; try again in a while")
    if refresh and principal.user.role == Role.employee:
        refresh = False
    return await verify_gstin(gstin, refresh=refresh)


@public_router.post("/check")
async def public_check(body: GstinCheck, request: Request):
    """For the firm registration form, before an account exists."""
    await enforce(f"gstin-public:{client_ip(request)}", 10, 3600, "Too many GSTIN checks; try again later")
    result = await verify_gstin(body.gstin)
    return {key: result.get(key) for key in PUBLIC_FIELDS}
