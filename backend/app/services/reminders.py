"""Build supplier reminder payloads (WhatsApp / email / manual follow-up)."""

from __future__ import annotations

from urllib.parse import quote

from app.models import Invoice, ReminderChannel


def contact_from_invoice(invoice: Invoice) -> tuple[str | None, str | None]:
    edited = invoice.edited_data or {}
    ocr = invoice.ocr_data or {}
    phone = edited.get("supplierPhone") or ocr.get("supplierPhone")
    email = edited.get("supplierEmail") or ocr.get("supplierEmail")
    if isinstance(phone, str):
        phone = "".join(ch for ch in phone if ch.isdigit()) or None
    else:
        phone = None
    if isinstance(email, str):
        email = email.strip().lower() or None
    else:
        email = None
    return phone, email


def reminder_message(invoice: Invoice, company_name: str | None = None) -> str:
    vendor = invoice.vendor_name or "Supplier"
    inv = invoice.invoice_number or "your invoice"
    date = invoice.invoice_date.isoformat() if invoice.invoice_date else "N/A"
    amount = f"₹{invoice.net_amount}" if invoice.net_amount is not None else "the billed amount"
    who = company_name or "our company"
    return (
        f"Dear {vendor}, this is a reminder from {who}. "
        f"Invoice {inv} dated {date} for {amount} is not yet reflecting in our GSTR-2B. "
        f"Please file/include it in your GSTR-1 so we can claim ITC. Thank you."
    )


def choose_channel(phone: str | None, email: str | None) -> ReminderChannel:
    if phone:
        return ReminderChannel.whatsapp
    if email:
        return ReminderChannel.email
    return ReminderChannel.manual


def whatsapp_link(phone: str, message: str) -> str:
    digits = "".join(ch for ch in phone if ch.isdigit())
    if len(digits) == 10:
        digits = f"91{digits}"
    return f"https://wa.me/{digits}?text={quote(message)}"


def mailto_link(email: str, subject: str, body: str) -> str:
    return f"mailto:{email}?subject={quote(subject)}&body={quote(body)}"
