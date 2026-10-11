"""Shared key-value store for rate limits and short-lived caches.

Uses Redis when REDIS_URL is set; otherwise an in-process store that is only
correct for a single worker. Redis errors fail open so an outage degrades
rate limiting/caching instead of taking the API down.
"""
import json
import logging
import time
from typing import Any

from app.core.config import settings

logger = logging.getLogger(__name__)


class MemoryStore:
    def __init__(self) -> None:
        self._data: dict[str, tuple[str, float | None]] = {}

    def _live(self, key: str) -> str | None:
        item = self._data.get(key)
        if not item:
            return None
        value, expires = item
        if expires is not None and expires < time.monotonic():
            self._data.pop(key, None)
            return None
        return value

    async def get(self, key: str) -> str | None:
        return self._live(key)

    async def set(self, key: str, value: str, ttl: int | None = None) -> None:
        self._data[key] = (value, time.monotonic() + ttl if ttl else None)

    async def incr(self, key: str, ttl: int) -> int:
        current = self._live(key)
        if current is None:
            self._data[key] = ("1", time.monotonic() + ttl)
            return 1
        value = int(current) + 1
        self._data[key] = (str(value), self._data[key][1])
        return value

    async def delete(self, *keys: str) -> None:
        for key in keys:
            self._data.pop(key, None)

    async def ping(self) -> bool:
        return True

    async def close(self) -> None:
        self._data.clear()


class RedisStore:
    def __init__(self, url: str) -> None:
        import redis.asyncio as redis

        self._client = redis.from_url(url, decode_responses=True, socket_timeout=2, socket_connect_timeout=2)

    async def get(self, key: str) -> str | None:
        try:
            return await self._client.get(key)
        except Exception as exc:  # noqa: BLE001
            logger.warning("redis get failed: %s", exc)
            return None

    async def set(self, key: str, value: str, ttl: int | None = None) -> None:
        try:
            await self._client.set(key, value, ex=ttl)
        except Exception as exc:  # noqa: BLE001
            logger.warning("redis set failed: %s", exc)

    async def incr(self, key: str, ttl: int) -> int:
        try:
            async with self._client.pipeline(transaction=True) as pipe:
                pipe.incr(key)
                pipe.expire(key, ttl, nx=True)
                value, _ = await pipe.execute()
            return int(value)
        except Exception as exc:  # noqa: BLE001
            logger.warning("redis incr failed: %s", exc)
            return 0

    async def delete(self, *keys: str) -> None:
        if not keys:
            return
        try:
            await self._client.delete(*keys)
        except Exception as exc:  # noqa: BLE001
            logger.warning("redis delete failed: %s", exc)

    async def ping(self) -> bool:
        try:
            return bool(await self._client.ping())
        except Exception:  # noqa: BLE001
            return False

    async def close(self) -> None:
        await self._client.aclose()


_store: MemoryStore | RedisStore | None = None


def get_store() -> MemoryStore | RedisStore:
    global _store
    if _store is None:
        _store = RedisStore(settings.redis_url) if settings.redis_url else MemoryStore()
    return _store


def set_store(store: MemoryStore | RedisStore | None) -> None:
    global _store
    _store = store


async def get_json(key: str) -> Any | None:
    raw = await get_store().get(key)
    if raw is None:
        return None
    try:
        return json.loads(raw)
    except ValueError:
        return None


async def set_json(key: str, value: Any, ttl: int) -> None:
    await get_store().set(key, json.dumps(value, default=str), ttl)
