from datetime import date

from app.services.ai_extract import _clean_invoice_number, _money, _normalize, _parse_date, words_to_amount
from app.services.party import CompanyIdentity

VALID_GSTIN = "27AAPFU0939F1ZV"


def test_normalize_valid_gst_invoice():
    result = _normalize(
        {
            "vendorName": "  Vijayawada Paints  ",
            "gstin": VALID_GSTIN,
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
    assert result["gstin"] == VALID_GSTIN
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


def test_misread_gstin_is_repaired_and_checksum_failure_is_flagged():
    # O read for 0 and I for 1 in digit positions.
    repaired = _normalize({"vendorName": "Paints", "gstin": "27AAPFU0939F1ZV".replace("0", "O"), "netAmount": 10, "confidence": 0.9})
    assert repaired["gstin"] == VALID_GSTIN

    flagged = _normalize({"vendorName": "Paints", "gstin": "37AABCT1332L1ZV", "netAmount": 10, "confidence": 0.95})
    assert flagged["gstin"] == "37AABCT1332L1ZV"
    assert flagged["confidence"] <= 0.6
    assert "checksum" in flagged["notes"]


def test_two_company_bill_picks_the_party_that_is_not_the_scanning_company():
    identity = CompanyIdentity.from_company(
        {"name": "Sunrise Traders", "legal_name": "Sunrise Traders Private Limited", "gstin": "36AAPFU0939F1ZW"}
    )
    raw = {
        # The model wrongly returned the buyer (the scanning company) as the vendor.
        "vendorName": "M/s Sunrise Traders Pvt Ltd",
        "gstin": "36AAPFU0939F1ZW",
        "invoiceNumber": "SVE/245",
        "invoiceDate": "01-10-26",
        "netAmount": "5,900/-",
        "parties": [
            {"name": "Sri Vijayalakshmi Enterprises", "gstin": VALID_GSTIN, "role": "seller"},
            {"name": "Sunrise Traders Pvt Ltd", "gstin": "36AAPFU0939F1ZW", "role": "buyer"},
        ],
        "confidence": 0.9,
    }
    result = _normalize(raw, identity)
    assert result["vendorName"] == "Sri Vijayalakshmi Enterprises"
    assert result["gstin"] == VALID_GSTIN
    assert result["buyerIsCompany"] is True
    assert result["buyerGstin"] == "36AAPFU0939F1ZW"
    assert result["netAmount"] == 5900.0
    assert result["invoiceDate"] == "2026-10-01"
    assert "switched to the other party" in result["notes"]


SUPPLIER_GSTIN = "37AABCV1234K1ZC"
COMPANY_GSTIN = "36AAACS5678L1ZS"


def test_buyer_listed_first_is_skipped_for_the_seller():
    identity = CompanyIdentity.from_company({"name": "Sunrise Traders", "gstin": COMPANY_GSTIN})
    result = _normalize(
        {
            "vendorName": "SUNRISE TRADERS",
            "gstin": COMPANY_GSTIN,
            "netAmount": 2360,
            "parties": [
                {"name": "Sunrise Traders", "gstin": COMPANY_GSTIN, "role": "unknown"},
                {"name": "Vijaya Hardware & Paints", "gstin": SUPPLIER_GSTIN, "role": "unknown"},
            ],
            "confidence": 0.9,
        },
        identity,
    )
    assert result["vendorName"] == "Vijaya Hardware & Paints"
    assert result["gstin"] == SUPPLIER_GSTIN
    assert result["buyerIsCompany"] is True


def test_supplier_name_with_company_gstin_gets_supplier_gstin():
    identity = CompanyIdentity.from_company({"name": "Sunrise Traders", "gstin": COMPANY_GSTIN})
    result = _normalize(
        {
            "vendorName": "Vijaya Hardware",
            "gstin": COMPANY_GSTIN,
            "netAmount": 100,
            "parties": [
                {"name": "Vijaya Hardware", "gstin": SUPPLIER_GSTIN, "role": "seller"},
                {"name": "Sunrise Traders", "gstin": COMPANY_GSTIN, "role": "buyer"},
            ],
            "confidence": 0.9,
        },
        identity,
    )
    assert result["vendorName"] == "Vijaya Hardware"
    assert result["gstin"] == SUPPLIER_GSTIN


def test_only_the_company_on_the_bill_leaves_vendor_for_the_user():
    identity = CompanyIdentity.from_company({"name": "Sunrise Traders", "gstin": COMPANY_GSTIN})
    result = _normalize(
        {"vendorName": "Sunrise Traders", "gstin": COMPANY_GSTIN, "netAmount": 100, "confidence": 0.9},
        identity,
    )
    assert result["vendorName"] is None and result["gstin"] is None
    assert result["confidence"] <= 0.5
    assert "enter the supplier name" in result["notes"]


def test_company_alias_matches_without_gstin():
    identity = CompanyIdentity.from_company({"name": "SVL Infra", "name_aliases": ["Sri Venkata Lakshmi Infra Projects"]})
    result = _normalize(
        {
            "vendorName": "Sri Venkata Lakshmi Infra Projects Pvt. Ltd.",
            "netAmount": 500,
            "parties": [{"name": "Balaji Cement Agencies", "gstin": None, "role": "unknown"}],
            "confidence": 0.9,
        },
        identity,
    )
    assert result["vendorName"] == "Balaji Cement Agencies"


def test_same_pan_other_state_is_still_the_company():
    # Company registered in Telangana (36); bill names its Maharashtra branch (27) with the same PAN.
    identity = CompanyIdentity.from_company({"name": "Unique Foods", "gstin": "36AAPFU0939F1ZW"})
    assert identity.owns_gstin(VALID_GSTIN)
    result = _normalize(
        {
            "vendorName": "Unique Foods",
            "gstin": VALID_GSTIN,
            "netAmount": 100,
            "parties": [{"name": "Hotel Paradise", "gstin": None, "role": "seller"}],
            "confidence": 0.9,
        },
        identity,
    )
    assert result["vendorName"] == "Hotel Paradise"
    assert result["gstin"] is None


def test_company_name_with_supplier_gstin_takes_supplier_name():
    identity = CompanyIdentity.from_company({"name": "Sunrise Traders"})
    result = _normalize(
        {
            "vendorName": "Sunrise Traders",
            "gstin": VALID_GSTIN,
            "netAmount": 100,
            "parties": [{"name": "Vijaya Hardware", "gstin": VALID_GSTIN, "role": "unknown"}],
            "confidence": 0.9,
        },
        identity,
    )
    assert result["vendorName"] == "Vijaya Hardware"
    assert result["gstin"] == VALID_GSTIN


def test_handwritten_bill_is_capped_and_amounts_derived_from_line_items():
    result = _normalize(
        {
            "vendorName": "Ganesh Kirana Stores",
            "invoiceNumber": "No. 57",
            "invoiceDate": "5/9/26",
            "lineItems": [
                {"description": "Rice 25kg", "quantity": "1", "rate": "1,450", "amount": None},
                {"description": "Oil", "quantity": 2, "rate": 180, "amount": "360/-"},
            ],
            "isHandwritten": True,
            "documentType": "cash memo",
            "confidence": 0.97,
        }
    )
    assert result["isHandwritten"] is True
    assert result["confidence"] <= 0.8
    assert result["netAmount"] == 1810.0
    assert result["invoiceDate"] == "2026-09-05"
    assert len(result["lineItems"]) == 2


def test_amount_in_words():
    assert words_to_amount("Rupees One Thousand Two Hundred Fifty Only") == 1250.0
    assert words_to_amount("Rs. One Lakh Twenty-Five Thousand and Fifty Paise Only") == 125000.5
    assert words_to_amount("Twelve hundred rupees only") == 1200.0
    assert words_to_amount("Two Crore Fifty Lakh") == 25_000_000.0
    assert words_to_amount("Only") is None
    assert words_to_amount(None) is None


def test_handwritten_total_in_words_fills_and_checks_the_figure():
    filled = _normalize({"vendorName": "Ganesh Stores", "amountInWords": "Rupees Five Hundred Only", "isHandwritten": True, "confidence": 0.9})
    assert filled["netAmount"] == 500.0

    disagree = _normalize(
        {"vendorName": "Ganesh Stores", "netAmount": 1750, "amountInWords": "One thousand two hundred fifty only", "isHandwritten": True, "confidence": 0.9}
    )
    assert disagree["netAmount"] == 1750.0
    assert disagree["confidence"] <= 0.5
    assert "in words" in disagree["notes"]


def test_handwritten_line_items_that_do_not_add_up_are_flagged():
    result = _normalize(
        {
            "vendorName": "Ganesh Stores",
            "netAmount": 990,
            "lineItems": [{"description": "Rice", "amount": 450}, {"description": "Dal", "amount": 240}],
            "isHandwritten": True,
            "confidence": 0.95,
        }
    )
    assert result["confidence"] <= 0.6
    assert "Line items add up to 690.00" in result["notes"]


def test_field_cleaners():
    assert _clean_invoice_number("Invoice No: GT/1023") == "GT/1023"
    assert _clean_invoice_number("Bill # 77") == "77"
    assert _clean_invoice_number("INV-8891") == "INV-8891"
    assert _money("Rs. 1,23,456.50") == 123456.5
    assert _money("₹ 5,900/-") == 5900.0
    assert _parse_date("13.11.2025") == date(2025, 11, 13)
    assert _parse_date("1999-01-01") is None
