"""Shared key-value store for rate limits and short-lived caches.

Redis when REDIS_URL is set; otherwise a MongoDB TTL collection (shared by
every instance, no extra service), or an in-process store for tests. Store
errors fail open so an outage degrades rate limiting/caching instead of
taking the API down.
"""
import json
import logging
import time
from datetime import timedelta
from typing import Any

from pymongo import ReturnDocument

from app.core.config import settings
from app.db.mongo import get_database, utcnow
from app.db.mongo import ping as mongo_ping

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


class MongoStore:
    """`kv` collection: {_id: key, value, expires_at}. Atlas's TTL monitor removes
    expired rows within ~60 s; reads and counters also check `expires_at` so a
    lingering row is never treated as live."""

    @staticmethod
    def _collection():
        return get_database()["kv"]

    async def get(self, key: str) -> str | None:
        try:
            doc = await self._collection().find_one({"_id": key, "expires_at": {"$gt": utcnow()}})
        except Exception as exc:  # noqa: BLE001
            logger.warning("mongo cache get failed: %s", exc)
            return None
        return doc["value"] if doc else None

    async def set(self, key: str, value: str, ttl: int | None = None) -> None:
        expires = utcnow() + timedelta(seconds=ttl or 86400 * 365)
        try:
            await self._collection().update_one({"_id": key}, {"$set": {"value": value, "expires_at": expires}}, upsert=True)
        except Exception as exc:  # noqa: BLE001
            logger.warning("mongo cache set failed: %s", exc)

    async def incr(self, key: str, ttl: int) -> int:
        now = utcnow()
        live = {"$gt": ["$expires_at", now]}
        pipeline = [
            {
                "$set": {
                    "count": {"$cond": [live, {"$add": [{"$ifNull": ["$count", 0]}, 1]}, 1]},
                    "expires_at": {"$cond": [live, "$expires_at", now + timedelta(seconds=ttl)]},
                }
            },
            {"$set": {"value": {"$toString": "$count"}}},
        ]
        try:
            doc = await self._collection().find_one_and_update(
                {"_id": key}, pipeline, upsert=True, return_document=ReturnDocument.AFTER
            )
        except Exception as exc:  # noqa: BLE001
            logger.warning("mongo cache incr failed: %s", exc)
            return 0
        return int(doc["count"]) if doc else 0

    async def delete(self, *keys: str) -> None:
        if not keys:
            return
        try:
            await self._collection().delete_many({"_id": {"$in": list(keys)}})
        except Exception as exc:  # noqa: BLE001
            logger.warning("mongo cache delete failed: %s", exc)

    async def ping(self) -> bool:
        return await mongo_ping()

    async def close(self) -> None:
        return None


Store = MemoryStore | RedisStore | MongoStore
_store: Store | None = None


def get_store() -> Store:
    global _store
    if _store is None:
        if settings.redis_url:
            _store = RedisStore(settings.redis_url)
        elif settings.cache_backend.strip().lower() == "memory":
            _store = MemoryStore()
        else:
            _store = MongoStore()
    return _store


def set_store(store: Store | None) -> None:
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
