from datetime import datetime, timezone
from decimal import Decimal, InvalidOperation
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Invoice
from app.schemas.common import InvoicePayload


def _decimal(data: dict, *keys: str) -> Decimal | None:
    value = next((data[key] for key in keys if data.get(key) not in (None, "")), None)
    try:
        return Decimal(str(value)) if value is not None else None
    except (InvalidOperation, ValueError):
        return None


async def find_duplicate(
    db: AsyncSession,
    company_id: UUID,
    invoice_number: str,
    gstin: str | None,
) -> Invoice | None:
    query = select(Invoice).where(
        Invoice.company_id == company_id,
        Invoice.invoice_number == invoice_number,
    )
    if gstin:
        query = query.where(Invoice.gstin == gstin)
    return await db.scalar(query.limit(1))


def populate_invoice_fields(invoice: Invoice, payload: InvoicePayload) -> None:
    data = {**payload.ocr_data, **payload.edited_data}
    invoice.invoice_number = data.get("invoiceNumber") or data.get("invoice_number")
    invoice.gstin = data.get("gstin")
    invoice.vendor_name = data.get("vendorName") or data.get("vendor_name")
    raw_date = data.get("invoiceDate") or data.get("invoice_date")
    if raw_date:
        try:
            invoice.invoice_date = datetime.fromisoformat(str(raw_date)).date()
        except ValueError:
            pass
    # Clients send the shorter field names (taxableValue/cgst/...); keep the
    # long forms so existing integrations and fixtures still populate.
    invoice.taxable_amount = _decimal(data, "taxableAmount", "taxable_amount", "taxableValue")
    invoice.cgst_amount = _decimal(data, "cgstAmount", "cgst_amount", "cgst")
    invoice.sgst_amount = _decimal(data, "sgstAmount", "sgst_amount", "sgst")
    invoice.igst_amount = _decimal(data, "igstAmount", "igst_amount", "igst")
    invoice.total_tax = _decimal(data, "totalTax", "total_tax")
    invoice.net_amount = _decimal(data, "netAmount", "net_amount", "totalAmount")
    invoice.uploaded_at = datetime.now(timezone.utc)
