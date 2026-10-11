import json
from datetime import date, datetime, timezone
from uuid import UUID

from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, UploadFile
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.pagination import paginate
from app.core.config import settings
from app.core.deps import Principal, company_admin_principal, current_employee
from app.db.session import get_db
from app.models import ApprovalStatus, Branch, Company, Employee, ExpenseCategory, Invoice
from app.schemas.common import DuplicateCheck, InvoiceDecision, InvoicePayload
from app.services.ai_extract import AiExtractError, ai_extract_configured, extract_invoice_fields
from app.services.invoice import find_duplicate, populate_invoice_fields
from app.services.notifications import notify_employee
from app.core.ratelimit import enforce
from app.services.storage import MAX_FILE_SIZE, public_url, save_upload, sniff_image_type

router = APIRouter()
admin_router = APIRouter()


@router.get("/extract/status")
async def extract_status(employee: Employee = Depends(current_employee)):
    """Lets the client know whether AI extraction is available before uploading."""
    _ = employee
    return {
        "available": ai_extract_configured(),
        "provider": "gemini" if ai_extract_configured() else None,
        "model": settings.gemini_model if ai_extract_configured() else None,
    }


@router.post("/extract")
async def extract_invoice(
    image: UploadFile = File(...),
    employee: Employee = Depends(current_employee),
):
    """AI vision extraction for Indian GST invoices (online path)."""
    await enforce(f"extract:{employee.id}", 30, 60, "Too many scans in a minute; please wait")
    data = await image.read(MAX_FILE_SIZE + 1)
    if not data:
        raise HTTPException(400, "Empty image upload")
    if len(data) > MAX_FILE_SIZE:
        raise HTTPException(413, "Image exceeds 15 MB")
    content_type = sniff_image_type(data[:16])
    if not content_type:
        raise HTTPException(400, "Unsupported image type. Use JPEG, PNG, WebP, or HEIC.")
    try:
        result = await extract_invoice_fields(data, mime_type=content_type)
    except AiExtractError as exc:
        raise HTTPException(exc.status_code, str(exc)) from exc
    return result


def summary(item: Invoice) -> dict:
    return {
        "id": item.id,
        "localIdempotencyKey": item.idempotency_key,
        "approvalStatus": item.approval_status,
        "adminRemarks": item.admin_remarks,
        "editedData": item.edited_data,
        "ocrData": item.ocr_data,
        "imageUrl": public_url(item.compressed_image_path),
        "thumbnailUrl": public_url(item.thumbnail_image_path),
        "uploadedAt": item.uploaded_at,
        "invoiceNumber": item.invoice_number,
        "gstin": item.gstin,
        "vendorName": item.vendor_name,
        "netAmount": item.net_amount,
    }


@router.post("/duplicate-check")
async def duplicate_check(
    body: DuplicateCheck,
    employee: Employee = Depends(current_employee),
    db: AsyncSession = Depends(get_db),
):
    match = await find_duplicate(db, employee.company_id, body.invoice_number, body.gstin)
    return {
        "isDuplicate": bool(match),
        "matchedInvoiceId": match.id if match else None,
        "message": "Possible duplicate" if match else "No duplicate found",
    }


@router.post("/upload", status_code=201)
async def upload(
    idempotency_key: str = Form(alias="idempotencyKey"),
    payload: str = Form(),
    original: UploadFile = File(),
    compressed: UploadFile = File(),
    thumbnail: UploadFile = File(),
    employee: Employee = Depends(current_employee),
    db: AsyncSession = Depends(get_db),
):
    existing = await db.scalar(
        select(Invoice).where(
            Invoice.company_id == employee.company_id,
            Invoice.idempotency_key == idempotency_key,
        )
    )
    if existing:
        return {"id": existing.id, "approvalStatus": existing.approval_status, "uploadedAt": existing.uploaded_at}
    try:
        parsed = InvoicePayload.model_validate(json.loads(payload))
    except (json.JSONDecodeError, ValueError) as exc:
        raise HTTPException(400, f"Invalid invoice payload: {exc}")
    if parsed.branch_id:
        branch = await db.scalar(
            select(Branch).where(
                Branch.id == parsed.branch_id, Branch.company_id == employee.company_id
            )
        )
        if not branch:
            raise HTTPException(400, "Branch does not belong to company")
    if parsed.category_id and not await db.scalar(
        select(ExpenseCategory.id).where(
            ExpenseCategory.id == parsed.category_id,
            ExpenseCategory.company_id == employee.company_id,
        )
    ):
        raise HTTPException(400, "Category does not belong to company")
    company = await db.get(Company, employee.company_id)
    if company.requires_gps and (parsed.latitude is None or parsed.longitude is None):
        raise HTTPException(400, "GPS coordinates are required")
    item = Invoice(
        company_id=employee.company_id,
        employee_id=employee.id,
        branch_id=parsed.branch_id,
        category_id=parsed.category_id,
        idempotency_key=idempotency_key,
        device_id=parsed.device_id,
        latitude=parsed.latitude,
        longitude=parsed.longitude,
        ocr_confidence=parsed.ocr_confidence,
        ocr_data=parsed.ocr_data,
        edited_data=parsed.edited_data,
        duplicate_override=parsed.duplicate_override,
        original_image_path="",
        compressed_image_path="",
        thumbnail_image_path="",
    )
    populate_invoice_fields(item, parsed)
    if company.duplicate_check_enabled and item.invoice_number and not parsed.duplicate_override:
        duplicate = await find_duplicate(
            db, employee.company_id, item.invoice_number, item.gstin
        )
        if duplicate:
            raise HTTPException(409, "Possible duplicate; set duplicateOverride to continue")
    try:
        paths = [
            await save_upload(original, employee.company_id, "original"),
            await save_upload(compressed, employee.company_id, "compressed"),
            await save_upload(thumbnail, employee.company_id, "thumbnail"),
        ]
    except ValueError as exc:
        raise HTTPException(400, str(exc))
    item.original_image_path, item.compressed_image_path, item.thumbnail_image_path = paths
    db.add(item)
    try:
        await db.commit()
    except IntegrityError:
        await db.rollback()
        existing = await db.scalar(
            select(Invoice).where(
                Invoice.company_id == employee.company_id,
                Invoice.idempotency_key == idempotency_key,
            )
        )
        if not existing:
            raise
        return {
            "id": existing.id,
            "approvalStatus": existing.approval_status,
            "uploadedAt": existing.uploaded_at,
        }
    await db.refresh(item)
    return {"id": item.id, "approvalStatus": item.approval_status, "uploadedAt": item.uploaded_at}


