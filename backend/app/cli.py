"""Operational commands.

    python -m app.cli create-super-admin --email ops@example.com
        Password is read from SUPER_ADMIN_PASSWORD (never from argv/history).
    python -m app.cli init-db
        Creates MongoDB indexes and the default subscription plans (also done on API start).
    python -m app.cli cleanup
        Deletes expired OTP challenges and old webhook events (TTL indexes do most of this).
    python -m app.cli migrate-uploads
        Copies files from the local STORAGE_PATH into the configured R2 bucket.
    python -m app.cli backup [--out DIR] [--include-files]
        Exports every collection to BACKUP_BUCKET (or DIR). --include-files adds GridFS images.
    python -m app.cli restore --file ARCHIVE.tar.gz [--drop] --yes
        Loads a backup archive. --drop replaces the collections instead of merging.
"""
import argparse
import asyncio
import os
import sys
from datetime import timedelta
from pathlib import Path

from app.core.security import hash_password
from app.db.mongo import close_client, ensure_indexes, get_database, new_id, utcnow
from app.models import Role
from app.services.otp import purge_expired


async def create_super_admin(email: str) -> int:
    password = os.environ.get("SUPER_ADMIN_PASSWORD", "")
    if len(password) < 12:
        print("Set SUPER_ADMIN_PASSWORD (12+ characters) in the environment.", file=sys.stderr)
        return 1
    db = get_database()
    email = email.strip().lower()
    existing = await db.users.find_one({"email": email})
    if existing:
        if existing["role"] != Role.super_admin.value:
            print("That email belongs to a non-super-admin account.", file=sys.stderr)
            return 1
        await db.users.update_one(
            {"_id": existing["_id"]},
            {"$set": {"password_hash": hash_password(password), "is_active": True, "refresh_token_hash": None, "updated_at": utcnow()}},
        )
        action = "updated"
    else:
        now = utcnow()
        await db.users.insert_one({
            "_id": new_id(), "company_id": None, "email": email, "password_hash": hash_password(password),
            "role": Role.super_admin.value, "is_active": True, "refresh_token_hash": None,
            "created_at": now, "updated_at": now,
        })
        action = "created"
    print(f"Super admin {email} {action}.")
    return 0


async def init_db() -> int:
    from app.seed import seed_plans

    db = get_database()
    await ensure_indexes(db)
    await seed_plans(db)
    print("Indexes and subscription plans are ready.")
    return 0


async def cleanup() -> int:
    db = get_database()
    otp = await purge_expired(db)
    events = await db.payment_events.delete_many({"created_at": {"$lt": utcnow() - timedelta(days=180)}})
    print(f"Deleted {otp} OTP challenges and {events.deleted_count} payment events.")
    from app.services.renewals import send_renewal_reminders

    print(f"Sent {await send_renewal_reminders(db)} renewal reminder email(s).")
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
            data = path.read_bytes()
            await target.put(key, data, sniff_image_type(data[:16]) or "application/octet-stream")
            copied += 1
    print(f"Copied {copied} files to R2 bucket {settings.r2_bucket}.")
    return 0


async def backup(out: Path | None, include_files: bool) -> int:
    from app.services.backup import run_backup

    location = await run_backup(out, include_files)
    print(f"Backup saved to {location}")
    return 0


async def restore_backup(archive: Path, drop: bool, confirmed: bool) -> int:
    from app.services.backup import restore

    if not archive.is_file():
        print(f"{archive} not found.", file=sys.stderr)
        return 1
    db = get_database()
    if not confirmed:
        print(f"This loads {archive} into database '{db.name}'{' and DROPS existing collections' if drop else ''}. Re-run with --yes.", file=sys.stderr)
        return 1
    counts = await restore(db, archive, drop)
    print("Restored: " + ", ".join(f"{name}={count}" for name, count in counts.items()))
    return 0


def main() -> None:
    parser = argparse.ArgumentParser(prog="python -m app.cli")
    sub = parser.add_subparsers(dest="command", required=True)
    sa = sub.add_parser("create-super-admin")
    sa.add_argument("--email", required=True)
    sub.add_parser("init-db")
    sub.add_parser("cleanup")
    sub.add_parser("migrate-uploads")
    bk = sub.add_parser("backup")
    bk.add_argument("--out", type=Path)
    bk.add_argument("--include-files", action="store_true")
    rs = sub.add_parser("restore")
    rs.add_argument("--file", type=Path, required=True)
    rs.add_argument("--drop", action="store_true")
    rs.add_argument("--yes", action="store_true")
    args = parser.parse_args()

    async def run() -> int:
        try:
            if args.command == "create-super-admin":
                return await create_super_admin(args.email)
            if args.command == "init-db":
                return await init_db()
            if args.command == "cleanup":
                return await cleanup()
            if args.command == "backup":
                return await backup(args.out, args.include_files)
            if args.command == "restore":
                return await restore_backup(args.file, args.drop, args.yes)
            return await migrate_uploads()
        finally:
            await close_client()

    sys.exit(asyncio.run(run()))


if __name__ == "__main__":
    main()
