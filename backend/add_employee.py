"""Register an employee mobile so it can receive a login OTP.

Employees normally come from the admin app; this exists so a developer can put
their own phone number into the seeded demo company without a UI round-trip.

Usage:
    py add_employee.py 9876543210 --name "Ramaa" --code EMP002
    py add_employee.py 9876543210 --company "Acme Construction"
"""

import argparse
import asyncio
import re
import sys

from sqlalchemy import func, select

from app.db.session import SessionLocal
from app.models import Branch, Company, Employee, Role, User

MOBILE_PATTERN = re.compile(r"^[6-9]\d{9}$")


async def add_employee(mobile: str, name: str, code: str, company_name: str) -> int:
    async with SessionLocal() as db:
        company = await db.scalar(select(Company).where(Company.name == company_name))
        if not company:
            names = (await db.scalars(select(Company.name))).all()
            print(f"Company '{company_name}' not found. Available: {', '.join(names) or 'none'}")
            return 1

        existing = await db.scalar(
            select(Employee).where(
                Employee.mobile == mobile, Employee.company_id == company.id
            )
        )
        if existing:
            if not existing.is_active:
                existing.is_active = True
                await db.commit()
                print(f"Reactivated {mobile} ({existing.name}) in {company.name}.")
            else:
                print(f"{mobile} is already active in {company.name} as {existing.name}.")
            return 0

        # Mobiles must be unique per company, and a duplicate across companies
        # makes OTP login ambiguous, so refuse it here as the API would.
        clash = await db.scalar(
            select(Employee).where(Employee.mobile == mobile, Employee.is_active.is_(True))
        )
        if clash:
            print(f"{mobile} is already active in another company; OTP login would be ambiguous.")
            return 1

        if not code:
            count = await db.scalar(
                select(func.count()).select_from(Employee).where(Employee.company_id == company.id)
            )
            code = f"EMP{(count or 0) + 1:03d}"

        branch = await db.scalar(select(Branch).where(Branch.company_id == company.id))
        user = User(company_id=company.id, role=Role.employee)
        db.add(user)
        await db.flush()

        db.add(
            Employee(
                company_id=company.id,
                user_id=user.id,
                branch_id=branch.id if branch else None,
                name=name,
                employee_code=code,
                mobile=mobile,
            )
        )
        await db.commit()

        print(f"Added {name} ({code}) with mobile {mobile} to {company.name}.")
        print("Log in with this mobile; the development OTP is printed by the API.")
        return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mobile", help="10-digit Indian mobile number")
    parser.add_argument("--name", default="Test Employee")
    parser.add_argument("--code", default="", help="Employee code; auto-generated when omitted")
    parser.add_argument("--company", default="Acme Construction")
    args = parser.parse_args()

    mobile = re.sub(r"\D", "", args.mobile)
    if not MOBILE_PATTERN.match(mobile):
        print("Mobile must be 10 digits starting with 6, 7, 8, or 9.")
        return 1

    return asyncio.run(add_employee(mobile, args.name, args.code, args.company))


if __name__ == "__main__":
    sys.exit(main())
