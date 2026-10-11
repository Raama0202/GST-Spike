"""Real-HTTP smoke test across every surface, using the exact request shapes each client sends.

Super admin (web) -> company admin (web / Flutter admin / iOS admin) -> employees on
Android and iOS -> admin review -> employee notifications -> ITC -> billing -> lifecycle.

Needs a dev-mode server (fixed OTP) with seed data:
    python scripts/smoke_all_surfaces.py http://localhost:8000 [web-admin-origin]

Creates its own company, so it is safe to rerun. Never point it at production.
"""

import io
import json
import sys
import time
import uuid
from pathlib import Path

import httpx

BASE = (sys.argv[1] if len(sys.argv) > 1 else "http://localhost:8000").rstrip("/")
WEB_ORIGIN = sys.argv[2] if len(sys.argv) > 2 else "http://localhost:5173"
API = f"{BASE}/v1"
OTP = "123456"
SUPER = ("admin@gstexpenses.app", "ChangeMeNow!123")
FIXTURE = Path(__file__).resolve().parent.parent / "test" / "fixtures" / "vijayawada_tax_invoice.png"

RUN = uuid.uuid4().hex[:6]
results: list[tuple[str, bool, str]] = []


def check(name: str, ok: bool, detail: str = "") -> bool:
    results.append((name, ok, detail))
    print(f"[{'PASS' if ok else 'FAIL'}] {name}" + (f"  ({detail})" if detail and not ok else ""))
    return ok


def bearer(token: str, company_id: str | None = None, device: str = "smoke") -> dict:
    headers = {"Authorization": f"Bearer {token}", "X-Device-Id": device}
    if company_id:
        headers["X-Company-Id"] = company_id
    return headers


def jpeg_bytes() -> bytes:
    try:
        from PIL import Image

        buf = io.BytesIO()
        Image.open(FIXTURE).convert("RGB").save(buf, "JPEG", quality=80)
        return buf.getvalue()
    except Exception:
        return b"\xff\xd8\xff\xe0" + FIXTURE.read_bytes()[:4096] + b"\xff\xd9"


def fields(number: str, gstin: str, vendor: str, net: float, date_iso: str) -> dict:
    return {
        "vendorName": vendor, "gstin": gstin, "invoiceNumber": number, "invoiceDate": date_iso,
        "taxableValue": round(net / 1.18, 2), "cgst": round(net * 0.09 / 1.18, 2), "sgst": round(net * 0.09 / 1.18, 2),
        "igst": None, "discount": None, "netAmount": net, "expenseCategoryId": None,
        "expenseCategoryName": "Cement", "remarks": None, "supplierPhone": "9848012345", "supplierEmail": None,
    }


def upload(c: httpx.Client, headers: dict, key: str, payload: dict, image: bytes) -> httpx.Response:
    return c.post(
        f"{API}/invoices/upload", headers=headers,
        data={"idempotencyKey": key, "payload": json.dumps(payload)},
        files={
            "original": ("original.jpg", image, "image/jpeg"),
            "compressed": ("compressed.jpg", image, "image/jpeg"),
            "thumbnail": ("thumbnail.jpg", image, "image/jpeg"),
        },
    )


def employee_login(c: httpx.Client, mobile: str, device: str, platform: str) -> dict | None:
    r = c.post(f"{API}/auth/otp/request", json={"mobile": mobile})
    if not check(f"{platform} employee: OTP request", r.status_code in (200, 204), r.text):
        return None
    r = c.post(f"{API}/auth/otp/verify", json={"mobile": mobile, "otp": OTP, "deviceId": device, "platform": platform})
    if not check(f"{platform} employee: OTP verify", r.status_code == 200 and "accessToken" in r.json(), r.text):
        return None
    return r.json()


