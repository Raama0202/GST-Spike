"""Extract structured Indian GST invoice fields from a bill image.

Uses Google Gemini Flash (free tier) as the primary vision model: layouts vary
wildly across vendors and many bills are handwritten, which a vision LLM reads
far better than regex-on-OCR. The on-device ML Kit + regex parser remains the
offline fallback in the clients.

The scanning company's identity (names, GSTINs) is passed in so the model and
the post-processing never record the company itself as the vendor.
"""

from __future__ import annotations

import asyncio
import base64
import json
import re
from datetime import date, datetime
from typing import Any

import httpx

from app.core.config import settings
from app.services import gstin as gst
from app.services.party import CompanyIdentity, resolve_vendor

EXTRACTION_PROMPT = """
You are an expert at reading Indian bills: printed GST tax invoices, computer bills,
thermal receipts, and HANDWRITTEN bills / cash memos / kachha bills / estimates.
Extract fields from the attached image. Return ONLY valid JSON matching the schema.

Fields:
- vendorName: the SELLER / supplier who issued the bill (usually the letterhead or stamp at the top).
- gstin: the SELLER's 15-character GSTIN.
- parties: EVERY business named on the bill, each {name, gstin, role}. role is "seller" for the
  issuer, "buyer" for "Bill to / Billed to / Buyer / Customer / M/s / Consignee / Ship to / Recipient",
  otherwise "unknown". Include both parties even when you are unsure which is which.
- invoiceNumber: the bill / invoice / cash memo number (not IRN, not e-way bill, not GSTIN, not phone).
- invoiceDate: YYYY-MM-DD.
- taxableValue, cgst, sgst, igst, discount, netAmount: numbers only. netAmount is the invoice value
  (the full amount of the bill including GST).
- amountInWords: the total written in words exactly as on the bill ("Rupees One Thousand Two
  Hundred Only"), or null when there is none.
- lineItems: each {description, quantity, rate, amount} when items are listed.
- supplierPhone / supplierEmail: SELLER contact details when printed or written.
- isHandwritten: true when the amounts or items are handwritten.
- documentType: "tax_invoice" | "bill_of_supply" | "cash_memo" | "receipt" | "estimate" | "other".
- confidence: 0.0-1.0 for how sure you are overall. notes: short reasons for any doubt.

Rules:
- Dates on bills are day-first (dd/mm/yyyy, dd-mm-yy, dd.mm.yy). Two-digit years mean 20yy.
- Amounts: Indian grouping (1,25,000.00) and suffixes like "/-", "Rs", "₹", "INR" are common.
  "1250/-" means 1250. Ignore struck-through figures; use the corrected value written nearby.
- Prefer invoice value / grand total / net payable / amount payable / "Total Rs" for netAmount. If the total is
  also written in words ("Rupees One Thousand Two Hundred Only"), use it to confirm the figure.
- On handwritten bills read each digit carefully (1 vs 7, 4 vs 9, 5 vs 6, 0 vs 6). When no total
  is written, set netAmount to the sum of the line item amounts.
- Handwritten amounts are often written "1250=00", "1250-00", "1250/-" or "Rs 1250.00"; all mean 1250.
- On handwritten cash memos the PRINTED header or rubber stamp is the seller; the handwritten
  "M/s", "Name", "To" or "Sold to" line is the buyer.
- Bills may be in Telugu, Hindi, Tamil, Kannada, Marathi, Gujarati, Bengali or mixed with English.
  Write names in English letters (transliterate, e.g. "శ్రీ లక్ష్మి ట్రేడర్స్" -> "Sri Lakshmi Traders")
  and convert Devanagari or other Indian digits to 0-9.
- Faint carbon copies and creased or skewed photos are common; read through stamps and folds.
- If only IGST is present, set igst and leave cgst/sgst null (and vice versa).
- taxableValue = taxable / assessable value before GST. Cash memos without GST: taxes null.
- If a field is unreadable, use null. Never invent a GSTIN or invoice number.
- Do not wrap the JSON in markdown.
""".strip()

_PARTY_SCHEMA = {
    "type": "object",
    "properties": {
        "name": {"type": "string", "nullable": True},
        "gstin": {"type": "string", "nullable": True},
        "role": {"type": "string", "enum": ["seller", "buyer", "unknown"]},
    },
}
_LINE_ITEM_SCHEMA = {
    "type": "object",
    "properties": {
        "description": {"type": "string", "nullable": True},
        "quantity": {"type": "number", "nullable": True},
        "rate": {"type": "number", "nullable": True},
        "amount": {"type": "number", "nullable": True},
    },
}

