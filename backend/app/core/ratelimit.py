import time

from fastapi import HTTPException, Request

from app.core.cache import get_store
from app.core.config import settings


def resolve_client_ip(forwarded: str | None, peer: str | None) -> str:
    """Clients can prepend anything to X-Forwarded-For; only the entries added by
    our own proxies (TRUSTED_PROXY_HOPS, counted from the right) are reliable."""
    hops = settings.trusted_proxy_hops
    if forwarded and hops > 0:
        parts = [part.strip() for part in forwarded.split(",") if part.strip()]
        if parts:
            return parts[-hops] if len(parts) >= hops else parts[0]
    return peer or "unknown"


def client_ip(request: Request) -> str:
    return resolve_client_ip(request.headers.get("x-forwarded-for"), request.client.host if request.client else None)


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


async def check_login_lockout(identity: str, threshold: int | None = None) -> None:
    if not settings.rate_limit_enabled:
        return
    failures = await get_store().get(f"lock:{identity}")
    if failures and int(failures) >= (threshold or settings.login_lockout_failures):
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
