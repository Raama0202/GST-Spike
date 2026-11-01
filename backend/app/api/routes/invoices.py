import asyncio
import csv
import io
import json
from datetime import date, datetime
from typing import Literal
from uuid import UUID

from fastapi import APIRouter, BackgroundTasks, Depends, File, Form, HTTPException, Query, Response, UploadFile
from pymongo import ReturnDocument
from pymongo.asynchronous.database import AsyncDatabase
from pymongo.errors import DuplicateKeyError

from app.core.config import settings
from app.core.deps import Principal, company_admin_principal, current_employee
from app.core.ratelimit import enforce
from app.db.mongo import as_utc, get_db, icontains, new_id, paginate, sid, utcnow
from app.models import ApprovalStatus
from app.schemas.common import BulkDecision, DuplicateCheck, InvoiceDecision, InvoiceEdit, InvoicePayload, InvoiceResubmit
from app.services.ai_extract import AiExtractError, ai_extract_configured, extract_invoice_fields
from app.services.audit import record_audit
from app.services.gstin_verify import check_invoice_gstin, check_json
from app.services.invoice import fields_from_data, find_duplicate, invoice_fields
from app.services.notifications import notify_employee
from app.services.party import CompanyIdentity
from app.services.reports import ist_string, ist_today
from app.services.storage import MAX_FILE_SIZE, discard, public_url, save_upload, sniff_image_type

router = APIRouter()
admin_router = APIRouter()

EXPORT_MAX_ROWS = 50_000
SORTS = {
    "uploaded_desc": [("uploaded_at", -1), ("_id", 1)],
    "uploaded_asc": [("uploaded_at", 1), ("_id", 1)],
    "amount_desc": [("net_amount", -1), ("_id", 1)],
    "amount_asc": [("net_amount", 1), ("_id", 1)],
}
SortKey = Literal["uploaded_desc", "uploaded_asc", "amount_desc", "amount_asc"]
GstinStatus = Literal["active", "cancelled", "suspended", "inactive", "not_found", "invalid_format", "problem"]
PROBLEM_STATUSES = ("cancelled", "suspended", "inactive", "not_found", "invalid_format")


@router.get("/extract/status")
async def extract_status(employee: dict = Depends(current_employee)):
    """Lets the client know whether AI extraction is available before uploading."""
    _ = employee
    return {
        "available": ai_extract_configured(),
        "provider": "gemini" if ai_extract_configured() else None,
        "model": settings.gemini_model if ai_extract_configured() else None,
        "handwritingSupported": ai_extract_configured(),
    }


@router.post("/extract")
async def extract_invoice(
    image: UploadFile = File(...),
    employee: dict = Depends(current_employee),
    db: AsyncDatabase = Depends(get_db),
):
    """AI vision extraction for Indian GST invoices, printed or handwritten (online path).
    The employee's own firm is excluded so the other party is returned as the vendor."""
    await enforce(f"extract:{employee['_id']}", 30, 60, "Too many scans in a minute; please wait")
    data = await image.read(MAX_FILE_SIZE + 1)
    if not data:
        raise HTTPException(400, "Empty image upload")
    if len(data) > MAX_FILE_SIZE:
        raise HTTPException(413, "Image exceeds 15 MB")
    content_type = sniff_image_type(data[:16])
    if not content_type:
        raise HTTPException(400, "Unsupported image type. Use JPEG, PNG, WebP, or HEIC.")
    company = await db.companies.find_one({"_id": employee["company_id"]})
    try:
        return await extract_invoice_fields(data, mime_type=content_type, identity=CompanyIdentity.from_company(company))
    except AiExtractError as exc:
        raise HTTPException(exc.status_code, str(exc)) from exc