@router.get("/mine")
async def mine(
    page: int = Query(1, ge=1),
    page_size: int = Query(50, alias="pageSize", ge=1, le=100),
    updated_since: datetime | None = Query(None, alias="updatedSince"),
    employee: Employee = Depends(current_employee),
    db: AsyncSession = Depends(get_db),
):
    query = select(Invoice).where(
        Invoice.company_id == employee.company_id, Invoice.employee_id == employee.id
    )
    if updated_since:
        query = query.where(Invoice.updated_at >= updated_since)
    return await paginate(db, query.order_by(Invoice.updated_at.desc(), Invoice.id), page, page_size, summary)


@admin_router.get("")
async def list_invoices(
    status: ApprovalStatus | None = None,
    employee_id: UUID | None = Query(None, alias="employeeId"),
    branch_id: UUID | None = Query(None, alias="branchId"),
    date_from: date | None = Query(None, alias="dateFrom"),
    date_to: date | None = Query(None, alias="dateTo"),
    page: int = Query(1, ge=1),
    page_size: int = Query(50, alias="pageSize", ge=1, le=100),
    q: str | None = Query(None, max_length=100),
    principal: Principal = Depends(company_admin_principal),
    db: AsyncSession = Depends(get_db),
):
    query = select(Invoice).where(Invoice.company_id == principal.company_id)
    if status: query = query.where(Invoice.approval_status == status)
    if employee_id: query = query.where(Invoice.employee_id == employee_id)
    if branch_id: query = query.where(Invoice.branch_id == branch_id)
    if date_from: query = query.where(Invoice.invoice_date >= date_from)
    if date_to: query = query.where(Invoice.invoice_date <= date_to)
    if q:
        term = f"%{q.strip()}%"
        query = query.where(
            Invoice.invoice_number.ilike(term) | Invoice.vendor_name.ilike(term) | Invoice.gstin.ilike(term)
        )
    return await paginate(db, query.order_by(Invoice.uploaded_at.desc(), Invoice.id), page, page_size, summary)


@admin_router.get("/{invoice_id}")
async def invoice_detail(invoice_id: UUID, principal: Principal = Depends(company_admin_principal), db: AsyncSession = Depends(get_db)):
    item = await db.scalar(select(Invoice).where(Invoice.id == invoice_id, Invoice.company_id == principal.company_id))
    if not item: raise HTTPException(404, "Invoice not found")
    result = summary(item)
    result.update({"originalImageUrl": public_url(item.original_image_path), "latitude": item.latitude, "longitude": item.longitude, "deviceId": item.device_id})
    return result


async def _decide(invoice_id: UUID, status: ApprovalStatus, body: InvoiceDecision, principal: Principal, db: AsyncSession):
    item = await db.scalar(select(Invoice).where(Invoice.id == invoice_id, Invoice.company_id == principal.company_id))
    if not item: raise HTTPException(404, "Invoice not found")
    if status in (ApprovalStatus.rejected, ApprovalStatus.returned) and not body.remarks:
        raise HTTPException(400, "Remarks are required")
    item.approval_status, item.admin_remarks = status, body.remarks
    item.reviewed_at, item.reviewed_by = datetime.now(timezone.utc), principal.user.id
    labels = {
        ApprovalStatus.approved: ("billApproved", "Bill approved"),
        ApprovalStatus.rejected: ("billRejected", "Bill rejected"),
        ApprovalStatus.returned: ("billReturned", "Bill returned"),
    }
    notification_type, title = labels[status]
    await notify_employee(db, principal.company_id, item.employee_id, notification_type, title, f"{item.invoice_number or 'Invoice'} {status.value}", item.id)
    await db.commit()
    return summary(item)


@admin_router.post("/{invoice_id}/approve")
async def approve(invoice_id: UUID, body: InvoiceDecision, principal: Principal = Depends(company_admin_principal), db: AsyncSession = Depends(get_db)):
    return await _decide(invoice_id, ApprovalStatus.approved, body, principal, db)


@admin_router.post("/{invoice_id}/reject")
async def reject(invoice_id: UUID, body: InvoiceDecision, principal: Principal = Depends(company_admin_principal), db: AsyncSession = Depends(get_db)):
    return await _decide(invoice_id, ApprovalStatus.rejected, body, principal, db)


@admin_router.post("/{invoice_id}/return")
async def return_invoice(invoice_id: UUID, body: InvoiceDecision, principal: Principal = Depends(company_admin_principal), db: AsyncSession = Depends(get_db)):
    return await _decide(invoice_id, ApprovalStatus.returned, body, principal, db)
