"""OTP delivery. Pick the provider with SMS_PROVIDER = console | msg91 | twilio.

`console` only logs the code and is refused in production.
"""
import logging

import httpx
from fastapi import HTTPException

from app.core.config import settings

logger = logging.getLogger(__name__)

TIMEOUT = httpx.Timeout(10.0, connect=5.0)


class SMSUnavailable(HTTPException):
    def __init__(self, detail: str = "OTP delivery is temporarily unavailable. Please try again later.") -> None:
        super().__init__(503, detail)


def to_e164(mobile: str) -> str:
    digits = "".join(ch for ch in mobile if ch.isdigit())
    if len(digits) == 10:
        digits = "91" + digits
    return digits


async def send_otp(mobile: str, code: str) -> None:
    if not settings.sms_configured:
        raise SMSUnavailable()
    provider = settings.sms_provider.strip().lower()
    try:
        if provider == "msg91":
            await _send_msg91(mobile, code)
        elif provider == "twilio":
            await _send_twilio(mobile, code)
        else:
            logger.warning("Development OTP for %s: %s", mobile, code)
    except SMSUnavailable:
        raise
    except Exception as exc:  # noqa: BLE001
        logger.exception("SMS delivery via %s failed", provider)
        raise SMSUnavailable() from exc


async def _send_msg91(mobile: str, code: str) -> None:
    async with httpx.AsyncClient(timeout=TIMEOUT) as client:
        response = await client.post(
            "https://control.msg91.com/api/v5/otp",
            params={"template_id": settings.msg91_template_id, "mobile": to_e164(mobile), "otp": code},
            headers={"authkey": settings.msg91_auth_key, "accept": "application/json"},
        )
    if response.status_code >= 400 or response.json().get("type") == "error":
        raise RuntimeError(f"MSG91 rejected the request: {response.status_code} {response.text[:200]}")


async def _send_twilio(mobile: str, code: str) -> None:
    sid = settings.twilio_account_sid
    async with httpx.AsyncClient(timeout=TIMEOUT, auth=(sid, settings.twilio_auth_token)) as client:
        response = await client.post(
            f"https://api.twilio.com/2010-04-01/Accounts/{sid}/Messages.json",
            data={
                "To": "+" + to_e164(mobile),
                "From": settings.twilio_from_number,
                "Body": f"{code} is your GST Expense Scanner login code. It expires in 5 minutes.",
            },
        )
    if response.status_code >= 400:
        raise RuntimeError(f"Twilio rejected the request: {response.status_code} {response.text[:200]}")