def summary(item: dict) -> dict:
    return {
        "id": item["_id"],
        "localIdempotencyKey": item["idempotency_key"],
        "approvalStatus": item["approval_status"],
        "adminRemarks": item.get("admin_remarks"),
        "editedData": item.get("edited_data") or {},
        "ocrData": item.get("ocr_data") or {},
        "imageUrl": public_url(item.get("compressed_image_path")),
        "thumbnailUrl": public_url(item.get("thumbnail_image_path")),
        "uploadedAt": item.get("uploaded_at"),
        "updatedAt": item.get("updated_at"),
        "reviewedAt": item.get("reviewed_at"),
        "invoiceNumber": item.get("invoice_number"),
        "invoiceDate": item.get("invoice_date"),
        "gstin": item.get("gstin"),
        "vendorName": item.get("vendor_name"),
        "netAmount": item.get("net_amount"),
        "vendorIsCompany": bool(item.get("vendor_is_company")),
        "categoryId": item.get("category_id"),
        "gstinCheck": check_json(item.get("gstin_check")),
    }


def history(item: dict) -> list[dict]:
    events = item.get("history")
    if events is None:
        # Invoices from before the history field: rebuild what we know.
        events = [{"action": "uploaded", "at": item.get("uploaded_at")}]
        if item.get("approval_status") != ApprovalStatus.pending.value and item.get("reviewed_at"):
            events.append({"action": item["approval_status"], "remarks": item.get("admin_remarks"), "at": item["reviewed_at"]})
    return [
        {"action": e["action"], "remarks": e.get("remarks"), "byName": e.get("by_name"), "at": e.get("at")}
        for e in events
    ]


def _event(action: str, by_id: str | None, by_name: str | None, remarks: str | None = None) -> dict:
    return {"action": action, "by_id": by_id, "by_name": by_name, "remarks": remarks, "at": utcnow()}


def _upload_receipt(item: dict) -> dict:
    return {"id": item["_id"], "approvalStatus": item["approval_status"], "uploadedAt": item.get("uploaded_at")}


async def _validate_refs(db: AsyncDatabase, company_id: str, branch_id: str | None, category_id: str | None) -> None:
    if branch_id and not await db.branches.find_one({"_id": branch_id, "company_id": company_id}, {"_id": 1}):
        raise HTTPException(400, "Branch does not belong to company")
    if category_id and not await db.expense_categories.find_one({"_id": category_id, "company_id": company_id}, {"_id": 1}):
        raise HTTPException(400, "Category does not belong to company")


async def _company(db: AsyncDatabase, company_id: str) -> dict:
    company = await db.companies.find_one({"_id": company_id})
    if not company:
        raise HTTPException(403, "Company is not active")
    return company


@router.post("/duplicate-check")
async def duplicate_check(
    body: DuplicateCheck,
    employee: dict = Depends(current_employee),
    db: AsyncDatabase = Depends(get_db),
):
    match = await find_duplicate(db, employee["company_id"], body.invoice_number, body.gstin)
    return {
        "isDuplicate": bool(match),
        "matchedInvoiceId": match["_id"] if match else None,
        "message": "Possible duplicate" if match else "No duplicate found",
    }


