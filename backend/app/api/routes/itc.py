"""Admin ITC: GSTR-2A/2B import, matching, and supplier reminders."""

from __future__ import annotations

import logging
from datetime import date, datetime, timezone
from uuid import UUID, uuid4

import anyio
from fastapi import APIRouter, BackgroundTasks, Depends, File, Form, HTTPException, Query, UploadFile
from pydantic import BaseModel, Field
from sqlalchemy import func, insert, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.deps import Principal, company_admin_principal
from app.core.ratelimit import enforce
from app.db.session import SessionLocal, get_db
from app.models import (
    Company,
    GstrImport,
    GstrImportSource,
    GstrImportStatus,
    GstrInwardRow,
    GstrReturnType,
    Invoice,
    ItcMatch,
    ItcMatchStatus,
    ReminderChannel,
    ReminderStatus,
    SupplierReminder,
)
from app.services.gstr_excel import parse_gstr_file
from app.services.gstr_portal import portal_api_configured
from app.services.itc_matcher import rebuild_matches
from app.services.reminders import (
    choose_channel,
    contact_from_invoice,
    mailto_link,
    reminder_message,
    whatsapp_link,
)

router = APIRouter()
logger = logging.getLogger(__name__)
MAX_IMPORT_BYTES = 25 * 1024 * 1024
MAX_MATCH_ROWS = 10000


class FollowUpUpdate(BaseModel):
    called: bool | None = None
    promised_by: date | None = Field(default=None, alias="promisedBy")
    resolved: bool | None = None

    model_config = {"populate_by_name": True}


def _parse_period(period: str) -> str:
    text = (period or "").strip()
    if len(text) != 7 or text[4] != "-":
        raise HTTPException(400, "period must be YYYY-MM")
    year, month = int(text[:4]), int(text[5:7])
    if month < 1 or month > 12:
        raise HTTPException(400, "Invalid month in period")
    return f"{year:04d}-{month:02d}"


def _return_type(value: str) -> GstrReturnType:
    cleaned = value.strip().upper().replace("GSTR-", "").replace("GSTR", "")
    if cleaned == "2A":
        return GstrReturnType.gstr_2a
    if cleaned == "2B":
        return GstrReturnType.gstr_2b
    raise HTTPException(400, "returnType must be 2A or 2B")


@router.get("/status")
async def itc_status(principal: Principal = Depends(company_admin_principal)):
    _ = principal
    return {
        "portalApiConfigured": portal_api_configured(),
        "excelUploadSupported": True,
        "whatsappMode": "wa.me deep link (manual send)",
    }


@router.get("/imports")
async def list_imports(
    period: str | None = None,
    principal: Principal = Depends(company_admin_principal),
    db: AsyncSession = Depends(get_db),
):
    stmt = select(GstrImport).where(GstrImport.company_id == principal.company_id)
    if period:
        stmt = stmt.where(GstrImport.period == _parse_period(period))
    items = (await db.scalars(stmt.order_by(GstrImport.created_at.desc()))).all()
    return {
        "items": [
            {
                "id": x.id,
                "period": x.period,
                "returnType": x.return_type.value,
                "source": x.source.value,
                "status": x.status.value,
                "rowCount": x.row_count,
                "originalFilename": x.original_filename,
                "errorMessage": x.error_message,
                "createdAt": x.created_at,
            }
            for x in items
        ]
    }


ROW_FIELDS = (
    "supplier_gstin", "supplier_name", "invoice_number", "invoice_date", "taxable_amount", "cgst_amount",
    "sgst_amount", "igst_amount", "net_amount", "place_of_supply", "document_type",
)
INSERT_BATCH = 1000


async def _store_rows(db: AsyncSession, record: GstrImport, rows: list[dict]) -> None:
    now = datetime.now(timezone.utc)
    for start in range(0, len(rows), INSERT_BATCH):
        await db.execute(
            insert(GstrInwardRow),
            [
                {
                    "id": uuid4(),
                    "company_id": record.company_id,
                    "import_id": record.id,
                    "period": record.period,
                    "return_type": record.return_type,
                    **{field: item.get(field) for field in ROW_FIELDS},
                    "raw_json": item.get("raw_json") or {},
                    "created_at": now,
                    "updated_at": now,
                }
                for item in rows[start:start + INSERT_BATCH]
            ],
        )


