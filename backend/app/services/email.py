"""Transactional email. EMAIL_PROVIDER = brevo | resend | smtp | console, or a
comma-separated fallback chain such as "brevo,resend".

brevo  — free forever plan, 300 emails/day over HTTPS. Use this on Render's free
         tier, which blocks outbound SMTP ports. Needs BREVO_API_KEY + a verified EMAIL_FROM
         (a single verified sender address is enough; no domain needed).
resend — free plan, 100 emails/day (3,000/month) over HTTPS. Needs RESEND_API_KEY and an
         EMAIL_FROM on a domain verified in Resend.
smtp   — any SMTP relay, e.g. Gmail with an app password (smtp.gmail.com:587,
         ~500/day). Needs a paid Render instance (SMTP ports are blocked on free).
console — logs the message; refused in production.
"""
import asyncio
import logging
import smtplib
import ssl
from email.message import EmailMessage
from html import escape

import httpx
from fastapi import HTTPException

from app.core.config import settings

logger = logging.getLogger(__name__)

TIMEOUT = httpx.Timeout(15.0, connect=5.0)


class EmailUnavailable(HTTPException):
    def __init__(self, detail: str = "Email delivery is temporarily unavailable. Please try again later.") -> None:
        super().__init__(503, detail)


async def send_email(to: str, subject: str, text: str, html: str | None = None) -> None:
    providers = settings.email_providers
    if not providers:
        raise EmailUnavailable()
    last_error: Exception | None = None
    for provider in providers:
        try:
            if provider == "brevo":
                await _send_brevo(to, subject, text, html)
            elif provider == "resend":
                await _send_resend(to, subject, text, html)
            elif provider == "smtp":
                await asyncio.to_thread(_send_smtp, to, subject, text, html)
            else:
                logger.warning("Development email to %s — %s\n%s", to, subject, text)
            return
        except Exception as exc:  # noqa: BLE001
            logger.exception("Email delivery via %s failed", provider)
            last_error = exc
    raise EmailUnavailable() from last_error


async def send_otp_email(to: str, code: str, purpose: str) -> None:
    action = {
        "signup": "verify your email and finish creating your company account",
        "password_reset": "reset your password",
    }.get(purpose, "sign in")
    subject = f"{code} is your GST Expense verification code"
    minutes = settings.otp_ttl_minutes
    text = (
        f"Your verification code is {code}.\n\n"
        f"Use it to {action}. It expires in {minutes} minutes.\n"
        "If you did not request this, you can ignore this email."
    )
    html = (
        '<div style="font-family:Arial,sans-serif;font-size:15px;color:#111">'
        f"<p>Use this code to {escape(action)}:</p>"
        f'<p style="font-size:28px;font-weight:bold;letter-spacing:6px">{escape(code)}</p>'
        f"<p>It expires in {minutes} minutes. If you did not request this, ignore this email.</p>"
        "</div>"
    )
    await send_email(to, subject, text, html)


async def _send_brevo(to: str, subject: str, text: str, html: str | None) -> None:
    payload = {
        "sender": {"email": settings.sender_email, "name": settings.email_from_name},
        "to": [{"email": to}],
        "subject": subject,
        "textContent": text,
        "htmlContent": html or f"<pre>{escape(text)}</pre>",
    }
    async with httpx.AsyncClient(timeout=TIMEOUT) as client:
        response = await client.post(
            "https://api.brevo.com/v3/smtp/email",
            json=payload,
            headers={"api-key": settings.brevo_api_key, "accept": "application/json"},
        )
    if response.status_code >= 400:
        raise RuntimeError(f"Brevo rejected the request: {response.status_code} {response.text[:200]}")


async def _send_resend(to: str, subject: str, text: str, html: str | None) -> None:
    payload = {
        "from": f"{settings.email_from_name} <{settings.sender_email}>",
        "to": [to],
        "subject": subject,
        "text": text,
        "html": html or f"<pre>{escape(text)}</pre>",
    }
    async with httpx.AsyncClient(timeout=TIMEOUT) as client:
        response = await client.post(
            "https://api.resend.com/emails",
            json=payload,
            headers={"Authorization": f"Bearer {settings.resend_api_key}"},
        )
    if response.status_code >= 400:
        raise RuntimeError(f"Resend rejected the request: {response.status_code} {response.text[:200]}")


def _send_smtp(to: str, subject: str, text: str, html: str | None) -> None:
    message = EmailMessage()
    message["From"] = f"{settings.email_from_name} <{settings.sender_email}>"
    message["To"] = to
    message["Subject"] = subject
    message.set_content(text)
    if html:
        message.add_alternative(html, subtype="html")
    context = ssl.create_default_context()
    if settings.smtp_port == 465:
        with smtplib.SMTP_SSL(settings.smtp_host, settings.smtp_port, context=context, timeout=15) as smtp:
            if settings.smtp_user:
                smtp.login(settings.smtp_user, settings.smtp_password)
            smtp.send_message(message)
        return
    with smtplib.SMTP(settings.smtp_host, settings.smtp_port, timeout=15) as smtp:
        smtp.starttls(context=context)
        if settings.smtp_user:
            smtp.login(settings.smtp_user, settings.smtp_password)
        smtp.send_message(message)