@router.post("/upload", status_code=201)
async def upload(
    background: BackgroundTasks,
    idempotency_key: str = Form(alias="idempotencyKey", max_length=200),
    payload: str = Form(max_length=60_000),
    original: UploadFile = File(),
    compressed: UploadFile = File(),
    thumbnail: UploadFile = File(),
    employee: dict = Depends(current_employee),
    db: AsyncDatabase = Depends(get_db),
):
    company_id = employee["company_id"]
    key = {"company_id": company_id, "idempotency_key": idempotency_key}
    existing = await db.invoices.find_one(key)
    if existing:
        return _upload_receipt(existing)
    try:
        parsed = InvoicePayload.model_validate(json.loads(payload))
    except (json.JSONDecodeError, ValueError) as exc:
        raise HTTPException(400, f"Invalid invoice payload: {exc}")
    branch_id, category_id = sid(parsed.branch_id), sid(parsed.category_id)
    await _validate_refs(db, company_id, branch_id, category_id)
    company = await _company(db, company_id)
    if company.get("requires_gps") and (parsed.latitude is None or parsed.longitude is None):
        raise HTTPException(400, "GPS coordinates are required")
    fields = invoice_fields(parsed, company)
    if company.get("duplicate_check_enabled", True) and fields["invoice_number"] and not parsed.duplicate_override:
        if await find_duplicate(db, company_id, fields["invoice_number"], fields["gstin"]):
            raise HTTPException(409, "Possible duplicate; set duplicateOverride to continue")
    paths: list[str] = []
    try:
        for upload_file, kind in ((original, "original"), (compressed, "compressed"), (thumbnail, "thumbnail")):
            paths.append(await save_upload(upload_file, company_id, kind))
    except ValueError as exc:
        await discard(paths)
        raise HTTPException(400, str(exc))
    now = utcnow()
    item = {
        "_id": new_id(),
        **key,
        "employee_id": employee["_id"],
        "branch_id": branch_id or employee.get("branch_id"),
        "category_id": category_id,
        "device_id": parsed.device_id,
        "latitude": parsed.latitude,
        "longitude": parsed.longitude,
        "ocr_confidence": parsed.ocr_confidence,
        "ocr_data": parsed.ocr_data,
        "edited_data": parsed.edited_data,
        "duplicate_override": parsed.duplicate_override,
        **fields,
        "original_image_path": paths[0],
        "compressed_image_path": paths[1],
        "thumbnail_image_path": paths[2],
        "approval_status": ApprovalStatus.pending.value,
        "admin_remarks": None,
        "history": [_event("uploaded", employee["_id"], employee.get("name"))],
        "uploaded_at": now,
        "updated_at": now,
        "reviewed_at": None,
        "reviewed_by": None,
    }
    try:
        await db.invoices.insert_one(item)
    except DuplicateKeyError:
        await discard(paths)
        existing = await db.invoices.find_one(key)
        if not existing:
            raise
        return _upload_receipt(existing)
    if item.get("gstin"):
        background.add_task(check_invoice_gstin, db, item["_id"])
    return _upload_receipt(item)


@router.get("/mine")
async def mine(
    page: int = Query(1, ge=1),
    page_size: int = Query(50, alias="pageSize", ge=1, le=100),
    updated_since: datetime | None = Query(None, alias="updatedSince"),
    employee: dict = Depends(current_employee),
    db: AsyncDatabase = Depends(get_db),
):
    query: dict = {"company_id": employee["company_id"], "employee_id": employee["_id"]}
    if updated_since:
        query["updated_at"] = {"$gte": as_utc(updated_since)}
    return await paginate(db.invoices, query, [("updated_at", -1), ("_id", 1)], page, page_size, summary)


async def _own_invoice(db: AsyncDatabase, employee: dict, invoice_id: UUID) -> dict:
    item = await db.invoices.find_one({"_id": sid(invoice_id), "company_id": employee["company_id"], "employee_id": employee["_id"]})
    if not item:
        raise HTTPException(404, "Invoice not found")
    return item


@router.get("/{invoice_id}")
async def my_invoice(invoice_id: UUID, employee: dict = Depends(current_employee), db: AsyncDatabase = Depends(get_db)):
    item = await _own_invoice(db, employee, invoice_id)
    return {**summary(item), "history": history(item)}


@router.post("/{invoice_id}/resubmit")
async def resubmit(
    invoice_id: UUID,
    body: InvoiceResubmit,
    background: BackgroundTasks,
    employee: dict = Depends(current_employee),
    db: AsyncDatabase = Depends(get_db),
):
    item = await _own_invoice(db, employee, invoice_id)
    if item["approval_status"] != ApprovalStatus.returned.value:
        raise HTTPException(409, "Only bills returned for changes can be resubmitted")
    company_id = employee["company_id"]
    changes: dict = {}
    if "category_id" in body.model_fields_set:
        changes["category_id"] = sid(body.category_id)
        await _validate_refs(db, company_id, None, changes["category_id"])
    edited = {**(item.get("edited_data") or {}), **body.edited_data}
    fields = fields_from_data(item.get("ocr_data"), edited, await _company(db, company_id))
    fields.setdefault("vendor_is_company", False)
    now = utcnow()
    updated = await db.invoices.find_one_and_update(
        {"_id": item["_id"], "approval_status": ApprovalStatus.returned.value},
        {
            "$set": {**changes, **fields, "edited_data": edited, "approval_status": ApprovalStatus.pending.value, "updated_at": now},
            "$push": {"history": _event("resubmitted", employee["_id"], employee.get("name"), (body.note or "").strip() or None)},
        },
        return_document=ReturnDocument.AFTER,
    )
    if not updated:
        raise HTTPException(409, "This bill changed while you were editing it; refresh and try again")
    if updated.get("gstin") != item.get("gstin"):
        background.add_task(check_invoice_gstin, db, updated["_id"])
    return summary(updated)