RESPONSE_SCHEMA: dict[str, Any] = {
    "type": "object",
    "properties": {
        "vendorName": {"type": "string", "nullable": True},
        "gstin": {"type": "string", "nullable": True},
        "parties": {"type": "array", "items": _PARTY_SCHEMA},
        "invoiceNumber": {"type": "string", "nullable": True},
        "invoiceDate": {"type": "string", "nullable": True},
        "taxableValue": {"type": "number", "nullable": True},
        "cgst": {"type": "number", "nullable": True},
        "sgst": {"type": "number", "nullable": True},
        "igst": {"type": "number", "nullable": True},
        "discount": {"type": "number", "nullable": True},
        "netAmount": {"type": "number", "nullable": True},
        "amountInWords": {"type": "string", "nullable": True},
        "lineItems": {"type": "array", "items": _LINE_ITEM_SCHEMA},
        "supplierPhone": {"type": "string", "nullable": True},
        "supplierEmail": {"type": "string", "nullable": True},
        "isHandwritten": {"type": "boolean", "nullable": True},
        "documentType": {"type": "string", "nullable": True},
        "confidence": {"type": "number"},
        "notes": {"type": "string", "nullable": True},
    },
    "required": ["confidence"],
}


class AiExtractError(Exception):
    def __init__(self, message: str, *, status_code: int = 502):
        super().__init__(message)
        self.status_code = status_code


def ai_extract_configured() -> bool:
    return bool(settings.gemini_api_key.strip())


RETRY_PAUSE_SECONDS = 2.0

FALLBACK_MODELS = (
    "gemini-flash-latest",
    "gemini-3.5-flash",
    "gemini-2.5-flash",
    "gemini-2.5-flash-lite",
    "gemini-2.0-flash",
)


async def extract_invoice_fields(
    image_bytes: bytes,
    *,
    mime_type: str = "image/jpeg",
    identity: CompanyIdentity | None = None,
) -> dict[str, Any]:
    if not ai_extract_configured():
        raise AiExtractError(
            "AI extraction is not configured. Set GEMINI_API_KEY on the server "
            "(free key from https://aistudio.google.com/apikey).",
            status_code=503,
        )
    if not image_bytes:
        raise AiExtractError("Empty image", status_code=400)
    if len(image_bytes) > 15 * 1024 * 1024:
        raise AiExtractError("Image too large for AI extraction (max 15 MB)", status_code=400)

    identity = identity or CompanyIdentity()
    raw, model_used = await _call_gemini(image_bytes, mime_type, identity)
    result = _normalize(raw, identity)
    result["model"] = model_used
    return result


def _candidate_models() -> list[str]:
    preferred = (settings.gemini_model or "").strip()
    models: list[str] = [preferred] if preferred else []
    for name in FALLBACK_MODELS:
        if name not in models:
            models.append(name)
    return models


def _prompt(identity: CompanyIdentity) -> str:
    hint = identity.prompt_hint()
    return f"{EXTRACTION_PROMPT}\n\n{hint}" if hint else EXTRACTION_PROMPT


async def _call_gemini(image_bytes: bytes, mime_type: str, identity: CompanyIdentity) -> tuple[dict[str, Any], str]:
    payload = {
        "contents": [
            {
                "role": "user",
                "parts": [
                    {"text": _prompt(identity)},
                    {"inline_data": {"mime_type": mime_type, "data": base64.b64encode(image_bytes).decode("ascii")}},
                ],
            }
        ],
        "generationConfig": {
            "temperature": 0.1,
            "responseMimeType": "application/json",
            "responseSchema": RESPONSE_SCHEMA,
        },
    }

    last_error = "No Gemini models available"
    models = _candidate_models()
    async with httpx.AsyncClient(timeout=60.0) as client:
        # Free-tier limits are per minute; one short pause usually clears a burst.
        for attempt, model in enumerate([*models, models[0]]):
            if attempt == len(models):
                if not _is_busy(last_error):
                    break
                await asyncio.sleep(RETRY_PAUSE_SECONDS)
            url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"
            try:
                response = await client.post(url, headers={"x-goog-api-key": settings.gemini_api_key}, json=payload)
            except httpx.HTTPError as exc:
                last_error = f"AI provider unreachable: {exc}"
                continue

            if response.status_code == 429:
                last_error = "AI free-tier rate limit reached"
                # Try next model — different Flash SKUs often have separate quotas.
                continue

            if response.status_code >= 400:
                detail = _provider_error(response)
                last_error = detail
                lower = detail.lower()
                if any(
                    tip in lower
                    for tip in ("no longer available", "not found", "high demand", "quota", "overloaded", "try again later", "unsupported")
                ):
                    continue
                raise AiExtractError(f"AI extraction failed: {detail}", status_code=502)

            body = response.json()
            try:
                text = body["candidates"][0]["content"]["parts"][0]["text"]
            except (KeyError, IndexError, TypeError):
                last_error = f"{model} returned an empty extraction result"
                continue

            try:
                return json.loads(_strip_fences(text)), model
            except json.JSONDecodeError:
                last_error = f"{model} returned invalid JSON"
                continue

    if _is_busy(last_error):
        raise AiExtractError("AI free-tier is busy or rate-limited. Try again in a minute, or continue offline.", status_code=429)
    raise AiExtractError(f"AI extraction failed: {last_error}", status_code=502)


