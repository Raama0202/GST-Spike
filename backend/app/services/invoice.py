from datetime import datetime
from decimal import Decimal, InvalidOperation
from typing import Any

from pymongo.asynchronous.database import AsyncDatabase

from app.schemas.common import InvoicePayload
from app.services import gstin as gst
from app.services.party import CompanyIdentity


def _decimal(data: dict, *keys: str) -> Decimal | None:
    value = next((data[key] for key in keys if data.get(key) not in (None, "")), None)
    try:
        return Decimal(str(value)).quantize(Decimal("0.01")) if value is not None else None
    except (InvalidOperation, ValueError):
        return None


def _iso_date(raw: Any) -> str | None:
    if not raw:
        return None
    try:
        return datetime.fromisoformat(str(raw)).date().isoformat()
    except ValueError:
        return None


async def find_duplicate(db: AsyncDatabase, company_id: str, invoice_number: str, gstin: str | None) -> dict | None:
    query: dict = {"company_id": company_id, "invoice_number": invoice_number}
    if gstin:
        query["gstin"] = gstin
    return await db.invoices.find_one(query, {"_id": 1})


def invoice_fields(payload: InvoicePayload, company: dict | None = None) -> dict[str, Any]:
    return fields_from_data(payload.ocr_data, payload.edited_data, company)


def fields_from_data(ocr_data: dict | None, edited_data: dict | None, company: dict | None = None) -> dict[str, Any]:
    """Denormalised columns for search, duplicates and ITC, from OCR data overlaid with user edits."""
    ocr, edited = ocr_data or {}, edited_data or {}
    data = {**ocr, **edited}
    gstin = gst.compact(data.get("gstin")) or None

    def amount(*keys: str) -> Decimal | None:
        # An edit under any alias beats the scan, even if the scan used a different alias.
        return _decimal(edited if any(k in edited for k in keys) else ocr, *keys)

    fields = {
        "invoice_number": (str(data.get("invoiceNumber") or data.get("invoice_number") or "").strip() or None),
        "gstin": gstin,
        "vendor_name": data.get("vendorName") or data.get("vendor_name"),
        "invoice_date": _iso_date(data.get("invoiceDate") or data.get("invoice_date")),
        # Clients send the shorter field names (taxableValue/cgst/...); keep the
        # long forms so existing integrations and fixtures still populate.
        "taxable_amount": amount("taxableAmount", "taxable_amount", "taxableValue"),
        "cgst_amount": amount("cgstAmount", "cgst_amount", "cgst"),
        "sgst_amount": amount("sgstAmount", "sgst_amount", "sgst"),
        "igst_amount": amount("igstAmount", "igst_amount", "igst"),
        "total_tax": amount("totalTax", "total_tax"),
        "net_amount": amount("netAmount", "net_amount", "totalAmount"),
    }
    identity = CompanyIdentity.from_company(company)
    if not identity.empty and identity.owns(fields["vendor_name"], fields["gstin"]):
        fields["vendor_is_company"] = True
    return fields
