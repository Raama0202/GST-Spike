"""Tell the scanning company apart from the supplier on a bill.

A GST tax invoice names two businesses: the supplier who issued it and the
recipient ("Bill to" / "Buyer"), which is normally the company scanning it.
The vendor recorded for the expense must be the party that is *not* the
company in its profile. A party is "own" when its GSTIN is one of the
company's GSTINs, shares the company's PAN under one of the company's names
(same business, another state), or — without a GSTIN — its name matches the
company's legal name, display name or aliases. A party that only shares the
PAN under a different name is kept as a last-resort supplier rather than
discarded, so a bill never ends up with no vendor at all.
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field
from difflib import SequenceMatcher
from typing import Any

from app.services import gstin as gst

_NOISE_WORDS = {
    "M", "S", "MS", "M/S", "MESSRS", "THE", "PVT", "PRIVATE", "LTD", "LIMITED", "LLP", "CO", "COMPANY",
    "CORP", "CORPORATION", "INC", "OPC", "AND", "&", "INDIA",
}


def normalize_name(value: str | None) -> str:
    text = re.sub(r"[^A-Z0-9& ]", " ", (value or "").upper().replace("M/S", " "))
    words = [w for w in text.split() if w not in _NOISE_WORDS]
    return " ".join(words)


def names_match(a: str | None, b: str | None) -> bool:
    left, right = normalize_name(a), normalize_name(b)
    if not left or not right:
        return False
    if left == right:
        return True
    shorter, longer = sorted((left, right), key=len)
    # "SUNRISE TRADERS" vs "SUNRISE TRADERS HYDERABAD BRANCH"
    if len(shorter.split()) >= 2 and f" {shorter} " in f" {longer} ":
        return True
    return SequenceMatcher(None, left, right).ratio() >= 0.88


@dataclass
class CompanyIdentity:
    names: list[str] = field(default_factory=list)
    gstins: set[str] = field(default_factory=set)
    pans: set[str] = field(default_factory=set)

    @classmethod
    def from_company(cls, company: dict[str, Any] | None) -> CompanyIdentity:
        if not company:
            return cls()
        names = [company.get("name"), company.get("legal_name"), *(company.get("name_aliases") or [])]
        gstins = {g for g in (gst.compact(x) for x in [company.get("gstin"), *(company.get("additional_gstins") or [])]) if len(g) == 15}
        pans = {p for p in (gst.pan_of(g) for g in gstins) if p}
        return cls(names=[n.strip() for n in names if n and n.strip()], gstins=gstins, pans=pans)

    @property
    def empty(self) -> bool:
        return not (self.names or self.gstins)

    def gstin_match(self, value: str | None) -> str | None:
        """"exact" for one of the company's GSTINs, "pan" when only the PAN matches, else None."""
        text = gst.compact(value)
        if len(text) != 15:
            return None
        if text in self.gstins:
            return "exact"
        return "pan" if gst.pan_of(text) in self.pans else None

    def owns_gstin(self, value: str | None) -> bool:
        return self.gstin_match(value) is not None

    def owns_name(self, value: str | None) -> bool:
        return any(names_match(value, own) for own in self.names)

    def owns(self, name: str | None, gstin: str | None) -> bool:
        match = self.gstin_match(gstin)
        if match == "exact":
            return True
        if match == "pan":
            return not name or self.owns_name(name)
        if len(gst.compact(gstin)) == 15:
            return False
        return self.owns_name(name)

    def same_pan_only(self, name: str | None, gstin: str | None) -> bool:
        return self.gstin_match(gstin) == "pan" and not self.owns(name, gstin)

    def prompt_hint(self) -> str:
        if self.empty:
            return ""
        lines = ["The company that scanned this bill is the BUYER / recipient, never the vendor:"]
        if self.names:
            lines.append(f"- Names: {'; '.join(dict.fromkeys(self.names))}")
        if self.gstins:
            lines.append(f"- GSTIN(s): {', '.join(sorted(self.gstins))}")
        lines.append("Return the OTHER business (the one that issued the bill) as vendorName/gstin.")
        return "\n".join(lines)


def resolve_vendor(fields: dict[str, Any], parties: list[dict[str, Any]], identity: CompanyIdentity) -> dict[str, Any]:
    """Make vendorName/gstin the non-company party; record the buyer separately.

    `parties` are {name, gstin, role} dicts read from the bill (role: seller | buyer | unknown).
    Mutates and returns `fields`, adding buyerName/buyerGstin/buyerIsCompany and
    `vendorCorrected` when the extractor had picked the company itself.
    """
    parties = [p for p in parties if (p.get("name") or p.get("gstin"))]
    if identity.empty:
        own: list[dict[str, Any]] = []
        same_pan: list[dict[str, Any]] = []
    else:
        own = [p for p in parties if identity.owns(p.get("name"), p.get("gstin"))]
        same_pan = [p for p in parties if p not in own and identity.same_pan_only(p.get("name"), p.get("gstin"))]
    others = [p for p in parties if p not in own and p not in same_pan]

    def by_role(group: list[dict[str, Any]]) -> list[dict[str, Any]]:
        return [p for p in group if p.get("role") == "seller"] + [p for p in group if p.get("role") != "seller"]

    sellers = by_role(others) + [p for p in by_role(same_pan) if p.get("role") != "buyer"]

    vendor_name, vendor_gstin = fields.get("vendorName"), fields.get("gstin")
    match = None if identity.empty else identity.gstin_match(vendor_gstin)
    name_own = not identity.empty and identity.owns_name(vendor_name)
    gstin_own = match == "exact" or (match == "pan" and (name_own or not vendor_name))
    other_valid_gstin = len(gst.compact(vendor_gstin)) == 15 and match is None

    corrected = False
    if match == "exact" and vendor_name and not name_own:
        # Right supplier name, but the buyer's GSTIN was copied next to it.
        party = next((p for p in sellers if p.get("gstin") and names_match(p.get("name"), vendor_name)), None)
        party = party or next((p for p in sellers if p.get("gstin")), None)
        fields["gstin"] = party.get("gstin") if party else None
        corrected = True
    elif gstin_own or (name_own and not other_valid_gstin):
        replacement = sellers[0] if sellers else None
        fields["vendorName"] = replacement.get("name") if replacement else None
        fields["gstin"] = replacement.get("gstin") if replacement else None
        corrected = True
    elif name_own and other_valid_gstin:
        # The supplier's GSTIN with the company's own name beside it: take the name of that GSTIN's party.
        party = next((p for p in others if gst.compact(p.get("gstin")) == gst.compact(vendor_gstin)), None)
        party = party or next((p for p in sellers if p.get("name")), None)
        if party and party.get("name"):
            fields["vendorName"] = party["name"]
            corrected = True
    if not fields.get("gstin") and fields.get("vendorName"):
        same = next((p for p in sellers if p.get("gstin") and names_match(p.get("name"), fields["vendorName"])), None)
        if same:
            fields["gstin"] = same["gstin"]

    buyer = own[0] if own else next((p for p in others if p.get("role") == "buyer" and not names_match(p.get("name"), fields.get("vendorName"))), None)
    if buyer:
        fields["buyerName"] = buyer.get("name") or fields.get("buyerName")
        fields["buyerGstin"] = buyer.get("gstin") or fields.get("buyerGstin")
    if not identity.empty and (fields.get("buyerName") or fields.get("buyerGstin")):
        fields["buyerIsCompany"] = identity.owns(fields.get("buyerName"), fields.get("buyerGstin"))
    if corrected:
        fields["vendorCorrected"] = True
    return fields
