"""Match company purchase invoices against imported GSTR-2A/2B rows."""

from __future__ import annotations

from collections import defaultdict
from datetime import date
from decimal import Decimal
from typing import Any

from pymongo.asynchronous.database import AsyncDatabase

from app.db.mongo import new_id, utcnow
from app.models import ApprovalStatus, GstrReturnType, ItcMatchStatus


def _norm_inv(value: str | None) -> str:
    return "".join(ch for ch in (value or "").upper() if ch.isalnum())


def _amount(value: Decimal | None) -> Decimal:
    return value if value is not None else Decimal("0")


def _close(a: Decimal | None, b: Decimal | None, tol: Decimal = Decimal("2")) -> bool:
    if a is None or b is None:
        return a == b
    return abs(a - b) <= tol


def _date(value: Any) -> date | None:
    if isinstance(value, date):
        return value
    if isinstance(value, str) and value:
        try:
            return date.fromisoformat(value[:10])
        except ValueError:
            return None
    return None


async def rebuild_matches(
    db: AsyncDatabase,
    *,
    company_id: str,
    period: str,
    return_type: GstrReturnType = GstrReturnType.gstr_2b,
) -> dict[str, int]:
    scope = {"company_id": company_id, "period": period, "return_type": return_type.value}
    run_id = new_id()

    books = await db.invoices.find({
        "company_id": company_id,
        "invoice_date": {"$regex": f"^{period[:7]}"},
        "approval_status": {"$ne": ApprovalStatus.rejected.value},
        "vendor_is_company": {"$ne": True},
    }).to_list(None)
    portal_rows = await db.gstr_inward_rows.find(scope).to_list(None)
    by_gstin: dict[str, list[dict]] = defaultdict(list)
    for row in portal_rows:
        by_gstin[(row.get("supplier_gstin") or "").upper()].append(row)

    used_portal: set[str] = set()
    counts = {status.value: 0 for status in ItcMatchStatus}
    now = utcnow()
    matches: list[dict] = []

    for invoice in books:
        match_row, status, delta, notes = _best_match(invoice, by_gstin.get((invoice.get("gstin") or "").upper(), []), used_portal)
        if match_row is not None:
            used_portal.add(match_row["_id"])
        matches.append({
            "_id": new_id(), **scope, "run_id": run_id,
            "invoice_id": invoice["_id"],
            "gstr_row_id": match_row["_id"] if match_row else None,
            "status": status.value,
            "amount_delta": delta,
            "notes": notes,
            "created_at": now,
        })
        counts[status.value] += 1

    for row in portal_rows:
        if row["_id"] in used_portal:
            continue
        matches.append({
            "_id": new_id(), **scope, "run_id": run_id,
            "invoice_id": None,
            "gstr_row_id": row["_id"],
            "status": ItcMatchStatus.missing_in_books.value,
            "amount_delta": None,
            "notes": "Present in portal download but no matching scanned bill",
            "created_at": now,
        })
        counts[ItcMatchStatus.missing_in_books.value] += 1

    # Insert the new run before removing the old one so readers never see an empty period.
    for start in range(0, len(matches), 1000):
        await db.itc_matches.insert_many(matches[start:start + 1000], ordered=False)
    await db.itc_matches.delete_many({**scope, "run_id": {"$ne": run_id}})
    return counts


def _best_match(
    invoice: dict,
    portal_rows: list[dict],
    used: set[str],
) -> tuple[dict | None, ItcMatchStatus, Decimal | None, str | None]:
    """`portal_rows` are the rows for this invoice's supplier GSTIN only."""
    inv_no = _norm_inv(invoice.get("invoice_number"))
    gstin = (invoice.get("gstin") or "").upper()
    inv_date = _date(invoice.get("invoice_date"))
    candidates = [r for r in portal_rows if r["_id"] not in used]

    # 1) Exact GSTIN + invoice number + date
    for row in candidates:
        row_date = _date(row.get("invoice_date"))
        if (
            (row.get("supplier_gstin") or "").upper() == gstin
            and inv_no
            and _norm_inv(row.get("invoice_number")) == inv_no
            and row_date
            and inv_date
            and row_date == inv_date
        ):
            return _classify_amounts(invoice, row)

    # 2) GSTIN + invoice number, date within ±3 days
    for row in candidates:
        if (row.get("supplier_gstin") or "").upper() != gstin or not inv_no or _norm_inv(row.get("invoice_number")) != inv_no:
            continue
        row_date = _date(row.get("invoice_date"))
        if inv_date and row_date and abs((inv_date - row_date).days) <= 3:
            return _classify_amounts(invoice, row, notes="Matched with date tolerance ±3 days")

    # 3) GSTIN + amount + date window (±7 days)
    for row in candidates:
        if (row.get("supplier_gstin") or "").upper() != gstin:
            continue
        row_date = _date(row.get("invoice_date"))
        if not inv_date or not row_date or abs((inv_date - row_date).days) > 7:
            continue
        if _close(invoice.get("net_amount"), row.get("net_amount")) or _close(invoice.get("taxable_amount"), row.get("taxable_amount")):
            return _classify_amounts(invoice, row, notes="Matched on GSTIN + amount + date window")

    return None, ItcMatchStatus.missing_in_2b, None, "In books but not found in portal download"


def _classify_amounts(
    invoice: dict,
    row: dict,
    *,
    notes: str | None = None,
) -> tuple[dict, ItcMatchStatus, Decimal | None, str | None]:
    net, row_net = invoice.get("net_amount"), row.get("net_amount")
    delta = _amount(net) - _amount(row_net)
    if _close(net, row_net) and _close(invoice.get("taxable_amount"), row.get("taxable_amount")):
        return row, ItcMatchStatus.matched, Decimal("0"), notes
    if abs(delta) <= Decimal("50"):
        return row, ItcMatchStatus.partial, delta, notes or "Partial amount match"
    return row, ItcMatchStatus.mismatch, delta, notes or "Amounts differ beyond tolerance"
