"""Extract structured Indian GST invoice fields from a bill image.

Uses Google Gemini Flash (free tier) as the primary vision model. Layout varies
wildly across vendors; a vision LLM outperforms regex-on-OCR for that job.
The on-device ML Kit + regex parser remains the offline fallback in the client.
"""

from __future__ import annotations

import base64
import json
import re
from datetime import date, datetime
from typing import Any

import httpx

from app.core.config import settings

GSTIN_RE = re.compile(r"^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$")

EXTRACTION_PROMPT = """
You are an expert at reading Indian GST tax invoices / bills / cash memos.
Extract fields from the attached image. Return ONLY valid JSON matching this schema:

{
  "vendorName": string|null,
  "gstin": string|null,
  "invoiceNumber": string|null,
  "invoiceDate": "YYYY-MM-DD"|null,
  "taxableValue": number|null,
  "cgst": number|null,
  "sgst": number|null,
  "igst": number|null,
  "discount": number|null,
  "netAmount": number|null,
  "supplierPhone": string|null,
  "supplierEmail": string|null,
  "confidence": number,
  "notes": string|null
}

Rules:
- vendorName is the SELLER / supplier business name (not the buyer).
- gstin is the SELLER GSTIN (15 chars). Ignore buyer GSTIN.
- invoiceNumber is the bill/invoice/tax invoice number (not IRN, not e-way).
- invoiceDate as YYYY-MM-DD. Accept dd/mm/yyyy, dd-mm-yyyy, dd.mm.yyyy on the bill.
- Amounts are numbers only (no currency symbols, no commas).
- taxableValue = taxable / taxable value / assessable value before GST.
- Prefer grand total / net payable / amount payable for netAmount.
- If only IGST is present, set igst and leave cgst/sgst null (and vice versa).
- supplierPhone / supplierEmail are SELLER contact details when printed on the bill.
- confidence is 0.0–1.0 for how sure you are overall.
- If a field is unreadable, use null. Never invent a GSTIN or invoice number.
- Do not wrap the JSON in markdown.
""".strip()