async def _finish_import_in_background(import_id: UUID, rows: list[dict]) -> None:
    async with SessionLocal() as db:
        record = await db.get(GstrImport, import_id)
        if not record:
            return
        try:
            await _store_rows(db, record, rows)
            record.row_count = len(rows)
            record.status = GstrImportStatus.ready
            await db.commit()
            await rebuild_matches(db, company_id=record.company_id, period=record.period, return_type=record.return_type)
        except Exception as exc:  # noqa: BLE001
            logger.exception("Background GSTR import %s failed", import_id)
            await db.rollback()
            record = await db.get(GstrImport, import_id)
            record.status = GstrImportStatus.failed
            record.error_message = str(exc)[:1000]
            await db.commit()


@router.post("/import")
async def import_gstr(
    background: BackgroundTasks,
    period: str = Form(...),
    return_type: str = Form(alias="returnType"),
    file: UploadFile = File(...),
    principal: Principal = Depends(company_admin_principal),
    db: AsyncSession = Depends(get_db),
):
    period_key = _parse_period(period)
    rtype = _return_type(return_type)
    await enforce(f"gstr-import:{principal.company_id}", 30, 3600, "Import limit reached; try again later")
    content = await file.read(MAX_IMPORT_BYTES + 1)
    if not content:
        raise HTTPException(400, "Empty file")
    if len(content) > MAX_IMPORT_BYTES:
        raise HTTPException(413, "File exceeds 25 MB; split it by month")

    try:
        rows = await anyio.to_thread.run_sync(parse_gstr_file, file.filename or "upload.csv", content)
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(400, f"Import failed: {exc}") from exc
    if len(rows) > settings.gstr_max_rows:
        raise HTTPException(413, f"File has {len(rows)} rows; the limit is {settings.gstr_max_rows}")

    record = GstrImport(
        company_id=principal.company_id,
        period=period_key,
        return_type=rtype,
        source=GstrImportSource.excel,
        status=GstrImportStatus.processing,
        uploaded_by=principal.user.id,
        original_filename=(file.filename or "")[:255] or None,
    )
    db.add(record)
    await db.flush()

    if len(rows) > settings.gstr_background_rows:
        record.row_count = len(rows)
        await db.commit()
        background.add_task(_finish_import_in_background, record.id, rows)
        return {
            "id": record.id,
            "period": period_key,
            "returnType": rtype.value,
            "rowCount": len(rows),
            "status": GstrImportStatus.processing.value,
            "matchCounts": None,
        }

    try:
        await _store_rows(db, record, rows)
        record.row_count = len(rows)
        record.status = GstrImportStatus.ready
        await db.commit()
    except Exception as exc:
        await db.rollback()
        logger.exception("GSTR import failed")
        raise HTTPException(400, f"Import failed: {exc}") from exc

    counts = await rebuild_matches(
        db,
        company_id=principal.company_id,
        period=period_key,
        return_type=rtype,
    )
    return {
        "id": record.id,
        "period": period_key,
        "returnType": rtype.value,
        "rowCount": record.row_count,
        "status": GstrImportStatus.ready.value,
        "matchCounts": counts,
    }


@router.post("/reconcile")
async def reconcile(
    period: str = Query(...),
    return_type: str = Query("2B", alias="returnType"),
    principal: Principal = Depends(company_admin_principal),
    db: AsyncSession = Depends(get_db),
):
    period_key = _parse_period(period)
    rtype = _return_type(return_type)
    counts = await rebuild_matches(
        db,
        company_id=principal.company_id,
        period=period_key,
        return_type=rtype,
    )
    return {"period": period_key, "returnType": rtype.value, "matchCounts": counts}


@router.get("/summary")
async def summary(
    period: str = Query(...),
    return_type: str = Query("2B", alias="returnType"),
    principal: Principal = Depends(company_admin_principal),
    db: AsyncSession = Depends(get_db),
):
    period_key = _parse_period(period)
    rtype = _return_type(return_type)
    rows = (
        await db.execute(
            select(ItcMatch.status, func.count())
            .where(
                ItcMatch.company_id == principal.company_id,
                ItcMatch.period == period_key,
                ItcMatch.return_type == rtype,
            )
            .group_by(ItcMatch.status)
        )
    ).all()
    counts = {status.value: 0 for status in ItcMatchStatus}
    for status, count in rows:
        counts[status.value] = count
    return {"period": period_key, "returnType": rtype.value, "counts": counts}


