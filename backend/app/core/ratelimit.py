import time

from fastapi import HTTPException, Request

from app.core.cache import get_store
from app.core.config import settings


def client_ip(request: Request) -> str:
    forwarded = request.headers.get("x-forwarded-for")
    if forwarded:
        return forwarded.split(",")[0].strip()
    return request.client.host if request.client else "unknown"


async def allow(key: str, limit: int, window_seconds: int) -> bool:
    """Fixed-window counter. Store failures (count 0) are treated as allowed."""
    if not settings.rate_limit_enabled or limit <= 0:
        return True
    bucket = int(time.time() // window_seconds)
    count = await get_store().incr(f"rl:{key}:{bucket}", window_seconds + 1)
    return count <= limit


async def enforce(key: str, limit: int, window_seconds: int, message: str = "Too many requests. Please slow down.") -> None:
    if not await allow(key, limit, window_seconds):
        raise HTTPException(429, message, headers={"Retry-After": str(window_seconds)})


async def check_login_lockout(identity: str) -> None:
    if not settings.rate_limit_enabled:
        return
    failures = await get_store().get(f"lock:{identity}")
    if failures and int(failures) >= settings.login_lockout_failures:
        raise HTTPException(
            429,
            f"Too many failed attempts. Try again in {settings.login_lockout_minutes} minutes.",
            headers={"Retry-After": str(settings.login_lockout_minutes * 60)},
        )


async def record_login_failure(identity: str) -> None:
    if settings.rate_limit_enabled:
        await get_store().incr(f"lock:{identity}", settings.login_lockout_minutes * 60)


async def clear_login_failures(identity: str) -> None:
    await get_store().delete(f"lock:{identity}")