RESPONSE_SCHEMA: dict[str, Any] = {
    "type": "object",
    "properties": {
        "vendorName": {"type": "string", "nullable": True},
        "gstin": {"type": "string", "nullable": True},
        "invoiceNumber": {"type": "string", "nullable": True},
        "invoiceDate": {"type": "string", "nullable": True},
        "taxableValue": {"type": "number", "nullable": True},
        "cgst": {"type": "number", "nullable": True},
        "sgst": {"type": "number", "nullable": True},
        "igst": {"type": "number", "nullable": True},
        "discount": {"type": "number", "nullable": True},
        "netAmount": {"type": "number", "nullable": True},
        "supplierPhone": {"type": "string", "nullable": True},
        "supplierEmail": {"type": "string", "nullable": True},
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


FALLBACK_MODELS = (
    "gemini-3.5-flash",
    "gemini-flash-latest",
    "gemini-2.5-flash-lite",
    "gemini-2.0-flash",
    "gemini-1.5-flash",
)


async def extract_invoice_fields(
    image_bytes: bytes,
    *,
    mime_type: str = "image/jpeg",
) -> dict[str, Any]:
    if not ai_extract_configured():
        raise AiExtractError(
            "AI extraction is not configured. Set GEMINI_API_KEY on the server "
            "(free key from https://aistudio.google.com/apikey).",
            status_code=503,
        )
    if not image_bytes:
        raise AiExtractError("Empty image", status_code=400)
    if len(image_bytes) > 8 * 1024 * 1024:
        raise AiExtractError("Image too large for AI extraction (max 8 MB)", status_code=400)

    raw, model_used = await _call_gemini(image_bytes, mime_type)
    result = _normalize(raw)
    result["model"] = model_used
    return result


def _candidate_models() -> list[str]:
    preferred = (settings.gemini_model or "").strip()
    models: list[str] = []
    if preferred:
        models.append(preferred)
    for name in FALLBACK_MODELS:
        if name not in models:
            models.append(name)
    return models


async def _call_gemini(image_bytes: bytes, mime_type: str) -> tuple[dict[str, Any], str]:
    payload = {
        "contents": [
            {
                "role": "user",
                "parts": [
                    {"text": EXTRACTION_PROMPT},
                    {
                        "inline_data": {
                            "mime_type": mime_type,
                            "data": base64.b64encode(image_bytes).decode("ascii"),
                        }
                    },
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
    async with httpx.AsyncClient(timeout=60.0) as client:
        for model in _candidate_models():
            url = (
                f"https://generativelanguage.googleapis.com/v1beta/models/"
                f"{model}:generateContent"
            )
            try:
                response = await client.post(
                    url,
                    params={"key": settings.gemini_api_key},
                    json=payload,
                )
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
                    for tip in (
                        "no longer available",
                        "not found",
                        "high demand",
                        "quota",
                        "overloaded",
                        "try again later",
                        "unsupported",
                    )
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

    if "rate limit" in last_error.lower() or "high demand" in last_error.lower():
        raise AiExtractError(
            "AI free-tier is busy or rate-limited. Try again in a minute, or continue offline.",
            status_code=429,
        )
    raise AiExtractError(f"AI extraction failed: {last_error}", status_code=502)

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


def _normalize(raw: dict[str, Any]) -> dict[str, Any]:
    gstin = _clean_gstin(raw.get("gstin"))
    invoice_date = _parse_date(raw.get("invoiceDate"))
    confidence = _clamp(raw.get("confidence"), default=0.7)

    fields = {
        "vendorName": _clean_str(raw.get("vendorName")),
        "gstin": gstin,
        "invoiceNumber": _clean_str(raw.get("invoiceNumber")),
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

    # Soft arithmetic check — if totals look wrong, lower confidence so the
    # review screen highlights the draft for manual correction.
    if not _amounts_plausible(fields):
        confidence = min(confidence, 0.55)

    present = sum(1 for value in fields.values() if value not in (None, ""))
    if present < 3:
        confidence = min(confidence, 0.4)

    return {
        **fields,
        "confidence": confidence,
        "provider": "gemini",
        "model": settings.gemini_model,
        "notes": _clean_str(raw.get("notes")),
    }


def _amounts_plausible(fields: dict[str, Any]) -> bool:
    taxable = fields.get("taxableValue")
    net = fields.get("netAmount")
    if taxable is None or net is None:
        return True
    tax = sum(
        value or 0.0
        for value in (fields.get("cgst"), fields.get("sgst"), fields.get("igst"))
    )
    discount = fields.get("discount") or 0.0
    expected = taxable + tax - discount
    return abs(expected - net) <= max(2.0, 0.02 * max(net, 1.0))


def _clean_str(value: Any) -> str | None:
    if value is None:
        return None
    text = str(value).strip()
    if not text or text.lower() in {"null", "none", "n/a", "-"}:
        return None
    return text


def _clean_phone(value: Any) -> str | None:
    text = _clean_str(value)
    if not text:
        return None
    digits = re.sub(r"\D", "", text)
    if digits.startswith("91") and len(digits) == 12:
        digits = digits[2:]
    if len(digits) == 10 and digits[0] in "6789":
        return digits
    return None


def _clean_email(value: Any) -> str | None:
    text = _clean_str(value)
    if not text or "@" not in text:
        return None
    return text.lower()


def _clean_gstin(value: Any) -> str | None:
    text = _clean_str(value)
    if not text:
        return None
    compact = re.sub(r"[^A-Za-z0-9]", "", text).upper()
    if GSTIN_RE.match(compact):
        return compact
    # Keep unvalidated value so the user can correct it on review — but mark
    # it only when it looks roughly right.
    return compact if len(compact) == 15 else None


def _parse_date(value: Any) -> date | None:
    if value is None:
        return None
    if isinstance(value, date) and not isinstance(value, datetime):
        return value
    text = str(value).strip()
    if not text:
        return None
    for fmt in ("%Y-%m-%d", "%d/%m/%Y", "%d-%m-%Y", "%d.%m.%Y", "%d %b %Y", "%d %B %Y"):
        try:
            return datetime.strptime(text, fmt).date()
        except ValueError:
            continue
    try:
        return datetime.fromisoformat(text.replace("Z", "+00:00")).date()
    except ValueError:
        return None


def _money(value: Any) -> float | None:
    if value is None or value == "":
        return None
    if isinstance(value, (int, float)):
        return round(float(value), 2)
    text = str(value)
    text = text.replace(",", "").replace("₹", "").replace("Rs.", "").replace("INR", "")
    text = re.sub(r"[^\d.\-]", "", text)
    if not text:
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
