"""Invoice image storage.

`local` keeps files on disk (dev/tests) and serves them through the signed
`/v1/media/...` route. `r2` stores them in a Cloudflare R2 bucket (S3 API) and
hands out short-lived presigned URLs, so images are never publicly listable
and every API instance sees the same files.
"""
import asyncio
import hashlib
import hmac
import time
from functools import lru_cache
from pathlib import Path
from urllib.parse import urlencode
from uuid import UUID, uuid4

from fastapi import UploadFile

from app.core.config import settings

MAX_FILE_SIZE = 15 * 1024 * 1024
EXTENSIONS = {
    "image/jpeg": ".jpg",
    "image/png": ".png",
    "image/webp": ".webp",
    "image/heic": ".heic",
}
HEIC_BRANDS = {b"heic", b"heix", b"hevc", b"hevx", b"heim", b"heis", b"mif1", b"msf1"}


def sniff_image_type(head: bytes) -> str | None:
    if head.startswith(b"\xff\xd8\xff"):
        return "image/jpeg"
    if head.startswith(b"\x89PNG\r\n\x1a\n"):
        return "image/png"
    if len(head) >= 12 and head[:4] == b"RIFF" and head[8:12] == b"WEBP":
        return "image/webp"
    if len(head) >= 12 and head[4:8] == b"ftyp" and head[8:12] in HEIC_BRANDS:
        return "image/heic"
    return None


class LocalStorage:
    def __init__(self, root: Path | None = None) -> None:
        self.root = root or settings.storage_path

    def path_for(self, key: str) -> Path:
        target = (self.root / key).resolve()
        if self.root.resolve() not in target.parents:
            raise ValueError("Invalid storage key")
        return target

    async def put(self, key: str, data: bytes, content_type: str) -> None:
        target = self.path_for(key)
        await asyncio.to_thread(target.parent.mkdir, parents=True, exist_ok=True)
        await asyncio.to_thread(target.write_bytes, data)

    def url(self, key: str) -> str:
        expires = int(time.time()) + settings.signed_url_seconds
        return f"/v1/media/{key}?" + urlencode({"exp": expires, "sig": sign_media(key, expires)})


class R2Storage:
    def __init__(self) -> None:
        self.bucket = settings.r2_bucket
        self.client = _r2_client()

    async def put(self, key: str, data: bytes, content_type: str) -> None:
        await asyncio.to_thread(
            self.client.put_object,
            Bucket=self.bucket,
            Key=key,
            Body=data,
            ContentType=content_type,
            CacheControl="private, max-age=86400",
        )

    def url(self, key: str) -> str:
        return self.client.generate_presigned_url(
            "get_object",
            Params={"Bucket": self.bucket, "Key": key},
            ExpiresIn=settings.signed_url_seconds,
        )

    async def ping(self) -> bool:
        try:
            await asyncio.to_thread(self.client.head_bucket, Bucket=self.bucket)
            return True
        except Exception:  # noqa: BLE001
            return False


@lru_cache
def _r2_client():
    import boto3
    from botocore.config import Config

    return boto3.client(
        "s3",
        endpoint_url=settings.r2_endpoint,
        aws_access_key_id=settings.r2_access_key_id,
        aws_secret_access_key=settings.r2_secret_access_key,
        region_name="auto",
        config=Config(signature_version="s3v4", s3={"addressing_style": "path"}, retries={"max_attempts": 3, "mode": "standard"}, connect_timeout=5, read_timeout=30),
    )


_storage: LocalStorage | R2Storage | None = None


def get_storage() -> LocalStorage | R2Storage:
    global _storage
    if _storage is None:
        _storage = R2Storage() if settings.storage_backend == "r2" else LocalStorage()
    return _storage


def set_storage(storage: LocalStorage | R2Storage | None) -> None:
    global _storage
    _storage = storage


def sign_media(key: str, expires: int) -> str:
    return hmac.new(settings.jwt_secret.encode(), f"{key}:{expires}".encode(), hashlib.sha256).hexdigest()


def verify_media(key: str, expires: int, signature: str) -> bool:
    return expires >= int(time.time()) and hmac.compare_digest(sign_media(key, expires), signature)


async def save_upload(file: UploadFile, company_id: UUID, kind: str) -> str:
    data = bytearray()
    while chunk := await file.read(1024 * 1024):
        data.extend(chunk)
        if len(data) > MAX_FILE_SIZE:
            raise ValueError("Image exceeds 15 MB")
    if not data:
        raise ValueError(f"Empty {kind} image")
    content_type = sniff_image_type(bytes(data[:16]))
    if not content_type:
        raise ValueError(f"Unsupported image type for {kind}; use JPEG, PNG or WebP")
    key = f"{company_id}/{kind}-{uuid4().hex}{EXTENSIONS[content_type]}"
    await get_storage().put(key, bytes(data), content_type)
    return key


def public_url(path: str | None) -> str | None:
    """Short-lived URL for a stored image (name kept for existing callers)."""
    if not path:
        return None
    if path.startswith("/uploads/"):
        path = path[len("/uploads/"):]
    return get_storage().url(path)