# ── Company admin ────────────────────────────────────────────────────────────


def _admin_query(
    company_id: str,
    status: ApprovalStatus | None,
    employee_id: UUID | None,
    branch_id: UUID | None,
    category_id: UUID | None,
    date_from: date | None,
    date_to: date | None,
    q: str | None,
) -> dict:
    query: dict = {"company_id": company_id}
    if status:
        query["approval_status"] = status.value
    if employee_id:
        query["employee_id"] = sid(employee_id)
    if branch_id:
        query["branch_id"] = sid(branch_id)
    if category_id:
        query["category_id"] = sid(category_id)
    if date_from or date_to:
        query["invoice_date"] = {
            **({"$gte": date_from.isoformat()} if date_from else {}),
            **({"$lte": date_to.isoformat()} if date_to else {}),
        }
    if q and q.strip():
        term = icontains(q)
        query["$or"] = [{"invoice_number": term}, {"vendor_name": term}, {"gstin": term}]
    return query


class InvoiceFilters:
    def __init__(
        self,
        status: ApprovalStatus | None = None,
        employee_id: UUID | None = Query(None, alias="employeeId"),
        branch_id: UUID | None = Query(None, alias="branchId"),
        category_id: UUID | None = Query(None, alias="categoryId"),
        date_from: date | None = Query(None, alias="dateFrom"),
        date_to: date | None = Query(None, alias="dateTo"),
        q: str | None = Query(None, max_length=100),
        sort: SortKey = "uploaded_desc",
        gstin_status: GstinStatus | None = Query(None, alias="gstinStatus"),
    ):
        self.args = (status, employee_id, branch_id, category_id, date_from, date_to, q)
        self.sort = SORTS[sort]
        self.gstin_status = gstin_status

    def query(self, company_id: str) -> dict:
        query = _admin_query(company_id, *self.args)
        if self.gstin_status == "problem":
            query["gstin_check.status"] = {"$in": list(PROBLEM_STATUSES)}
        elif self.gstin_status:
            query["gstin_check.status"] = self.gstin_status
        return query


async def _lookups(db: AsyncDatabase, company_id: str, rows: list[dict]) -> tuple[dict, dict, dict]:
    employee_ids = list({row["employee_id"] for row in rows if row.get("employee_id")})
    employees = {
        e["_id"]: e
        async for e in db.employees.find({"_id": {"$in": employee_ids}}, {"name": 1, "employee_code": 1})
    } if employee_ids else {}
    branches = {b["_id"]: b["name"] async for b in db.branches.find({"company_id": company_id}, {"name": 1})}
    categories = {c["_id"]: c["name"] async for c in db.expense_categories.find({"company_id": company_id}, {"name": 1})}
    return employees, branches, categories


def _admin_item(row: dict, employees: dict, branches: dict, categories: dict) -> dict:
    employee = employees.get(row.get("employee_id")) or {}
    return {
        **summary(row),
        "employeeId": row.get("employee_id"),
        "employeeName": employee.get("name"),
        "employeeCode": employee.get("employee_code"),
        "branchId": row.get("branch_id"),
        "branchName": branches.get(row.get("branch_id")),
        "categoryName": categories.get(row.get("category_id")),
    }


async def _admin_detail(db: AsyncDatabase, company_id: str, item: dict) -> dict:
    lookups = await _lookups(db, company_id, [item])
    return {
        **_admin_item(item, *lookups),
        "originalImageUrl": public_url(item.get("original_image_path")),
        "latitude": item.get("latitude"),
        "longitude": item.get("longitude"),
        "deviceId": item.get("device_id"),
        "history": history(item),
    }