@router.get("/matches")
async def list_matches(
    period: str = Query(...),
    return_type: str = Query("2B", alias="returnType"),
    status: str | None = None,
    principal: Principal = Depends(company_admin_principal),
    db: AsyncSession = Depends(get_db),
):
    period_key = _parse_period(period)
    rtype = _return_type(return_type)
    stmt = select(ItcMatch).where(
        ItcMatch.company_id == principal.company_id,
        ItcMatch.period == period_key,
        ItcMatch.return_type == rtype,
    )
    if status:
        try:
            stmt = stmt.where(ItcMatch.status == ItcMatchStatus(status))
        except ValueError as exc:
            raise HTTPException(400, "Invalid status") from exc
    matches = (await db.scalars(stmt.order_by(ItcMatch.created_at.desc()).limit(MAX_MATCH_ROWS))).all()

    invoice_ids = [m.invoice_id for m in matches if m.invoice_id]
    row_ids = [m.gstr_row_id for m in matches if m.gstr_row_id]
    invoices = {
        i.id: i
        for i in (
            await db.scalars(select(Invoice).where(Invoice.id.in_(invoice_ids)))
        ).all()
    } if invoice_ids else {}
    portal = {
        r.id: r
        for r in (
            await db.scalars(select(GstrInwardRow).where(GstrInwardRow.id.in_(row_ids)))
        ).all()
    } if row_ids else {}

    items = []
    for match in matches:
        inv = invoices.get(match.invoice_id) if match.invoice_id else None
        prow = portal.get(match.gstr_row_id) if match.gstr_row_id else None
        phone, email = (None, None)
        if inv:
            phone, email = contact_from_invoice(inv)
        items.append(
            {
                "id": match.id,
                "status": match.status.value,
                "amountDelta": match.amount_delta,
                "notes": match.notes,
                "invoice": None
                if not inv
                else {
                    "id": inv.id,
                    "vendorName": inv.vendor_name,
                    "gstin": inv.gstin,
                    "invoiceNumber": inv.invoice_number,
                    "invoiceDate": inv.invoice_date,
                    "netAmount": inv.net_amount,
                    "supplierPhone": phone,
                    "supplierEmail": email,
                },
                "portalRow": None
                if not prow
                else {
                    "id": prow.id,
                    "supplierName": prow.supplier_name,
                    "supplierGstin": prow.supplier_gstin,
                    "invoiceNumber": prow.invoice_number,
                    "invoiceDate": prow.invoice_date,
                    "netAmount": prow.net_amount,
                },
            }
        )
    return {"items": items}


@router.get("/matches/export")
async def export_matches(
    period: str = Query(...),
    return_type: str = Query("2B", alias="returnType"),
    status: str | None = Query("missing_in_2b"),
    principal: Principal = Depends(company_admin_principal),
    db: AsyncSession = Depends(get_db),
):
    if status and status.strip().lower() == "all":
        status = None
    data = await list_matches(period, return_type, status, principal, db)
    lines = [
        "status,vendor,gstin,invoiceNumber,invoiceDate,netAmount,portalInvoice,portalAmount,notes"
    ]
    for item in data["items"]:
        inv = item.get("invoice") or {}
        portal = item.get("portalRow") or {}
        lines.append(
            ",".join(
                [
                    item.get("status") or "",
                    _csv(inv.get("vendorName")),
                    _csv(inv.get("gstin")),
                    _csv(inv.get("invoiceNumber")),
                    _csv(inv.get("invoiceDate")),
                    _csv(inv.get("netAmount")),
                    _csv(portal.get("invoiceNumber")),
                    _csv(portal.get("netAmount")),
                    _csv(item.get("notes")),
                ]
            )
        )
    return {"csv": "\n".join(lines), "filename": f"itc_{period}_{status or 'all'}.csv"}


def _csv(value) -> str:
    if value is None:
        return ""
    text = str(value).replace('"', '""')
    if "," in text or '"' in text:
        return f'"{text}"'
    return text


@router.post("/matches/{match_id}/remind")
async def remind_one(
    match_id: UUID,
    principal: Principal = Depends(company_admin_principal),
    db: AsyncSession = Depends(get_db),
):
    match = await db.get(ItcMatch, match_id)
    if not match or match.company_id != principal.company_id:
        raise HTTPException(404, "Match not found")
    if not match.invoice_id:
        raise HTTPException(400, "No book invoice to remind against")
    invoice = await db.get(Invoice, match.invoice_id)
    if not invoice:
        raise HTTPException(404, "Invoice not found")
    company = await db.get(Company, principal.company_id)
    return await _create_reminder(db, principal, company, match, invoice)


