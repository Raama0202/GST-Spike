"""Match company purchase invoices against imported GSTR-2A/2B rows."""

from __future__ import annotations

from decimal import Decimal
from uuid import UUID

from sqlalchemy import delete, extract, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import (
    GstrInwardRow,
    GstrReturnType,
    Invoice,
    ItcMatch,
    ItcMatchStatus,
)


def _norm_inv(value: str | None) -> str:
    return "".join(ch for ch in (value or "").upper() if ch.isalnum())


def _amount(value: Decimal | None) -> Decimal:
    return value if value is not None else Decimal("0")


def _close(a: Decimal | None, b: Decimal | None, tol: Decimal = Decimal("2")) -> bool:
    if a is None or b is None:
        return a == b
    return abs(a - b) <= tol


async def rebuild_matches(
    db: AsyncSession,
    *,
    company_id: UUID,
    period: str,
    return_type: GstrReturnType = GstrReturnType.gstr_2b,
) -> dict[str, int]:
    year, month = int(period[:4]), int(period[5:7])

    await db.execute(
        delete(ItcMatch).where(
            ItcMatch.company_id == company_id,
            ItcMatch.period == period,
            ItcMatch.return_type == return_type,
        )
    )

    books = (
        await db.scalars(
            select(Invoice).where(
                Invoice.company_id == company_id,
                extract("year", Invoice.invoice_date) == year,
                extract("month", Invoice.invoice_date) == month,
            )
        )
    ).all()

    portal_rows = (
        await db.scalars(
            select(GstrInwardRow).where(
                GstrInwardRow.company_id == company_id,
                GstrInwardRow.period == period,
                GstrInwardRow.return_type == return_type,
            )
        )
    ).all()

    used_portal: set[UUID] = set()
    counts = {status.value: 0 for status in ItcMatchStatus}

    for invoice in books:
        match_row, status, delta, notes = _best_match(invoice, portal_rows, used_portal)
        if match_row is not None:
            used_portal.add(match_row.id)
        db.add(
            ItcMatch(
                company_id=company_id,
                period=period,
                return_type=return_type,
                invoice_id=invoice.id,
                gstr_row_id=match_row.id if match_row else None,
                status=status,
                amount_delta=delta,
                notes=notes,
            )
        )
        counts[status.value] += 1

    for row in portal_rows:
        if row.id in used_portal:
            continue
        db.add(
            ItcMatch(
                company_id=company_id,
                period=period,
                return_type=return_type,
                invoice_id=None,
                gstr_row_id=row.id,
                status=ItcMatchStatus.missing_in_books,
                amount_delta=None,
                notes="Present in portal download but no matching scanned bill",
            )
        )
        counts[ItcMatchStatus.missing_in_books.value] += 1

    await db.commit()
    return counts


def _best_match(
    invoice: Invoice,
    portal_rows: list[GstrInwardRow],
    used: set[UUID],
) -> tuple[GstrInwardRow | None, ItcMatchStatus, Decimal | None, str | None]:
    inv_no = _norm_inv(invoice.invoice_number)
    gstin = (invoice.gstin or "").upper()
    candidates = [r for r in portal_rows if r.id not in used]

    # 1) Exact GSTIN + invoice number + date
    for row in candidates:
        if (
            (row.supplier_gstin or "").upper() == gstin
            and _norm_inv(row.invoice_number) == inv_no
            and inv_no
            and row.invoice_date
            and invoice.invoice_date
            and row.invoice_date == invoice.invoice_date
        ):
            return _classify_amounts(invoice, row)

    # 2) GSTIN + invoice number, date within ±3 days
    for row in candidates:
        if (row.supplier_gstin or "").upper() != gstin or _norm_inv(row.invoice_number) != inv_no or not inv_no:
            continue
        if invoice.invoice_date and row.invoice_date:
            if abs((invoice.invoice_date - row.invoice_date).days) <= 3:
                return _classify_amounts(invoice, row, notes="Matched with date tolerance ±3 days")

    # 3) GSTIN + amount + date window (±7 days)
    for row in candidates:
        if (row.supplier_gstin or "").upper() != gstin:
            continue
        if not invoice.invoice_date or not row.invoice_date:
            continue
        if abs((invoice.invoice_date - row.invoice_date).days) > 7:
            continue
        if _close(invoice.net_amount, row.net_amount) or _close(invoice.taxable_amount, row.taxable_amount):
            return _classify_amounts(invoice, row, notes="Matched on GSTIN + amount + date window")

    return None, ItcMatchStatus.missing_in_2b, None, "In books but not found in portal download"


def _classify_amounts(
    invoice: Invoice,
    row: GstrInwardRow,
    *,
    notes: str | None = None,
) -> tuple[GstrInwardRow, ItcMatchStatus, Decimal | None, str | None]:
    delta = _amount(invoice.net_amount) - _amount(row.net_amount)
    if _close(invoice.net_amount, row.net_amount) and _close(invoice.taxable_amount, row.taxable_amount):
        return row, ItcMatchStatus.matched, Decimal("0"), notes
    if abs(delta) <= Decimal("50"):
        return row, ItcMatchStatus.partial, delta, notes or "Partial amount match"
    return row, ItcMatchStatus.mismatch, delta, notes or "Amounts differ beyond tolerance"