def main() -> int:
    image = jpeg_bytes()
    with httpx.Client(timeout=60.0) as c:
        t0 = time.perf_counter()
        check("API /health", c.get(f"{BASE}/health").status_code == 200)
        r = c.get(f"{BASE}/ready")
        check("API /ready (database reachable)", r.status_code == 200, r.text)

        r = c.options(f"{API}/admin/auth/login", headers={
            "Origin": WEB_ORIGIN, "Access-Control-Request-Method": "POST",
            "Access-Control-Request-Headers": "authorization,content-type,x-company-id",
        })
        check(f"CORS preflight from web admin origin {WEB_ORIGIN}",
              r.status_code == 200 and r.headers.get("access-control-allow-origin") == WEB_ORIGIN, f"{r.status_code}")

        # --- Super admin (web console) ---
        r = c.post(f"{API}/admin/auth/login", json={"email": SUPER[0], "password": SUPER[1]})
        if not check("Super admin: login", r.status_code == 200 and r.json()["user"]["role"] == "super_admin", r.text):
            return summary()
        su = bearer(r.json()["accessToken"])

        plans = c.get(f"{API}/super/plans", headers=su).json()["items"]
        check("Super admin: list plans", {"starter", "growth", "enterprise"} <= {p["code"] for p in plans})
        plan_code = f"smoke{RUN}"
        r = c.post(f"{API}/super/plans", headers=su, json={
            "code": plan_code, "name": f"Smoke {RUN}", "monthlyPriceInr": 499, "maxEmployees": 3, "features": {"galleryImport": True},
        })
        check("Super admin: create plan", r.status_code in (200, 201), r.text)

        admin_email, admin_pw = f"owner{RUN}@smoke.in", "OwnerPass!23"
        r = c.post(f"{API}/super/companies", headers=su, json={
            "name": f"Smoke Traders {RUN}", "industry": "Retail", "adminEmail": admin_email,
            "adminPassword": admin_pw, "planCode": plan_code, "seats": 3, "subscriptionDays": 30,
        })
        if not check("Super admin: create company", r.status_code == 201, r.text):
            return summary()
        company = r.json()

        r = c.post(f"{API}/admin/auth/login", json={"email": admin_email, "password": admin_pw})
        check("Company admin: blocked before activation", r.status_code in (402, 403), f"{r.status_code}")
        r = c.post(f"{API}/super/companies/activate", json={"activationCode": company["activationCode"]})
        check("Company: activate with activation code (public)", r.status_code == 200 and r.json().get("status") == "active", r.text)
        r = c.get(f"{API}/super/companies", headers=su, params={"q": RUN})
        check("Super admin: company listed as active", r.json()["total"] == 1 and r.json()["items"][0]["status"] == "active")

        # --- Company admin (web / Android admin / iOS admin) ---
        r = c.post(f"{API}/admin/auth/login", json={"email": admin_email, "password": admin_pw})
        if not check("Company admin: login", r.status_code == 200, r.text):
            return summary()
        owner = r.json()
        company_id = owner["user"]["companyId"]
        adm = bearer(owner["accessToken"], company_id)

        r = c.post(f"{API}/admin/company/branches", headers=adm, json={"name": "Vijayawada", "code": "VJA"})
        check("Company admin: create branch", r.status_code == 201, r.text)
        branch_id = r.json().get("id")
        r = c.post(f"{API}/admin/company/categories", headers=adm, json={"name": "Cement", "sortOrder": 1})
        check("Company admin: create category", r.status_code == 201, r.text)
        category_id = r.json().get("id")
        r = c.patch(f"{API}/admin/company/settings", headers=adm, json={"primaryColorHex": "0B5FFF", "duplicateCheckEnabled": True})
        check("Company admin: update settings", r.status_code == 200, r.text)

        android_mobile = "9" + str(int(uuid.uuid4().int % 10**9)).zfill(9)
        ios_mobile = "8" + str(int(uuid.uuid4().int % 10**9)).zfill(9)
        for name, mobile, code in (("Android Ravi", android_mobile, "SM-1"), ("iOS Priya", ios_mobile, "SM-2")):
            r = c.post(f"{API}/admin/employees", headers=adm, json={"name": name, "mobile": mobile, "employeeCode": f"{code}-{RUN}", "branchId": branch_id})
            check(f"Company admin: add employee {name}", r.status_code == 201, r.text)
        r = c.post(f"{API}/admin/employees", headers=adm, json={"name": "Seat 3", "mobile": "7" + str(uuid.uuid4().int % 10**9).zfill(9)})
        r = c.post(f"{API}/admin/employees", headers=adm, json={"name": "Seat 4", "mobile": "6" + str(uuid.uuid4().int % 10**9).zfill(9)})
        check("Company admin: seat limit enforced (4th employee on 3-seat plan)", r.status_code in (402, 403, 409, 400), f"{r.status_code} {r.text[:120]}")

        # --- Employee on Android (Flutter) ---
        a = employee_login(c, android_mobile, "android-device-1", "android")
        if not a:
            return summary()
        emp_a = bearer(a["accessToken"], company_id, "android-device-1")
        check("Android employee: /employees/me", c.get(f"{API}/employees/me", headers=emp_a).json().get("name") == "Android Ravi")
        cfg = c.get(f"{API}/company/config", headers=emp_a).json()
        check("Android employee: company config has admin's branch, category, colour",
              cfg.get("primaryColorHex") == "0B5FFF" and branch_id in [b["id"] for b in cfg["branches"]]
              and category_id in [x["id"] for x in cfg["categories"]])
        r = c.post(f"{API}/devices/register", headers=emp_a, json={"deviceId": "android-device-1", "platform": "android", "appVersion": "1.0.0", "fcmToken": None})
        check("Android employee: device register", r.status_code in (200, 201), r.text)
        r = c.get(f"{API}/invoices/extract/status", headers=emp_a)
        check("Android employee: AI extract status endpoint", r.status_code == 200, r.text)

        inv_a = fields(f"SVE-{RUN}-1", "37AABCT1332L1ZV", "SRI VIJAYALAKSHMI ENTERPRISES", 11800.0, "2026-10-01T00:00:00.000")
        r = c.post(f"{API}/invoices/duplicate-check", headers=emp_a, json={
            "gstin": inv_a["gstin"], "invoiceNumber": inv_a["invoiceNumber"], "invoiceDate": "2026-10-01", "netAmount": inv_a["netAmount"],
        })
        check("Android employee: duplicate check (new bill)", r.status_code == 200 and r.json()["isDuplicate"] is False, r.text)
        android_payload = {
            "branchId": branch_id, "categoryId": category_id, "deviceId": "android-device-1",
            "ocrConfidence": 0.87, "ocrData": inv_a, "editedData": inv_a, "duplicateOverride": False,
        }
        key_a = str(uuid.uuid4())
        r = upload(c, emp_a, key_a, android_payload, image)
        check("Android employee: upload real invoice photo", r.status_code == 201, r.text)
        inv_a_id = r.json().get("id")
        r = upload(c, emp_a, key_a, android_payload, image)
        check("Android employee: offline-queue retry is idempotent", r.status_code == 201 and r.json().get("id") == inv_a_id, r.text)
        r = upload(c, emp_a, str(uuid.uuid4()), android_payload, image)
        check("Android employee: same bill re-captured is rejected as duplicate", r.status_code == 409, f"{r.status_code}")

        # --- Employee on iOS (SwiftUI) ---
        i = employee_login(c, ios_mobile, "ios-device-1", "ios")
        if not i:
            return summary()
        emp_i = bearer(i["accessToken"], company_id, "ios-device-1")
        r = c.post(f"{API}/devices/register", headers=emp_i, json={"deviceId": "ios-device-1", "platform": "ios", "appVersion": "1.0.0", "fcmToken": None})
        check("iOS employee: device register", r.status_code in (200, 201), r.text)
        inv_i = fields(f"TT-{RUN}-9", "36ABCDE1234F1Z5", "Taj Travels", 5900.0, "2026-10-02T00:00:00")
        ios_payload = {
            "branchId": branch_id, "deviceId": "ios-device-1", "latitude": 16.5062, "longitude": 80.648,
            "ocrConfidence": 0.93, "ocrData": inv_i, "editedData": inv_i, "duplicateOverride": False,
        }
        r = upload(c, emp_i, str(uuid.uuid4()), ios_payload, image)
        check("iOS employee: upload with GPS", r.status_code == 201, r.text)
        inv_i_id = r.json().get("id")

        # --- Admin reviews ---
        dash = c.get(f"{API}/admin/dashboard", headers=adm).json()
        check("Admin: dashboard pending count = 2", dash.get("pendingCount") == 2, json.dumps(dash)[:200])
        listing = c.get(f"{API}/admin/invoices", headers=adm, params={"status": "pending", "page": 1, "pageSize": 25}).json()
        check("Admin: both platform uploads in pending list", {inv_a_id, inv_i_id} <= {x["id"] for x in listing["items"]})
        detail = c.get(f"{API}/admin/invoices/{inv_a_id}", headers=adm).json()
        check("Admin: invoice detail carries OCR fields", detail.get("vendorName") == inv_a["vendorName"], json.dumps(detail)[:200])
        img_url = detail.get("imageUrl") or ""
        img = c.get(img_url if img_url.startswith("http") else BASE + img_url)
        check("Admin: invoice image loads (media URL)", img.status_code == 200 and img.content[:3] == b"\xff\xd8\xff", f"{img.status_code} {img_url}")
        r = c.post(f"{API}/admin/invoices/{inv_a_id}/reject", headers=adm, json={"remarks": None})
        check("Admin: reject without remarks refused", r.status_code == 400, f"{r.status_code}")
        r = c.post(f"{API}/admin/invoices/{inv_a_id}/return", headers=adm, json={"remarks": "Photo the GST section clearly"})
        check("Admin: return with remarks", r.status_code == 200 and r.json().get("approvalStatus") == "returned", r.text)
        r = c.post(f"{API}/admin/invoices/{inv_a_id}/approve", headers=adm, json={})
        check("Admin: approve", r.status_code == 200 and r.json().get("approvalStatus") == "approved", r.text)
        r = c.post(f"{API}/admin/invoices/{inv_i_id}/reject", headers=adm, json={"remarks": "Personal travel"})
        check("Admin: reject iOS bill", r.status_code == 200 and r.json().get("approvalStatus") == "rejected", r.text)

        # --- Employees see decisions ---
        mine_a = c.get(f"{API}/invoices/mine", headers=emp_a).json()["items"]
        check("Android employee: sees approved status + local key", mine_a and mine_a[0]["approvalStatus"] == "approved" and mine_a[0].get("localIdempotencyKey") == key_a)
        mine_i = c.get(f"{API}/invoices/mine", headers=emp_i).json()["items"]
        check("iOS employee: sees rejected status + remarks", mine_i and mine_i[0]["approvalStatus"] == "rejected" and mine_i[0].get("adminRemarks") == "Personal travel")
        check("Tenant isolation: Android employee cannot see iOS employee's bills", inv_i_id not in {x["id"] for x in mine_a})

        r = c.post(f"{API}/admin/notifications/announcements", headers=adm, json={"title": "Month end", "body": f"Submit bills by Friday {RUN}"})
        check("Admin: send announcement", r.status_code == 201 and r.json().get("created") == 2, r.text)
        notes_a = c.get(f"{API}/notifications", headers=emp_a).json()["items"]
        check("Android employee: notifications (approved, returned, announcement)",
              {"billApproved", "billReturned", "companyAnnouncement"} <= {n["type"] for n in notes_a}, str({n["type"] for n in notes_a}))
        notes_i = c.get(f"{API}/notifications", headers=emp_i).json()["items"]
        check("iOS employee: notifications (rejected, announcement)", {"billRejected", "companyAnnouncement"} <= {n["type"] for n in notes_i})
        r = c.post(f"{API}/notifications/read", headers=emp_a, json={"ids": [n["id"] for n in notes_a]})
        check("Android employee: mark notifications read", r.status_code == 200, r.text)
        hist = c.get(f"{API}/admin/notifications/announcements", headers=adm).json()["items"]
        check("Admin: announcement history shows read receipts", hist and hist[0]["recipients"] == 2 and hist[0]["read"] >= 1, json.dumps(hist[:1]))

        # --- ITC reconciliation (GSTR-2B import) ---
        period = "2026-10"
        csv = ("GSTIN of supplier,Trade/Legal name,Invoice number,Invoice Date,Taxable Value,CGST,SGST,IGST,Invoice Value\n"
               f"37AABCT1332L1ZV,SRI VIJAYALAKSHMI ENTERPRISES,SVE-{RUN}-1,01-10-2026,10000,900,900,0,11800\n"
               f"29AAACR5055K1Z5,Missing Supplier,MS-{RUN},05-10-2026,1000,90,90,0,1180\n")
        r = c.post(f"{API}/admin/itc/import", headers=adm, data={"period": period, "returnType": "2B"},
                   files={"file": ("gstr2b.csv", csv.encode(), "text/csv")})
        check("Admin: ITC GSTR-2B CSV import", r.status_code in (200, 201) and r.json().get("rowCount") == 2, r.text)
        r = c.post(f"{API}/admin/itc/reconcile", headers=adm, params={"period": period, "returnType": "2B"})
        check("Admin: ITC reconcile", r.status_code == 200, r.text)
        counts = c.get(f"{API}/admin/itc/summary", headers=adm, params={"period": period, "returnType": "2B"}).json().get("counts", {})
        check("Admin: ITC summary has matched + missing-in-books", sum(counts.values()) >= 2, json.dumps(counts))
        r = c.get(f"{API}/admin/itc/matches/export", headers=adm, params={"period": period, "returnType": "2B", "status": "all"})
        check("Admin: ITC export CSV", r.status_code == 200 and "csv" in r.json(), r.text[:150])

        # --- Billing (Razorpay) ---
        r = c.get(f"{API}/admin/billing", headers=adm)
        billing = r.json() if r.status_code == 200 else {}
        check("Admin: billing overview", r.status_code == 200, r.text)
        r = c.post(f"{API}/admin/billing/orders", headers=adm, json={"planCode": plan_code, "seats": 3, "months": 1})
        check("Admin: billing order " + ("created" if billing.get("paymentsEnabled") else "returns 503 until Razorpay keys are set"),
              r.status_code in ((200, 201) if billing.get("paymentsEnabled") else (503,)), f"{r.status_code}")
        r = c.get(f"{API}/super/payments", headers=su)
        check("Super admin: payments list", r.status_code == 200, r.text)

        # --- Security & lifecycle ---
        acme = c.post(f"{API}/admin/auth/login", json={"email": "acme@demo.com", "password": "DemoAdmin!123"}).json()
        r = c.get(f"{API}/admin/invoices/{inv_a_id}", headers=bearer(acme["accessToken"], acme["user"]["companyId"]))
        check("Tenant isolation: other company's admin cannot open this invoice", r.status_code in (403, 404), f"{r.status_code}")
        r = c.get(f"{API}/admin/invoices/{inv_a_id}", headers=bearer(acme["accessToken"], company_id))
        check("Tenant isolation: spoofed X-Company-Id rejected", r.status_code in (400, 403, 404), f"{r.status_code}")
        check("Role check: company admin blocked from super routes", c.get(f"{API}/super/companies", headers=adm).status_code == 403)
        check("Role check: employee blocked from admin routes", c.get(f"{API}/admin/invoices", headers=emp_a).status_code in (401, 403))
        check("Auth: no token -> 401", c.get(f"{API}/admin/invoices").status_code == 401)

        new_pw = "NewOwnerPass!456"
        r = c.post(f"{API}/admin/auth/password", headers=adm, json={"currentPassword": admin_pw, "newPassword": new_pw})
        check("Company admin: change password", r.status_code == 200, r.text)
        r = c.post(f"{API}/admin/auth/login", json={"email": admin_email, "password": new_pw})
        check("Company admin: login with new password", r.status_code == 200, r.text)
        owner2 = r.json()
        adm = bearer(owner2["accessToken"], company_id)

        r = c.post(f"{API}/auth/token/refresh", json={"refreshToken": a["refreshToken"]})
        check("Token refresh (employee)", r.status_code == 200, r.text)
        a2 = r.json()
        r = c.post(f"{API}/auth/token/refresh", json={"refreshToken": a["refreshToken"]})
        check("Token refresh: old refresh token cannot be replayed", r.status_code == 401, f"{r.status_code}")

        r = c.post(f"{API}/super/companies/{company['id']}/suspend", headers=su)
        check("Super admin: suspend company", r.status_code == 200, r.text)
        check("Suspended: company admin locked out", c.get(f"{API}/admin/dashboard", headers=adm).status_code in (402, 403))
        r = c.post(f"{API}/auth/otp/request", json={"mobile": android_mobile})
        check("Suspended: employee OTP blocked", r.status_code in (402, 403), f"{r.status_code}")
        r = upload(c, bearer(a2["accessToken"], company_id, "android-device-1"), str(uuid.uuid4()),
                   {**android_payload, "editedData": fields(f"X-{RUN}", "37AABCT1332L1ZV", "X", 100.0, "2026-10-03T00:00:00.000")}, image)
        check("Suspended: employee upload blocked", r.status_code in (402, 403), f"{r.status_code}")
        r = c.post(f"{API}/super/companies/{company['id']}/reactivate", headers=su)
        check("Super admin: reactivate company", r.status_code == 200, r.text)
        check("Reactivated: admin access restored", c.get(f"{API}/admin/dashboard", headers=adm).status_code == 200)
        r = c.post(f"{API}/super/companies/{company['id']}/subscription/extend", headers=su, json={"days": 30})
        check("Super admin: extend subscription", r.status_code == 200, r.text)

        statuses = [c.post(f"{API}/admin/auth/login", json={"email": f"nobody{RUN}@x.in", "password": "wrong"}).status_code for _ in range(7)]
        check("Rate limit: repeated bad logins get 429", 429 in statuses, str(statuses))

        r = c.post(f"{API}/auth/logout", json={"refreshToken": a2["refreshToken"]})
        check("Employee logout", r.status_code in (200, 204), f"{r.status_code}")
        r = c.post(f"{API}/auth/token/refresh", json={"refreshToken": a2["refreshToken"]})
        check("Logged-out refresh token rejected", r.status_code == 401, f"{r.status_code}")

        print(f"\nTotal time {time.perf_counter() - t0:.1f}s")
    return summary()


def summary() -> int:
    failed = [r for r in results if not r[1]]
    print(f"\n{len(results) - len(failed)}/{len(results)} checks passed")
    for name, _, detail in failed:
        print(f"  FAIL {name}: {detail[:300]}")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
