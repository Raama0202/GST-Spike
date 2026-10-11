from datetime import date

from app.services.ai_extract import _normalize


def test_normalize_valid_gst_invoice():
    result = _normalize(
        {
            "vendorName": "  Vijayawada Paints  ",
            "gstin": "37AABCT1332L1ZV",
            "invoiceNumber": "INV-8891",
            "invoiceDate": "15/03/2024",
            "taxableValue": "1000",
            "cgst": 90,
            "sgst": 90,
            "igst": None,
            "discount": 0,
            "netAmount": 1180,
            "confidence": 0.93,
            "notes": None,
        }
    )
    assert result["vendorName"] == "Vijayawada Paints"
    assert result["gstin"] == "37AABCT1332L1ZV"
    assert result["invoiceNumber"] == "INV-8891"
    assert result["invoiceDate"] == date(2024, 3, 15).isoformat()
    assert result["taxableValue"] == 1000.0
    assert result["cgst"] == 90.0
    assert result["sgst"] == 90.0
    assert result["netAmount"] == 1180.0
    assert result["confidence"] >= 0.9
    assert result["provider"] == "gemini"


def test_normalize_rejects_bad_gstin_and_lowers_confidence_on_bad_math():
    result = _normalize(
        {
            "vendorName": "Acme",
            "gstin": "NOT-A-GSTIN",
            "invoiceNumber": "1",
            "invoiceDate": "2024-01-01",
            "taxableValue": 100,
            "cgst": 9,
            "sgst": 9,
            "igst": None,
            "discount": 0,
            "netAmount": 999,
            "confidence": 0.95,
        }
    )
    assert result["gstin"] is None
    assert result["confidence"] <= 0.55