@admin_router.get("")
async def list_invoices(
    filters: InvoiceFilters = Depends(),
    page: int = Query(1, ge=1),
    page_size: int = Query(50, alias="pageSize", ge=1, le=100),
    principal: Principal = Depends(company_admin_principal),
    db: AsyncDatabase = Depends(get_db),
):
    result = await paginate(db.invoices, filters.query(principal.company_id), filters.sort, page, page_size, lambda row: row)
    lookups = await _lookups(db, principal.company_id, result["items"])
    result["items"] = [_admin_item(row, *lookups) for row in result["items"]]
    return result


EXPORT_COLUMNS = [
    ("Uploaded at (IST)", "uploaded"), ("Invoice date", "invoiceDate"), ("Invoice no.", "invoiceNumber"),
    ("Vendor", "vendorName"), ("Vendor GSTIN", "gstin"), ("Taxable", "taxable"), ("CGST", "cgst"),
    ("SGST", "sgst"), ("IGST", "igst"), ("Invoice value", "netAmount"), ("Status", "approvalStatus"),
    ("Remarks", "adminRemarks"), ("Employee", "employeeName"), ("Employee code", "employeeCode"),
    ("Branch", "branchName"), ("Category", "categoryName"), ("Supplier GSTIN status", "gstinStatus"),
    ("Invoice ID", "id"),
]


def _cell(value) -> object:
    if value is None:
        return ""
    if isinstance(value, str) and value[:1] in ("=", "+", "-", "@", "\t", "\r"):
        return "'" + value  # stop spreadsheets from evaluating user-entered text as a formula
    return value


def _export_rows(rows: list[dict], lookups: tuple[dict, dict, dict]) -> list[list]:
    out = []
    for row in rows:
        item = _admin_item(row, *lookups)
        item.update({
            "uploaded": ist_string(row.get("uploaded_at")),
            "taxable": row.get("taxable_amount"),
            "cgst": row.get("cgst_amount"),
            "sgst": row.get("sgst_amount"),
            "igst": row.get("igst_amount"),
            "gstinStatus": (row.get("gstin_check") or {}).get("status", "not checked" if row.get("gstin") else ""),
        })
        out.append([_cell(float(v) if hasattr(v, "quantize") else v) for v in (item.get(key) for _, key in EXPORT_COLUMNS)])
    return out


def _build_csv(rows: list[list]) -> bytes:
    buffer = io.StringIO()
    writer = csv.writer(buffer)
    writer.writerow([title for title, _ in EXPORT_COLUMNS])
    writer.writerows(rows)
    return ("\ufeff" + buffer.getvalue()).encode("utf-8")


def _build_xlsx(rows: list[list]) -> bytes:
    from openpyxl import Workbook

    workbook = Workbook(write_only=True)
    sheet = workbook.create_sheet("Invoices")
    sheet.append([title for title, _ in EXPORT_COLUMNS])
    for row in rows:
        sheet.append(row)
    buffer = io.BytesIO()
    workbook.save(buffer)
    return buffer.getvalue()


@admin_router.get("/export")
async def export_invoices(
    filters: InvoiceFilters = Depends(),
    format: Literal["csv", "xlsx"] = "csv",
    principal: Principal = Depends(company_admin_principal),
    db: AsyncDatabase = Depends(get_db),
):
    await enforce(f"invoice-export:{principal.company_id}", 10, 300, "Too many exports; please wait a few minutes")
    query = filters.query(principal.company_id)
    total = await db.invoices.count_documents(query)
    if total > EXPORT_MAX_ROWS:
        raise HTTPException(400, f"{total:,} bills match. Narrow the filters to at most {EXPORT_MAX_ROWS:,} rows.")
    projection = {"ocr_data": 0, "history": 0}
    rows = await db.invoices.find(query, projection).sort(filters.sort).to_list(length=EXPORT_MAX_ROWS)
    table = _export_rows(rows, await _lookups(db, principal.company_id, rows))
    if format == "xlsx":
        content = await asyncio.to_thread(_build_xlsx, table)
        media_type = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    else:
        content = await asyncio.to_thread(_build_csv, table)
        media_type = "text/csv; charset=utf-8"
    filename = f"invoices-{ist_today():%Y%m%d}.{format}"
    return Response(content, media_type=media_type, headers={"Content-Disposition": f'attachment; filename="{filename}"'})


