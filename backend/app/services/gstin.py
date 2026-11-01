"""GSTIN validation and repair.

GSTIN layout (15 chars): 2-digit state code, 10-char PAN (5 letters, 4 digits,
1 letter), entity number (1-9 or A-Z), the letter Z, and a mod-36 check char.
Every GSTIN a business holds (one per state) embeds the same PAN.
"""
from __future__ import annotations

import re

CHARSET = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
GSTIN_SHAPE = re.compile(r"^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$")
GSTIN_IN_TEXT = re.compile(r"[0-9OISBZ]{2}[A-Z0-9]{5}[0-9OISBZDGLQT]{4}[A-Z0-9][0-9A-Z][Z2][0-9A-Z]")

# Characters OCR and handwriting commonly confuse, by the type a position needs.
_TO_DIGIT = {"O": "0", "D": "0", "Q": "0", "I": "1", "L": "1", "T": "1", "Z": "2", "S": "5", "B": "8", "G": "6"}
_TO_LETTER = {"0": "O", "1": "I", "2": "Z", "5": "S", "8": "B", "6": "G"}
_DIGIT_POSITIONS = (0, 1, 7, 8, 9, 10)
_LETTER_POSITIONS = (2, 3, 4, 5, 6, 11)


def check_char(first14: str) -> str:
    total = 0
    for index, char in enumerate(first14):
        product = CHARSET.index(char) * (1 if index % 2 == 0 else 2)
        total += product // 36 + product % 36
    return CHARSET[(36 - total % 36) % 36]


def is_valid(gstin: str | None) -> bool:
    if not gstin or not GSTIN_SHAPE.match(gstin):
        return False
    return check_char(gstin[:14]) == gstin[14]


def compact(value: str | None) -> str:
    return re.sub(r"[^A-Za-z0-9]", "", value or "").upper()


def repair(value: str | None) -> str | None:
    """Return a checksum-valid GSTIN for `value`, fixing positional OCR confusions.

    Returns the cleaned 15-char string unchanged when it is already valid, a
    repaired variant when exactly one plausible fix exists, and None otherwise.
    """
    text = compact(value)
    if len(text) != 15:
        return None
    if is_valid(text):
        return text
    chars = list(text)
    for pos in _DIGIT_POSITIONS:
        chars[pos] = _TO_DIGIT.get(chars[pos], chars[pos])
    for pos in _LETTER_POSITIONS:
        chars[pos] = _TO_LETTER.get(chars[pos], chars[pos])
    if chars[13] == "2":
        chars[13] = "Z"
    shaped = "".join(chars)
    if not GSTIN_SHAPE.match(shaped):
        return None
    if is_valid(shaped):
        return shaped
    # A single misread in the check char or entity number is common; accept only an unambiguous fix.
    candidates = set()
    for pos, alphabet in ((14, CHARSET), (12, CHARSET[1:])):
        for char in alphabet:
            trial = shaped[:pos] + char + shaped[pos + 1:]
            if is_valid(trial):
                candidates.add(trial)
    return candidates.pop() if len(candidates) == 1 else None


def pan_of(gstin: str | None) -> str | None:
    text = compact(gstin)
    return text[2:12] if len(text) == 15 else None


def state_code(gstin: str | None) -> str | None:
    text = compact(gstin)
    return text[:2] if len(text) == 15 and text[:2].isdigit() else None


def find_all(text: str) -> list[str]:
    """Every GSTIN in free text, repaired where possible, in reading order, de-duplicated."""
    found: list[str] = []
    squashed = re.sub(r"[ \t]", "", text.upper())
    for match in GSTIN_IN_TEXT.finditer(squashed):
        fixed = repair(match.group(0))
        if fixed and fixed not in found:
            found.append(fixed)
    return found
