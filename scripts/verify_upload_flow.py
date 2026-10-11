"""End-to-end check that a client-shaped upload reaches the admin invoice list.

Mirrors exactly what the Flutter client posts, including the legacy field names
so a regression in either direction is visible.

Usage: python scripts/verify_upload_flow.py [base_url]
"""

import json
import sys
import uuid

import httpx

BASE = (sys.argv[1] if len(sys.argv) > 1 else "https://gst-expense-scanner.onrender.com").rstrip("/")
JPEG = bytes.fromhex(
    "ffd8ffe000104a46494600010100000100010000ffdb004300ffffffffffffffffffffffff"
    "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
    "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffc200110800"
    "01000101011100ffc40014000100000000000000000000000000000009ffda0008010100"
    "00000001bfffd9"
)


def employee_token(client: httpx.Client) -> str:
    client.post(f"{BASE}/v1/auth/otp/request", json={"mobile": "9999999999"})
    tokens = client.post(
        f"{BASE}/v1/auth/otp/verify",
        json={"mobile": "9999999999", "otp": "123456"},
    ).json()
    return tokens["accessToken"]


def client_shaped_payload(branch_id: str | None, number: str) -> dict:
    fields = {
        "vendorName": "Sri Balaji Traders",
        "gstin": "29ABCDE1234F1Z5",
        "invoiceNumber": number,
        "invoiceDate": "2026-07-30T00:00:00.000",
        "taxableValue": 1000.0,
        "cgst": 90.0,
        "sgst": 90.0,
        "igst": None,
        "discount": None,
        "netAmount": 1180.0,
        "expenseCategoryId": None,
        "expenseCategoryName": "Fuel",
        "remarks": None,
        "supplierPhone": None,
        "supplierEmail": None,
    }
    payload: dict = {"ocrConfidence": 0.82, "ocrData": fields, "editedData": fields}
    if branch_id:
        payload["branchId"] = branch_id
    payload["deviceId"] = "verify-script"
    payload["duplicateOverride"] = True
    return payload


def main() -> int:
    with httpx.Client(timeout=120.0) as client:
        headers = {"Authorization": f"Bearer {employee_token(client)}"}

        profile = client.get(f"{BASE}/v1/employees/me", headers=headers)
        branch_id = profile.json().get("branchId") if profile.status_code == 200 else None
        print(f"profile -> {profile.status_code} branchId={branch_id}")

        key = str(uuid.uuid4())
        current = client.post(
            f"{BASE}/v1/invoices/upload",
            headers=headers,
            data={
                "idempotencyKey": key,
                "payload": json.dumps(client_shaped_payload(branch_id, key[:8])),
            },
            files={
                "original": ("original.jpg", JPEG, "image/jpeg"),
                "compressed": ("compressed.jpg", JPEG, "image/jpeg"),
                "thumbnail": ("thumbnail.jpg", JPEG, "image/jpeg"),
            },
        )
        print(f"current client shape -> {current.status_code} {current.text[:200]}")

        legacy = client.post(
            f"{BASE}/v1/invoices/upload",
            headers=headers,
            data={"idempotencyKey": str(uuid.uuid4())},
            files={
                "invoice": ("invoice.json", b"{}", "application/json"),
                "image": ("invoice.jpg", JPEG, "image/jpeg"),
            },
        )
        print(f"legacy client shape  -> {legacy.status_code} {legacy.text[:120]}")

        admin = client.post(
            f"{BASE}/v1/admin/auth/login",
            json={"email": "acme@demo.com", "password": "DemoAdmin!123"},
        ).json()
        items = client.get(
            f"{BASE}/v1/admin/invoices",
            headers={"Authorization": f"Bearer {admin['accessToken']}"},
        ).json().get("items", [])
        print(f"admin sees {len(items)} invoice(s)")
        for item in items[:5]:
            print(f"  {item.get('vendorName')} | {item.get('netAmount')} | {item.get('approvalStatus')}")
        return 0 if current.status_code == 201 else 1


if __name__ == "__main__":
    raise SystemExit(main())