DECISION_LABELS = {
    ApprovalStatus.approved: ("billApproved", "Bill approved"),
    ApprovalStatus.rejected: ("billRejected", "Bill rejected"),
    ApprovalStatus.returned: ("billReturned", "Bill returned"),
}


async def _admin_name(db: AsyncDatabase, principal: Principal) -> str | None:
    user = await db.users.find_one({"_id": principal.user.id}, {"name": 1, "email": 1})
    return (user or {}).get("name") or principal.user.email


async def _apply_decision(
    db: AsyncDatabase, principal: Principal, invoice_id: str, status: ApprovalStatus, remarks: str | None, by_name: str | None
) -> dict | None:
    """Sets the status unless the invoice already has it; returns the updated document or None."""
    now = utcnow()
    item = await db.invoices.find_one_and_update(
        {"_id": invoice_id, "company_id": principal.company_id, "approval_status": {"$ne": status.value}},
        {
            "$set": {
                "approval_status": status.value,
                "admin_remarks": remarks,
                "reviewed_at": now,
                "reviewed_by": principal.user.id,
                "updated_at": now,
            },
            "$push": {"history": _event(status.value, principal.user.id, by_name, remarks)},
        },
        return_document=ReturnDocument.AFTER,
    )
    if not item:
        return None
    notification_type, title = DECISION_LABELS[status]
    label = " · ".join(filter(None, [item.get("vendor_name"), item.get("invoice_number")])) or "Your bill"
    message = f"{label} was {status.value}."
    if remarks:
        message += f" Remarks: {remarks}"
    await notify_employee(db, principal.company_id, item["employee_id"], notification_type, title, message, item["_id"])
    return item


def _clean_remarks(status: ApprovalStatus, remarks: str | None) -> str | None:
    remarks = (remarks or "").strip() or None
    if status in (ApprovalStatus.rejected, ApprovalStatus.returned) and not remarks:
        raise HTTPException(400, "Remarks are required")
    return remarks


async def _decide(invoice_id: UUID, status: ApprovalStatus, body: InvoiceDecision, principal: Principal, db: AsyncDatabase):
    remarks = _clean_remarks(status, body.remarks)
    item = await _apply_decision(db, principal, sid(invoice_id), status, remarks, await _admin_name(db, principal))
    if not item:
        exists = await db.invoices.find_one({"_id": sid(invoice_id), "company_id": principal.company_id}, {"_id": 1})
        if not exists:
            raise HTTPException(404, "Invoice not found")
        raise HTTPException(409, f"Invoice is already {status.value}")
    label = item.get("invoice_number") or item.get("vendor_name") or item["_id"][:8]
    await record_audit(db, principal, f"invoice.{status.value}", "invoice", item["_id"], f"{status.value.capitalize()} bill {label}")
    return summary(item)


@admin_router.post("/bulk-decision")
async def bulk_decision(body: BulkDecision, principal: Principal = Depends(company_admin_principal), db: AsyncDatabase = Depends(get_db)):
    status = ApprovalStatus(body.status)
    remarks = _clean_remarks(status, body.remarks)
    by_name = await _admin_name(db, principal)
    updated = 0
    for invoice_id in dict.fromkeys(sid(i) for i in body.ids):
        if await _apply_decision(db, principal, invoice_id, status, remarks, by_name):
            updated += 1
    skipped = len(body.ids) - updated
    if updated:
        await record_audit(
            db, principal, "invoice.bulk_decision", "invoice", None,
            f"Marked {updated} bill{'s' if updated != 1 else ''} as {status.value}",
            details={"status": status.value, "updated": updated, "skipped": skipped},
        )
    return {"updated": updated, "skipped": skipped}


