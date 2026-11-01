"""Admin ITC: GSTR-2A/2B import, matching, and supplier reminders."""

from __future__ import annotations

import logging
from datetime import date, timedelta
from uuid import UUID

import anyio
from fastapi import APIRouter, BackgroundTasks, Depends, File, Form, HTTPException, Query, UploadFile
from pydantic import BaseModel, Field
from pymongo import ReturnDocument
from pymongo.asynchronous.database import AsyncDatabase

from app.core.config import settings
from app.core.deps import Principal, company_admin_principal
from app.core.ratelimit import enforce
from app.db.mongo import get_database, get_db, new_id, sid, utcnow
from app.models import (
    GstrImportSource,
    GstrImportStatus,
    GstrReturnType,
    ItcMatchStatus,
    ReminderChannel,
    ReminderStatus,
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
STUCK_IMPORT_MINUTES = 30


class FollowUpUpdate(BaseModel):
    called: bool | None = None
    promised_by: date | None = Field(default=None, alias="promisedBy")
    resolved: bool | None = None

    model_config = {"populate_by_name": True}


def _parse_period(period: str) -> str:
    text = (period or "").strip()
    if len(text) != 7 or text[4] != "-" or not (text[:4].isdigit() and text[5:].isdigit()):
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
    db: AsyncDatabase = Depends(get_db),
):
    await _fail_stuck_imports(db, principal.company_id)
    query: dict = {"company_id": principal.company_id}
    if period:
        query["period"] = _parse_period(period)
    items = await db.gstr_imports.find(query).sort([("created_at", -1)]).limit(500).to_list(500)
    return {
        "items": [
            {
                "id": x["_id"],
                "period": x["period"],
                "returnType": x["return_type"],
                "source": x["source"],
                "status": x["status"],
                "rowCount": x.get("row_count", 0),
                "originalFilename": x.get("original_filename"),
                "errorMessage": x.get("error_message"),
                "createdAt": x.get("created_at"),
            }
            for x in items
        ]
    }


ROW_FIELDS = (
    "supplier_gstin", "supplier_name", "invoice_number", "invoice_date", "taxable_amount", "cgst_amount",
    "sgst_amount", "igst_amount", "net_amount", "place_of_supply", "document_type",
)
INSERT_BATCH = 1000


async def _store_rows(db: AsyncDatabase, record: dict, rows: list[dict]) -> None:
    now = utcnow()
    for start in range(0, len(rows), INSERT_BATCH):
        await db.gstr_inward_rows.insert_many(
            [
                {
                    "_id": new_id(),
                    "company_id": record["company_id"],
                    "import_id": record["_id"],
                    "period": record["period"],
                    "return_type": record["return_type"],
                    **{field: item.get(field) for field in ROW_FIELDS},
                    "raw_json": item.get("raw_json") or {},
                    "created_at": now,
                }
                for item in rows[start:start + INSERT_BATCH]
            ],
            ordered=False,
        )


async def _set_import(db: AsyncDatabase, import_id: str, **changes) -> None:
    await db.gstr_imports.update_one({"_id": import_id}, {"$set": {**changes, "updated_at": utcnow()}})


async def _replace_previous(db: AsyncDatabase, record: dict) -> None:
    """A new upload for a period/return replaces earlier ones instead of doubling every row."""
    scope = {"company_id": record["company_id"], "period": record["period"], "return_type": record["return_type"]}
    old = [
        x["_id"]
        async for x in db.gstr_imports.find(
            {**scope, "_id": {"$ne": record["_id"]}, "status": {"$ne": GstrImportStatus.processing.value}}, {"_id": 1}
        )
    ]
    await db.gstr_inward_rows.delete_many({**scope, "import_id": {"$ne": record["_id"]}})
    if old:
        await db.gstr_imports.delete_many({"_id": {"$in": old}})


async def _fail_stuck_imports(db: AsyncDatabase, company_id: str) -> None:
    """Background imports lost to a restart or deploy would otherwise say "processing" forever."""
    cutoff = utcnow() - timedelta(minutes=STUCK_IMPORT_MINUTES)
    async for stuck in db.gstr_imports.find(
        {"company_id": company_id, "status": GstrImportStatus.processing.value, "updated_at": {"$lt": cutoff}}, {"_id": 1}
    ):
        await db.gstr_inward_rows.delete_many({"import_id": stuck["_id"]})
        await _set_import(
            db, stuck["_id"], status=GstrImportStatus.failed.value,
            error_message="The import was interrupted (server restart). Please upload the file again.",
        )


