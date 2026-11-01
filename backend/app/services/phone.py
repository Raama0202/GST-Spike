"""Mobile numbers are stored in one canonical form so logins match however they were typed."""
import re

_SEPARATORS = re.compile(r"[\s\-().]")
_VALID = re.compile(r"^\+?[0-9]{10,15}$")


def canonical_mobile(value: str) -> str:
    """Indian numbers become 10 digits (+91 98765 43210, 919876543210, 09876543210);
    other international numbers keep their leading +."""
    cleaned = _SEPARATORS.sub("", value.strip())
    if not _VALID.fullmatch(cleaned):
        raise ValueError("Enter a valid mobile number (10-15 digits, optional leading +)")
    digits = cleaned.lstrip("+")
    if len(digits) == 12 and digits.startswith("91"):
        return digits[2:]
    if len(digits) == 11 and digits.startswith("0"):
        return digits[1:]
    if len(digits) == 10:
        return digits
    return f"+{digits}" if cleaned.startswith("+") else digits


def mobile_variants(mobile: str) -> list[str]:
    """Spellings older records may have been saved with."""
    canonical = canonical_mobile(mobile)
    if len(canonical) != 10:
        return [canonical, canonical.lstrip("+")]
    return [canonical, f"91{canonical}", f"+91{canonical}", f"0{canonical}"]
