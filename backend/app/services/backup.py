"""Logical MongoDB backups (Atlas M0 has no automated backups).

Each backup is one .tar.gz holding a gzipped Extended-JSON file per collection
plus a manifest. It goes to BACKUP_BUCKET (any S3-compatible store; the R2_*
credentials are reused) or to a local folder when no bucket is configured.
"""
import asyncio
import gzip
import io
import json
import logging
import tarfile
import tempfile
from datetime import timedelta
from pathlib import Path

from bson import json_util
from bson.codec_options import CodecOptions
from pymongo.asynchronous.database import AsyncDatabase

from app.core.config import settings
from app.db.mongo import ensure_indexes, utcnow

logger = logging.getLogger(__name__)

SKIP_ALWAYS = {"kv", "otp_challenges", "signup_requests"}
FILE_COLLECTIONS = {"fs.files", "fs.chunks"}
INSERT_BATCH = 1000
JSON_OPTIONS = json_util.JSONOptions(json_mode=json_util.JSONMode.CANONICAL, tz_aware=True)
# Without the app's Decimal codec so values stay Decimal128 and round-trip exactly.
RAW_BSON = CodecOptions(tz_aware=True)


def _client():
    from app.services.storage import _r2_client

    return _r2_client()


async def _collections(db: AsyncDatabase, include_files: bool) -> list[str]:
    names = await db.list_collection_names()
    return sorted(
        name for name in names
        if name not in SKIP_ALWAYS and not name.startswith("system.") and (include_files or name not in FILE_COLLECTIONS)
    )


async def dump(db: AsyncDatabase, target: Path, include_files: bool = False) -> dict:
    """Write a backup archive to `target`; returns the manifest."""
    manifest = {"created_at": utcnow().isoformat(), "database": db.name, "collections": {}}
    with tarfile.open(target, "w:gz") as tar:
        for name in await _collections(db, include_files):
            buffer = io.BytesIO()
            count = 0
            with gzip.GzipFile(fileobj=buffer, mode="wb") as gz:
                async for doc in db[name].with_options(codec_options=RAW_BSON).find({}):
                    gz.write(json_util.dumps(doc, json_options=JSON_OPTIONS).encode() + b"\n")
                    count += 1
            info = tarfile.TarInfo(f"{name}.jsonl.gz")
            info.size = buffer.tell()
            buffer.seek(0)
            tar.addfile(info, buffer)
            manifest["collections"][name] = count
        raw = json.dumps(manifest, indent=2).encode()
        info = tarfile.TarInfo("manifest.json")
        info.size = len(raw)
        tar.addfile(info, io.BytesIO(raw))
    return manifest


async def run_backup(out_dir: Path | None = None, include_files: bool = False) -> str:
    from app.db.mongo import get_database

    db = get_database()
    stamp = utcnow().strftime("%Y%m%dT%H%M%SZ")
    name = f"{db.name}-{stamp}.tar.gz"
    if not settings.backup_bucket:
        folder = out_dir or Path("backups")
        folder.mkdir(parents=True, exist_ok=True)
        path = folder / name
        manifest = await dump(db, path, include_files)
        logger.info("Backup written to %s (%s)", path, manifest["collections"])
        return str(path)

    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / name
        manifest = await dump(db, path, include_files)
        key = f"{settings.backup_prefix.strip('/')}/{name}"
        await asyncio.to_thread(_client().upload_file, str(path), settings.backup_bucket, key)
    logger.info("Backup uploaded to %s/%s (%s)", settings.backup_bucket, key, manifest["collections"])
    await asyncio.to_thread(_prune_remote)
    return f"{settings.backup_bucket}/{key}"


def _prune_remote() -> int:
    if settings.backup_keep_days <= 0:
        return 0
    cutoff = utcnow() - timedelta(days=settings.backup_keep_days)
    client = _client()
    removed = 0
    paginator = client.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=settings.backup_bucket, Prefix=settings.backup_prefix.strip("/") + "/"):
        old = [{"Key": item["Key"]} for item in page.get("Contents", []) if item["LastModified"] < cutoff]
        if old:
            client.delete_objects(Bucket=settings.backup_bucket, Delete={"Objects": old, "Quiet": True})
            removed += len(old)
    return removed


async def restore(db: AsyncDatabase, archive: Path, drop: bool = False) -> dict[str, int]:
    """Load an archive produced by `dump`. Without `drop`, existing _ids are kept."""
    restored: dict[str, int] = {}
    with tarfile.open(archive, "r:gz") as tar:
        for member in tar.getmembers():
            if not member.name.endswith(".jsonl.gz"):
                continue
            name = member.name.removesuffix(".jsonl.gz")
            handle = tar.extractfile(member)
            if handle is None:
                continue
            if drop:
                await db[name].drop()
            count = 0
            batch: list[dict] = []
            with gzip.GzipFile(fileobj=handle) as gz:
                for line in gz:
                    if line.strip():
                        batch.append(json_util.loads(line, json_options=JSON_OPTIONS))
                    if len(batch) >= INSERT_BATCH:
                        count += await _insert(db, name, batch)
                        batch = []
            if batch:
                count += await _insert(db, name, batch)
            restored[name] = count
    await ensure_indexes(db)
    return restored


async def _insert(db: AsyncDatabase, name: str, docs: list[dict]) -> int:
    from pymongo.errors import BulkWriteError

    try:
        result = await db[name].insert_many(docs, ordered=False)
        return len(result.inserted_ids)
    except BulkWriteError as exc:
        return exc.details.get("nInserted", 0)