async def _finish_import_in_background(import_id: str, rows: list[dict]) -> None:
    db = get_database()
    record = await db.gstr_imports.find_one({"_id": import_id})
    if not record:
        return
    try:
        await _store_rows(db, record, rows)
        await _replace_previous(db, record)
        await _set_import(db, import_id, row_count=len(rows), status=GstrImportStatus.ready.value)
        await rebuild_matches(
            db, company_id=record["company_id"], period=record["period"], return_type=GstrReturnType(record["return_type"])
        )
    except Exception as exc:  # noqa: BLE001
        logger.exception("Background GSTR import %s failed", import_id)
        await db.gstr_inward_rows.delete_many({"import_id": import_id})
        await _set_import(db, import_id, status=GstrImportStatus.failed.value, error_message=str(exc)[:1000])


@router.post("/import")
async def import_gstr(
    background: BackgroundTasks,
    period: str = Form(...),
    return_type: str = Form(alias="returnType"),
    file: UploadFile = File(...),
    principal: Principal = Depends(company_admin_principal),
    db: AsyncDatabase = Depends(get_db),
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

    now = utcnow()
    record = {
        "_id": new_id(),
        "company_id": principal.company_id,
        "period": period_key,
        "return_type": rtype.value,
        "source": GstrImportSource.excel.value,
        "status": GstrImportStatus.processing.value,
        "row_count": len(rows),
        "uploaded_by": principal.user.id,
        "original_filename": (file.filename or "")[:255] or None,
        "error_message": None,
        "created_at": now,
        "updated_at": now,
    }
    await db.gstr_imports.insert_one(record)

    if len(rows) > settings.gstr_background_rows:
        background.add_task(_finish_import_in_background, record["_id"], rows)
        return {
            "id": record["_id"],
            "period": period_key,
            "returnType": rtype.value,
            "rowCount": len(rows),
            "status": GstrImportStatus.processing.value,
            "matchCounts": None,
        }

    try:
        await _store_rows(db, record, rows)
        await _replace_previous(db, record)
        await _set_import(db, record["_id"], status=GstrImportStatus.ready.value)
    except Exception as exc:
        logger.exception("GSTR import failed")
        await db.gstr_inward_rows.delete_many({"import_id": record["_id"]})
        await db.gstr_imports.delete_one({"_id": record["_id"]})
        raise HTTPException(400, f"Import failed: {exc}") from exc

    counts = await rebuild_matches(db, company_id=principal.company_id, period=period_key, return_type=rtype)
    return {
        "id": record["_id"],
        "period": period_key,
        "returnType": rtype.value,
        "rowCount": len(rows),
        "status": GstrImportStatus.ready.value,
        "matchCounts": counts,
    }


@router.delete("/imports/{import_id}", status_code=204)
async def delete_import(
    import_id: UUID,
    principal: Principal = Depends(company_admin_principal),
    db: AsyncDatabase = Depends(get_db),
):
    record = await db.gstr_imports.find_one({"_id": sid(import_id), "company_id": principal.company_id})
    if not record:
        raise HTTPException(404, "Import not found")
    if record["status"] == GstrImportStatus.processing.value:
        raise HTTPException(409, "This import is still processing; try again in a minute")
    await db.gstr_inward_rows.delete_many({"import_id": record["_id"]})
    await db.gstr_imports.delete_one({"_id": record["_id"]})
    await rebuild_matches(
        db, company_id=principal.company_id, period=record["period"], return_type=GstrReturnType(record["return_type"])
    )


@router.post("/reconcile")
async def reconcile(
    period: str = Query(...),
    return_type: str = Query("2B", alias="returnType"),
    principal: Principal = Depends(company_admin_principal),
    db: AsyncDatabase = Depends(get_db),
):
    period_key = _parse_period(period)
    rtype = _return_type(return_type)
    counts = await rebuild_matches(db, company_id=principal.company_id, period=period_key, return_type=rtype)
    return {"period": period_key, "returnType": rtype.value, "matchCounts": counts}


@router.get("/summary")
async def summary(
    period: str = Query(...),
    return_type: str = Query("2B", alias="returnType"),
    principal: Principal = Depends(company_admin_principal),
    db: AsyncDatabase = Depends(get_db),
):
    period_key = _parse_period(period)
    rtype = _return_type(return_type)
    cursor = await db.itc_matches.aggregate([
        {"$match": {"company_id": principal.company_id, "period": period_key, "return_type": rtype.value}},
        {"$group": {"_id": "$status", "count": {"$sum": 1}}},
    ])
    counts = {status.value: 0 for status in ItcMatchStatus}
    async for row in cursor:
        counts[row["_id"]] = row["count"]
    return {"period": period_key, "returnType": rtype.value, "counts": counts}


@router.get("/matches")
async def list_matches(
    period: str = Query(...),
    return_type: str = Query("2B", alias="returnType"),
    status: str | None = None,
    principal: Principal = Depends(company_admin_principal),
    db: AsyncDatabase = Depends(get_db),
):
    period_key = _parse_period(period)
    rtype = _return_type(return_type)
    query: dict = {"company_id": principal.company_id, "period": period_key, "return_type": rtype.value}
    if status:
        try:
            query["status"] = ItcMatchStatus(status).value
        except ValueError as exc:
            raise HTTPException(400, "Invalid status") from exc
    matches = await db.itc_matches.find(query).sort([("created_at", -1)]).limit(MAX_MATCH_ROWS).to_list(MAX_MATCH_ROWS)

    invoice_ids = [m["invoice_id"] for m in matches if m.get("invoice_id")]
    row_ids = [m["gstr_row_id"] for m in matches if m.get("gstr_row_id")]
    invoices = {i["_id"]: i async for i in db.invoices.find({"_id": {"$in": invoice_ids}})} if invoice_ids else {}
    portal = {r["_id"]: r async for r in db.gstr_inward_rows.find({"_id": {"$in": row_ids}})} if row_ids else {}

    items = []
    for match in matches:
        inv = invoices.get(match.get("invoice_id"))
        prow = portal.get(match.get("gstr_row_id"))
        phone, email = contact_from_invoice(inv) if inv else (None, None)
        items.append(
            {
                "id": match["_id"],
                "status": match["status"],
                "amountDelta": match.get("amount_delta"),
                "notes": match.get("notes"),
                "invoice": None
                if not inv
                else {
                    "id": inv["_id"],
                    "vendorName": inv.get("vendor_name"),
                    "gstin": inv.get("gstin"),
                    "invoiceNumber": inv.get("invoice_number"),
                    "invoiceDate": inv.get("invoice_date"),
                    "netAmount": inv.get("net_amount"),
                    "supplierPhone": phone,
                    "supplierEmail": email,
                },
                "portalRow": None
                if not prow
                else {
                    "id": prow["_id"],
                    "supplierName": prow.get("supplier_name"),
                    "supplierGstin": prow.get("supplier_gstin"),
                    "invoiceNumber": prow.get("invoice_number"),
                    "invoiceDate": prow.get("invoice_date"),
                    "netAmount": prow.get("net_amount"),
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
    db: AsyncDatabase = Depends(get_db),
):
    if status and status.strip().lower() == "all":
        status = None
    data = await list_matches(period, return_type, status, principal, db)
    lines = [
        "status,vendor,gstin,invoiceNumber,invoiceDate,invoiceValue,portalInvoice,portalInvoiceValue,notes"
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
    if isinstance(value, str) and text[:1] in ("=", "+", "-", "@"):
        text = "'" + text
    if "," in text or '"' in text or "\n" in text:
        return f'"{text}"'
    return text


@router.post("/matches/{match_id}/remind")
async def remind_one(
    match_id: UUID,
    principal: Principal = Depends(company_admin_principal),
    db: AsyncDatabase = Depends(get_db),
):
    match = await db.itc_matches.find_one({"_id": sid(match_id), "company_id": principal.company_id})
    if not match:
        raise HTTPException(404, "Match not found")
    if not match.get("invoice_id"):
        raise HTTPException(400, "No book invoice to remind against")
    invoice = await db.invoices.find_one({"_id": match["invoice_id"], "company_id": principal.company_id})
    if not invoice:
        raise HTTPException(404, "Invoice not found")
    company = await db.companies.find_one({"_id": principal.company_id}, {"name": 1})
    return await _create_reminder(db, principal, company, match, invoice)


@router.post("/remind-missing")
async def remind_missing(
    period: str = Query(...),
    return_type: str = Query("2B", alias="returnType"),
    principal: Principal = Depends(company_admin_principal),
    db: AsyncDatabase = Depends(get_db),
):
    period_key = _parse_period(period)
    rtype = _return_type(return_type)
    matches = await db.itc_matches.find({
        "company_id": principal.company_id,
        "period": period_key,
        "return_type": rtype.value,
        "status": {"$in": [ItcMatchStatus.missing_in_2b.value, ItcMatchStatus.mismatch.value]},
        "invoice_id": {"$ne": None},
    }).to_list(None)
    company = await db.companies.find_one({"_id": principal.company_id}, {"name": 1})
    invoice_ids = list({m["invoice_id"] for m in matches})
    invoices = {i["_id"]: i async for i in db.invoices.find({"_id": {"$in": invoice_ids}})} if invoice_ids else {}
    already = {
        r["invoice_id"]
        async for r in db.supplier_reminders.find(
            {"company_id": principal.company_id, "invoice_id": {"$in": invoice_ids}, "status": {"$ne": ReminderStatus.resolved.value}},
            {"invoice_id": 1},
        )
    } if invoice_ids else set()
    results = []
    skipped = 0
    for match in matches:
        invoice = invoices.get(match["invoice_id"])
        if not invoice:
            continue
        if invoice["_id"] in already:
            skipped += 1
            continue
        already.add(invoice["_id"])
        results.append(await _create_reminder(db, principal, company, match, invoice))
    return {"count": len(results), "skipped": skipped, "items": results}


async def _create_reminder(
    db: AsyncDatabase,
    principal: Principal,
    company: dict | None,
    match: dict,
    invoice: dict,
) -> dict:
    phone, email = contact_from_invoice(invoice)
    channel = choose_channel(phone, email)
    message = reminder_message(invoice, company["name"] if company else None)
    status = ReminderStatus.sent_link if channel != ReminderChannel.manual else ReminderStatus.manual_followup
    reminder = {
        "_id": new_id(),
        "company_id": principal.company_id,
        "invoice_id": invoice["_id"],
        "itc_match_id": match["_id"],
        "channel": channel.value,
        "status": status.value,
        "contact_phone": phone,
        "contact_email": email,
        "message_preview": message,
        "called": False,
        "promised_by": None,
        "resolved_at": None,
        "created_by": principal.user.id,
        "created_at": utcnow(),
    }
    await db.supplier_reminders.insert_one(reminder)
    return {
        "id": reminder["_id"],
        "channel": channel.value,
        "status": status.value,
        "contactPhone": phone,
        "contactEmail": email,
        "message": message,
        "whatsappUrl": whatsapp_link(phone, message) if phone else None,
        "mailtoUrl": mailto_link(email, f"GSTR filing reminder — invoice {invoice.get('invoice_number') or ''}", message)
        if email
        else None,
        "invoiceId": invoice["_id"],
        "matchId": match["_id"],
    }


@router.get("/reminders")
async def list_reminders(
    status: str | None = Query("manual_followup"),
    principal: Principal = Depends(company_admin_principal),
    db: AsyncDatabase = Depends(get_db),
):
    query: dict = {"company_id": principal.company_id}
    if status:
        try:
            query["status"] = ReminderStatus(status).value
        except ValueError as exc:
            raise HTTPException(400, "Invalid reminder status") from exc
    items = await db.supplier_reminders.find(query).sort([("created_at", -1)]).to_list(None)
    return {
        "items": [
            {
                "id": r["_id"],
                "invoiceId": r.get("invoice_id"),
                "matchId": r.get("itc_match_id"),
                "channel": r["channel"],
                "status": r["status"],
                "contactPhone": r.get("contact_phone"),
                "contactEmail": r.get("contact_email"),
                "messagePreview": r.get("message_preview"),
                "called": bool(r.get("called")),
                "promisedBy": r.get("promised_by"),
                "resolvedAt": r.get("resolved_at"),
                "createdAt": r.get("created_at"),
            }
            for r in items
        ]
    }


@router.patch("/reminders/{reminder_id}")
async def update_reminder(
    reminder_id: UUID,
    body: FollowUpUpdate,
    principal: Principal = Depends(company_admin_principal),
    db: AsyncDatabase = Depends(get_db),
):
    changes: dict = {}
    if body.called is not None:
        changes["called"] = body.called
    if body.promised_by is not None:
        changes["promised_by"] = body.promised_by.isoformat()
    if body.resolved:
        changes["status"] = ReminderStatus.resolved.value
        changes["resolved_at"] = utcnow()
    key = {"_id": sid(reminder_id), "company_id": principal.company_id}
    reminder = (
        await db.supplier_reminders.find_one_and_update(key, {"$set": changes}, return_document=ReturnDocument.AFTER)
        if changes
        else await db.supplier_reminders.find_one(key)
    )
    if not reminder:
        raise HTTPException(404, "Reminder not found")
    return {"id": reminder["_id"], "status": reminder["status"], "called": bool(reminder.get("called"))}
