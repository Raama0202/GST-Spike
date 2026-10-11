from datetime import date
from decimal import Decimal
from uuid import uuid4

from app.models import GstrInwardRow, GstrReturnType, Invoice, ItcMatchStatus
from app.services.gstr_excel import parse_gstr_file
from app.services.itc_matcher import _best_match, _norm_inv


def test_parse_csv_gstr_headers():
    csv = (
        "GSTIN of supplier,Trade/Legal name,Invoice number,Invoice Date,Taxable Value,CGST,SGST,IGST,Invoice Value\n"
        "37AABCT1332L1ZV,Vijayawada Paints,INV-1001,15/03/2024,1000,90,90,,1180\n"
        "37AABCT1332L1ZV,Vijayawada Paints,INV-1001,15/03/2024,1000,90,90,,1180\n"
    ).encode()
    rows = parse_gstr_file("gstr2b.csv", csv)
    assert len(rows) == 1  # duplicate collapsed
    assert rows[0]["supplier_gstin"] == "37AABCT1332L1ZV"
    assert rows[0]["invoice_number"] == "INV-1001"
    assert rows[0]["invoice_date"] == date(2024, 3, 15)
    assert rows[0]["net_amount"] == Decimal("1180")


def test_best_match_exact_and_missing():
    company_id = uuid4()
    employee_id = uuid4()
    import_id = uuid4()
    invoice = Invoice(
        company_id=company_id,
        employee_id=employee_id,
        original_image_path="x",
        compressed_image_path="x",
        thumbnail_image_path="x",
        gstin="37AABCT1332L1ZV",
        invoice_number="INV-1001",
        invoice_date=date(2024, 3, 15),
        taxable_amount=Decimal("1000"),
        net_amount=Decimal("1180"),
    )
    row = GstrInwardRow(
        company_id=company_id,
        import_id=import_id,
        period="2024-03",
        return_type=GstrReturnType.gstr_2b,
        supplier_gstin="37AABCT1332L1ZV",
        invoice_number="INV-1001",
        invoice_date=date(2024, 3, 15),
        taxable_amount=Decimal("1000"),
        net_amount=Decimal("1180"),
        raw_json={},
    )
    row.id = uuid4()
    matched, status, delta, _ = _best_match(invoice, [row], set())
    assert matched is row
    assert status == ItcMatchStatus.matched
    assert delta == Decimal("0")

    missing, status2, _, _ = _best_match(invoice, [], set())
    assert missing is None
    assert status2 == ItcMatchStatus.missing_in_2b


def test_norm_inv():
    assert _norm_inv("inv-1001") == "INV1001"