def _is_busy(error: str) -> bool:
    lower = error.lower()
    return any(tip in lower for tip in ("rate limit", "high demand", "overloaded", "try again later"))


def _provider_error(response: httpx.Response) -> str:
    try:
        data = response.json()
        err = data.get("error") or {}
        if isinstance(err, dict) and err.get("message"):
            return str(err["message"])
    except Exception:
        pass
    return response.text[:240] or f"HTTP {response.status_code}"


def _strip_fences(text: str) -> str:
    cleaned = text.strip()
    if cleaned.startswith("```"):
        cleaned = re.sub(r"^```(?:json)?\s*", "", cleaned)
        cleaned = re.sub(r"\s*```$", "", cleaned)
    return cleaned.strip()


def _normalize(raw: dict[str, Any], identity: CompanyIdentity | None = None) -> dict[str, Any]:
    identity = identity or CompanyIdentity()
    notes: list[str] = [n for n in [_clean_str(raw.get("notes"))] if n]
    confidence = _clamp(raw.get("confidence"), default=0.7)

    gstin, gstin_ok = _clean_gstin(raw.get("gstin"))
    if gstin and not gstin_ok:
        notes.append("Vendor GSTIN failed its checksum; please verify it")
        confidence = min(confidence, 0.6)
    invoice_date = _parse_date(raw.get("invoiceDate"))
    line_items = _line_items(raw.get("lineItems"))

    fields: dict[str, Any] = {
        "vendorName": _clean_str(raw.get("vendorName")),
        "gstin": gstin,
        "invoiceNumber": _clean_invoice_number(raw.get("invoiceNumber")),
        "invoiceDate": invoice_date.isoformat() if invoice_date else None,
        "taxableValue": _money(raw.get("taxableValue")),
        "cgst": _money(raw.get("cgst")),
        "sgst": _money(raw.get("sgst")),
        "igst": _money(raw.get("igst")),
        "discount": _money(raw.get("discount")),
        "netAmount": _money(raw.get("netAmount")),
        "supplierPhone": _clean_phone(raw.get("supplierPhone")),
        "supplierEmail": _clean_email(raw.get("supplierEmail")),
    }
    in_words = words_to_amount(raw.get("amountInWords"))
    if in_words and fields["netAmount"] is None:
        fields["netAmount"] = in_words
    elif in_words and abs(in_words - fields["netAmount"]) > max(1.0, 0.01 * fields["netAmount"]):
        notes.append(f"Total in words reads {in_words:,.2f} but the figures read {fields['netAmount']:,.2f}; please check")
        confidence = min(confidence, 0.5)
    _fill_derived_amounts(fields, line_items)

    parties = [
        {"name": _clean_str(p.get("name")), "gstin": _clean_gstin(p.get("gstin"))[0], "role": p.get("role") or "unknown"}
        for p in (raw.get("parties") or [])
        if isinstance(p, dict)
    ]
    resolve_vendor(fields, parties, identity)
    if fields.pop("vendorCorrected", False):
        if fields.get("vendorName"):
            notes.append("The scanned company was named as the vendor; switched to the other party on the bill")
        else:
            notes.append("Only your own company was found on the bill; please enter the supplier name")
            confidence = min(confidence, 0.5)

    if not _amounts_plausible(fields):
        confidence = min(confidence, 0.55)
    is_handwritten = bool(raw.get("isHandwritten"))
    if is_handwritten:
        # Handwriting is read well but not perfectly; always ask for a human glance.
        confidence = min(confidence, 0.8)
        items_total = _line_items_total(line_items)
        net = fields.get("netAmount")
        if items_total is not None and net is not None:
            tax = sum(fields.get(key) or 0.0 for key in ("cgst", "sgst", "igst"))
            expected = items_total + tax - (fields.get("discount") or 0.0)
            if abs(expected - net) > max(2.0, 0.02 * net):
                notes.append(f"Line items add up to {items_total:,.2f} but the total reads {net:,.2f}; please check")
                confidence = min(confidence, 0.6)

    present = sum(1 for key in ("vendorName", "gstin", "invoiceNumber", "invoiceDate", "netAmount") if fields.get(key))
    if present < 2:
        confidence = min(confidence, 0.4)

    return {
        **fields,
        "lineItems": line_items,
        "isHandwritten": is_handwritten,
        "documentType": _clean_str(raw.get("documentType")),
        "confidence": round(confidence, 3),
        "provider": "gemini",
        "model": settings.gemini_model,
        "notes": "; ".join(notes) or None,
    }