@router.post("/remind-missing")
async def remind_missing(
    period: str = Query(...),
    return_type: str = Query("2B", alias="returnType"),
    principal: Principal = Depends(company_admin_principal),
    db: AsyncSession = Depends(get_db),
):
    period_key = _parse_period(period)
    rtype = _return_type(return_type)
    matches = (
        await db.scalars(
            select(ItcMatch).where(
                ItcMatch.company_id == principal.company_id,
                ItcMatch.period == period_key,
                ItcMatch.return_type == rtype,
                ItcMatch.status.in_([ItcMatchStatus.missing_in_2b, ItcMatchStatus.mismatch]),
                ItcMatch.invoice_id.is_not(None),
            )
        )
    ).all()
    company = await db.get(Company, principal.company_id)
    invoice_ids = {m.invoice_id for m in matches}
    invoices = {
        i.id: i for i in (await db.scalars(select(Invoice).where(Invoice.id.in_(invoice_ids)))).all()
    } if invoice_ids else {}
    results = []
    for match in matches:
        invoice = invoices.get(match.invoice_id)
        if not invoice:
            continue
        results.append(await _create_reminder(db, principal, company, match, invoice, commit=False))
    await db.commit()
    return {"count": len(results), "items": results}


async def _create_reminder(
    db: AsyncSession,
    principal: Principal,
    company: Company | None,
    match: ItcMatch,
    invoice: Invoice,
    *,
    commit: bool = True,
) -> dict:
    phone, email = contact_from_invoice(invoice)
    channel = choose_channel(phone, email)
    message = reminder_message(invoice, company.name if company else None)
    status = ReminderStatus.sent_link if channel != ReminderChannel.manual else ReminderStatus.manual_followup
    reminder = SupplierReminder(
        company_id=principal.company_id,
        invoice_id=invoice.id,
        itc_match_id=match.id,
        channel=channel,
        status=status,
        contact_phone=phone,
        contact_email=email,
        message_preview=message,
        created_by=principal.user.id,
    )
    db.add(reminder)
    if commit:
        await db.commit()
        await db.refresh(reminder)
    else:
        await db.flush()

    payload = {
        "id": reminder.id,
        "channel": channel.value,
        "status": status.value,
        "contactPhone": phone,
        "contactEmail": email,
        "message": message,
        "whatsappUrl": whatsapp_link(phone, message) if phone else None,
        "mailtoUrl": mailto_link(
            email,
            f"GSTR filing reminder — invoice {invoice.invoice_number or ''}",
            message,
        )
        if email
        else None,
        "invoiceId": invoice.id,
        "matchId": match.id,
    }
    return payload


@router.get("/reminders")
async def list_reminders(
    status: str | None = Query("manual_followup"),
    principal: Principal = Depends(company_admin_principal),
    db: AsyncSession = Depends(get_db),
):
    stmt = select(SupplierReminder).where(SupplierReminder.company_id == principal.company_id)
    if status:
        try:
            stmt = stmt.where(SupplierReminder.status == ReminderStatus(status))
        except ValueError as exc:
            raise HTTPException(400, "Invalid reminder status") from exc
    items = (await db.scalars(stmt.order_by(SupplierReminder.created_at.desc()))).all()
    return {
        "items": [
            {
                "id": r.id,
                "invoiceId": r.invoice_id,
                "matchId": r.itc_match_id,
                "channel": r.channel.value,
                "status": r.status.value,
                "contactPhone": r.contact_phone,
                "contactEmail": r.contact_email,
                "messagePreview": r.message_preview,
                "called": r.called,
                "promisedBy": r.promised_by,
                "resolvedAt": r.resolved_at,
                "createdAt": r.created_at,
            }
            for r in items
        ]
    }


@router.patch("/reminders/{reminder_id}")
async def update_reminder(
    reminder_id: UUID,
    body: FollowUpUpdate,
    principal: Principal = Depends(company_admin_principal),
    db: AsyncSession = Depends(get_db),
):
    reminder = await db.get(SupplierReminder, reminder_id)
    if not reminder or reminder.company_id != principal.company_id:
        raise HTTPException(404, "Reminder not found")
    if body.called is not None:
        reminder.called = body.called
    if body.promised_by is not None:
        reminder.promised_by = body.promised_by
    if body.resolved:
        reminder.status = ReminderStatus.resolved
        reminder.resolved_at = datetime.now(timezone.utc)
    await db.commit()
    return {"id": reminder.id, "status": reminder.status.value, "called": reminder.called}
