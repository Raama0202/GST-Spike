"""Operational commands.

    python -m app.cli create-super-admin --email ops@example.com
        Password is read from SUPER_ADMIN_PASSWORD (never from argv/history).
    python -m app.cli cleanup
        Deletes expired OTP challenges and old webhook events (run from cron).
    python -m app.cli migrate-uploads
        Copies files from the local STORAGE_PATH into the configured R2 bucket.
"""
import argparse
import asyncio
import os
import sys
from datetime import datetime, timedelta, timezone

from sqlalchemy import delete, select

from app.core.security import hash_password
from app.db.session import SessionLocal, engine
from app.models import OTPChallenge, PaymentEvent, Role, User


async def create_super_admin(email: str) -> int:
    password = os.environ.get("SUPER_ADMIN_PASSWORD", "")
    if len(password) < 12:
        print("Set SUPER_ADMIN_PASSWORD (12+ characters) in the environment.", file=sys.stderr)
        return 1
    async with SessionLocal() as db:
        existing = await db.scalar(select(User).where(User.email == email.lower()))
        if existing:
            if existing.role != Role.super_admin:
                print("That email belongs to a non-super-admin account.", file=sys.stderr)
                return 1
            existing.password_hash = hash_password(password)
            existing.is_active = True
            existing.refresh_token_hash = None
            action = "updated"
        else:
            db.add(User(email=email.lower(), password_hash=hash_password(password), role=Role.super_admin))
            action = "created"
        await db.commit()
    print(f"Super admin {email} {action}.")
    return 0


async def cleanup() -> int:
    now = datetime.now(timezone.utc)
    async with SessionLocal() as db:
        otp = await db.execute(delete(OTPChallenge).where(OTPChallenge.expires_at < now - timedelta(days=1)))
        events = await db.execute(delete(PaymentEvent).where(PaymentEvent.created_at < now - timedelta(days=180)))
        await db.commit()
    print(f"Deleted {otp.rowcount} OTP challenges and {events.rowcount} payment events.")
    return 0


async def migrate_uploads() -> int:
    from app.core.config import settings
    from app.services.storage import R2Storage, sniff_image_type

    if settings.storage_backend != "r2":
        print("Set STORAGE_BACKEND=r2 and the R2_* variables first.", file=sys.stderr)
        return 1
    target = R2Storage()
    root = settings.storage_path
    copied = 0
    for path in root.rglob("*"):
        if path.is_file():
            key = path.relative_to(root).as_posix()
            await target.put(key, path.read_bytes(), sniff_image_type(path.read_bytes()[:16]) or "application/octet-stream")
            copied += 1
    print(f"Copied {copied} files to R2 bucket {settings.r2_bucket}.")
    return 0


def main() -> None:
    parser = argparse.ArgumentParser(prog="python -m app.cli")
    sub = parser.add_subparsers(dest="command", required=True)
    sa = sub.add_parser("create-super-admin")
    sa.add_argument("--email", required=True)
    sub.add_parser("cleanup")
    sub.add_parser("migrate-uploads")
    args = parser.parse_args()

    async def run() -> int:
        try:
            if args.command == "create-super-admin":
                return await create_super_admin(args.email)
            if args.command == "cleanup":
                return await cleanup()
            return await migrate_uploads()
        finally:
            await engine.dispose()

    sys.exit(asyncio.run(run()))


if __name__ == "__main__":
    main()