@admin_router.get("/{invoice_id}")
async def invoice_detail(invoice_id: UUID, principal: Principal = Depends(company_admin_principal), db: AsyncDatabase = Depends(get_db)):
    item = await db.invoices.find_one({"_id": sid(invoice_id), "company_id": principal.company_id})
    if not item:
        raise HTTPException(404, "Invoice not found")
    return await _admin_detail(db, principal.company_id, item)


@admin_router.post("/{invoice_id}/verify-gstin")
async def verify_invoice_gstin(
    invoice_id: UUID, principal: Principal = Depends(company_admin_principal), db: AsyncDatabase = Depends(get_db)
):
    """Re-check the supplier GSTIN with the GST portal now (bypasses the cache)."""
    item = await db.invoices.find_one({"_id": sid(invoice_id), "company_id": principal.company_id}, {"gstin": 1})
    if not item:
        raise HTTPException(404, "Invoice not found")
    if not item.get("gstin"):
        raise HTTPException(400, "This bill has no supplier GSTIN to verify")
    await enforce(f"gstin-verify:{principal.company_id}", 300, 3600, "Too many GSTIN checks; try again in a while")
    await check_invoice_gstin(db, item["_id"], refresh=True)
    return await _admin_detail(db, principal.company_id, await db.invoices.find_one({"_id": item["_id"]}))


@admin_router.patch("/{invoice_id}")
async def edit_invoice(
    invoice_id: UUID,
    body: InvoiceEdit,
    background: BackgroundTasks,
    principal: Principal = Depends(company_admin_principal),
    db: AsyncDatabase = Depends(get_db),
):
    company_id = principal.company_id
    item = await db.invoices.find_one({"_id": sid(invoice_id), "company_id": company_id})
    if not item:
        raise HTTPException(404, "Invoice not found")
    changes: dict = {}
    if "category_id" in body.model_fields_set:
        changes["category_id"] = sid(body.category_id)
        await _validate_refs(db, company_id, None, changes["category_id"])
    if body.edited_data:
        edited = {**(item.get("edited_data") or {}), **body.edited_data}
        fields = fields_from_data(item.get("ocr_data"), edited, await _company(db, company_id))
        fields.setdefault("vendor_is_company", False)
        changes.update(fields, edited_data=edited)
    if not changes:
        return await _admin_detail(db, company_id, item)
    changed = sorted(set(body.edited_data or {}) | ({"category"} if "category_id" in changes else set()))
    previous_gstin = item.get("gstin")
    item = await db.invoices.find_one_and_update(
        {"_id": item["_id"]},
        {
            "$set": {**changes, "updated_at": utcnow()},
            "$push": {"history": _event("edited", principal.user.id, await _admin_name(db, principal), ", ".join(changed))},
        },
        return_document=ReturnDocument.AFTER,
    )
    if "gstin" in changes and changes["gstin"] != previous_gstin:
        background.add_task(check_invoice_gstin, db, item["_id"])
    label = item.get("invoice_number") or item.get("vendor_name") or item["_id"][:8]
    await record_audit(db, principal, "invoice.edited", "invoice", item["_id"], f"Edited bill {label}: {', '.join(changed)}")
    return await _admin_detail(db, company_id, item)


@admin_router.post("/{invoice_id}/approve")
async def approve(invoice_id: UUID, body: InvoiceDecision, principal: Principal = Depends(company_admin_principal), db: AsyncDatabase = Depends(get_db)):
    return await _decide(invoice_id, ApprovalStatus.approved, body, principal, db)


@admin_router.post("/{invoice_id}/reject")
async def reject(invoice_id: UUID, body: InvoiceDecision, principal: Principal = Depends(company_admin_principal), db: AsyncDatabase = Depends(get_db)):
    return await _decide(invoice_id, ApprovalStatus.rejected, body, principal, db)


@admin_router.post("/{invoice_id}/return")
async def return_invoice(invoice_id: UUID, body: InvoiceDecision, principal: Principal = Depends(company_admin_principal), db: AsyncDatabase = Depends(get_db)):
    return await _decide(invoice_id, ApprovalStatus.returned, body, principal, db)