def _fill_derived_amounts(fields: dict[str, Any], line_items: list[dict[str, Any]]) -> None:
    tax = sum(v for v in (fields.get("cgst"), fields.get("sgst"), fields.get("igst")) if v)
    if fields.get("netAmount") is None and fields.get("taxableValue") is None and line_items:
        total = sum(item["amount"] for item in line_items if item.get("amount") is not None)
        if total:
            fields["netAmount"] = round(total + tax - (fields.get("discount") or 0), 2)
    if fields.get("netAmount") is None and fields.get("taxableValue") is not None:
        fields["netAmount"] = round(fields["taxableValue"] + tax - (fields.get("discount") or 0), 2)
    if fields.get("taxableValue") is None and fields.get("netAmount") is not None and tax:
        fields["taxableValue"] = round(fields["netAmount"] - tax + (fields.get("discount") or 0), 2)
    if fields.get("cgst") is not None and fields.get("sgst") is None:
        fields["sgst"] = fields["cgst"]
    elif fields.get("sgst") is not None and fields.get("cgst") is None:
        fields["cgst"] = fields["sgst"]


def _amounts_plausible(fields: dict[str, Any]) -> bool:
    taxable = fields.get("taxableValue")
    net = fields.get("netAmount")
    if taxable is None or net is None:
        return True
    tax = sum(value or 0.0 for value in (fields.get("cgst"), fields.get("sgst"), fields.get("igst")))
    discount = fields.get("discount") or 0.0
    expected = taxable + tax - discount
    # Round-off lines on Indian bills move the total by up to ±1.
    return abs(expected - net) <= max(2.0, 0.02 * max(net, 1.0))


def _line_items_total(items: list[dict[str, Any]]) -> float | None:
    """Sum of line amounts, only when there are at least two lines and every line has an amount."""
    amounts = [item.get("amount") for item in items]
    if len(amounts) < 2 or any(amount is None for amount in amounts):
        return None
    return round(sum(amounts), 2)


_UNIT_WORDS = {
    word: value
    for value, word in enumerate(
        "zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen "
        "fifteen sixteen seventeen eighteen nineteen".split()
    )
}
_TEN_WORDS = {word: value * 10 for value, word in enumerate("_ _ twenty thirty forty fifty sixty seventy eighty ninety".split()) if value >= 2}
_TEN_WORDS["fourty"] = 40
_SCALE_WORDS = {"thousand": 1_000, "lakh": 100_000, "lakhs": 100_000, "lac": 100_000, "lacs": 100_000, "crore": 10_000_000, "crores": 10_000_000}
_NUMBER_WORDS = {*_UNIT_WORDS, *_TEN_WORDS, *_SCALE_WORDS, "hundred"}


def _words_number(tokens: list[str]) -> int | None:
    total = current = 0
    seen = False
    for word in tokens:
        if word in _UNIT_WORDS:
            current += _UNIT_WORDS[word]
        elif word in _TEN_WORDS:
            current += _TEN_WORDS[word]
        elif word == "hundred":
            current = (current or 1) * 100
        elif word in _SCALE_WORDS:
            total += (current or 1) * _SCALE_WORDS[word]
            current = 0
        else:
            continue
        seen = True
    return total + current if seen else None


