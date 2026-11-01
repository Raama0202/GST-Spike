"""Register an employee mobile so it can receive a login OTP.

Employees normally come from the admin app; this exists so a developer can put
their own phone number into the seeded demo company without a UI round-trip.

Usage:
    py add_employee.py 9876543210 --name "Ramaa" --code EMP002
    py add_employee.py 9876543210 --company "Acme Construction" --email me@example.com
"""

import argparse
import asyncio
import re
import sys

from app.db.mongo import close_client, get_database, new_id, utcnow
from app.models import Role

MOBILE_PATTERN = re.compile(r"^[6-9]\d{9}$")


async def add_employee(mobile: str, name: str, code: str, company_name: str, email: str | None) -> int:
    db = get_database()
    try:
        company = await db.companies.find_one({"name": company_name})
        if not company:
            names = [c["name"] async for c in db.companies.find({}, {"name": 1})]
            print(f"Company '{company_name}' not found. Available: {', '.join(names) or 'none'}")
            return 1

        existing = await db.employees.find_one({"mobile": mobile, "company_id": company["_id"]})
        if existing:
            changes = {"is_active": True, **({"email": email} if email else {})}
            await db.employees.update_one({"_id": existing["_id"]}, {"$set": changes})
            await db.users.update_one({"_id": existing["user_id"]}, {"$set": {"is_active": True}})
            print(f"{mobile} is active in {company['name']} as {existing['name']}.")
            return 0

        # A duplicate across companies makes OTP login ambiguous, so refuse it here as the API would.
        if await db.employees.find_one({"mobile": mobile, "is_active": True}, {"_id": 1}):
            print(f"{mobile} is already active in another company; OTP login would be ambiguous.")
            return 1

        if not code:
            count = await db.employees.count_documents({"company_id": company["_id"]})
            code = f"EMP{count + 1:03d}"

        branch = await db.branches.find_one({"company_id": company["_id"]})
        now = utcnow()
        user_id = new_id()
        await db.users.insert_one({
            "_id": user_id, "company_id": company["_id"], "role": Role.employee.value, "is_active": True,
            "refresh_token_hash": None, "created_at": now, "updated_at": now,
        })
        await db.employees.insert_one({
            "_id": new_id(), "company_id": company["_id"], "user_id": user_id,
            "branch_id": branch["_id"] if branch else None, "name": name, "employee_code": code,
            "mobile": mobile, "email": email, "is_active": True, "created_at": now, "updated_at": now,
        })
        print(f"Added {name} ({code}) with mobile {mobile} to {company['name']}.")
        print("Log in with this mobile; the development OTP is printed by the API.")
        return 0
    finally:
        await close_client()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mobile", help="10-digit Indian mobile number")
    parser.add_argument("--name", default="Test Employee")
    parser.add_argument("--code", default="", help="Employee code; auto-generated when omitted")
    parser.add_argument("--company", default="Acme Construction")
    parser.add_argument("--email", default=None, help="Send login codes to this email (free) instead of SMS")
    args = parser.parse_args()

    mobile = re.sub(r"\D", "", args.mobile)
    if not MOBILE_PATTERN.match(mobile):
        print("Mobile must be 10 digits starting with 6, 7, 8, or 9.")
        return 1

    return asyncio.run(add_employee(mobile, args.name, args.code, args.company, (args.email or "").strip().lower() or None))


if __name__ == "__main__":
    sys.exit(main())
