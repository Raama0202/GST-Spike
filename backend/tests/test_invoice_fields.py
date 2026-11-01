from decimal import Decimal

from app.services.invoice import fields_from_data


def test_edits_win_over_scan_across_field_aliases():
    ocr = {"netAmount": 1000, "taxableValue": 847.46}
    fields = fields_from_data(ocr, {"totalAmount": 1180, "taxableAmount": 1000})
    assert fields["net_amount"] == Decimal("1180") and fields["taxable_amount"] == Decimal("1000")

    cleared = fields_from_data(ocr, {"netAmount": None})
    assert cleared["net_amount"] is None and cleared["taxable_amount"] == Decimal("847.46")