def words_to_amount(value: Any) -> float | None:
    """Indian amount in words ("Rupees One Lakh Twenty Thousand and Fifty Paise Only") as a number."""
    text = _clean_str(value)
    if not text:
        return None
    words = re.sub(r"[^a-z ]", " ", text.lower().replace("-", " ")).split()
    paise = 0
    if "paise" in words:
        end = words.index("paise")
        start = end
        while start > 0 and words[start - 1] in _NUMBER_WORDS:
            start -= 1
        paise = _words_number(words[start:end]) or 0
        words = words[:start] + words[end + 1:]
    rupees = _words_number([word for word in words if word in _NUMBER_WORDS])
    if rupees is None:
        return None
    amount = round(rupees + min(paise, 99) / 100, 2)
    return amount or None


def _line_items(value: Any) -> list[dict[str, Any]]:
    items = []
    for item in value or []:
        if not isinstance(item, dict):
            continue
        cleaned = {
            "description": _clean_str(item.get("description")),
            "quantity": _money(item.get("quantity")),
            "rate": _money(item.get("rate")),
            "amount": _money(item.get("amount")),
        }
        if cleaned["amount"] is None and cleaned["quantity"] is not None and cleaned["rate"] is not None:
            cleaned["amount"] = round(cleaned["quantity"] * cleaned["rate"], 2)
        if any(v is not None for v in cleaned.values()):
            items.append(cleaned)
    return items[:100]


def _clean_str(value: Any) -> str | None:
    if value is None:
        return None
    text = re.sub(r"\s+", " ", str(value)).strip()
    if not text or text.lower() in {"null", "none", "n/a", "na", "-"}:
        return None
    return text


def _clean_invoice_number(value: Any) -> str | None:
    text = _clean_str(value)
    if not text:
        return None
    text = re.sub(
        r"^(?:tax\s+)?(?:invoice|inv|bill|memo|receipt)\s*(?:(?:no\.?|number|num|#)\s*[:.\-]?|:)\s*",
        "",
        text,
        flags=re.I,
    )
    return text[:120] or None


def _clean_phone(value: Any) -> str | None:
    text = _clean_str(value)
    if not text:
        return None
    digits = re.sub(r"\D", "", text)
    if digits.startswith("91") and len(digits) == 12:
        digits = digits[2:]
    if digits.startswith("0") and len(digits) == 11:
        digits = digits[1:]
    if len(digits) == 10 and digits[0] in "6789":
        return digits
    return None


def _clean_email(value: Any) -> str | None:
    text = _clean_str(value)
    if not text or not re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", text):
        return None
    return text.lower()


def _clean_gstin(value: Any) -> tuple[str | None, bool]:
    """(gstin, checksum_ok). Keeps a well-shaped but checksum-failing value so the user can fix it."""
    text = _clean_str(value)
    if not text:
        return None, False
    repaired = gst.repair(text)
    if repaired:
        return repaired, True
    compact = gst.compact(text)
    return (compact, False) if gst.GSTIN_SHAPE.match(compact) else (None, False)


def _parse_date(value: Any) -> date | None:
    if value is None:
        return None
    if isinstance(value, date) and not isinstance(value, datetime):
        return value
    text = str(value).strip().replace(",", " ")
    text = re.sub(r"\s+", " ", text)
    if not text:
        return None
    for fmt in (
        "%Y-%m-%d", "%d/%m/%Y", "%d-%m-%Y", "%d.%m.%Y", "%d/%m/%y", "%d-%m-%y", "%d.%m.%y",
        "%d %b %Y", "%d %B %Y", "%d-%b-%Y", "%d-%b-%y", "%b %d %Y", "%B %d %Y",
    ):
        try:
            parsed = datetime.strptime(text, fmt).date()
        except ValueError:
            continue
        return parsed if 2000 <= parsed.year <= date.today().year + 1 else None
    try:
        return datetime.fromisoformat(text.replace("Z", "+00:00")).date()
    except ValueError:
        return None


def _money(value: Any) -> float | None:
    if value is None or value == "" or isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        return round(float(value), 2)
    text = str(value).strip()
    text = re.sub(r"/-\s*$", "", text)
    text = text.replace(",", "").replace("₹", "").replace("Rs.", "").replace("Rs", "").replace("INR", "")
    text = re.sub(r"[^\d.\-]", "", text)
    if not text or text in {".", "-"}:
        return None
    try:
        return round(float(text), 2)
    except ValueError:
        return None


def _clamp(value: Any, *, default: float) -> float:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return default
    return max(0.0, min(1.0, number))
