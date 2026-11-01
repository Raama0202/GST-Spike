"""Unauthenticated data for the pricing, contact and policy pages."""
from fastapi import APIRouter, Depends
from pymongo.asynchronous.database import AsyncDatabase

from app.core.config import settings
from app.db.mongo import get_db

router = APIRouter()


@router.get("/business")
async def business():
    return {
        "name": settings.business_name,
        "legalName": settings.business_legal_name or settings.business_name,
        "gstin": settings.business_gstin_clean or None,
        "address": settings.business_address or None,
        "email": settings.business_email or None,
        "phone": settings.business_phone or None,
        "taxPercent": settings.effective_tax_percent,
        "paymentsEnabled": settings.payments_configured,
        "trialDays": settings.signup_trial_days,
    }


@router.get("/plans")
async def plans(db: AsyncDatabase = Depends(get_db)):
    rows = await db.subscription_plans.find({"monthly_price_inr": {"$gt": 0}}).sort([("monthly_price_inr", 1), ("_id", 1)]).to_list(None)
    return {
        "items": [
            {
                "code": p["code"],
                "name": p["name"],
                "monthlyPriceInr": p["monthly_price_inr"],
                "maxEmployees": p.get("max_employees"),
                "features": p.get("features_json") or {},
            }
            for p in rows
        ],
        "taxPercent": settings.effective_tax_percent,
    }
