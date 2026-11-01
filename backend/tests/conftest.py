import os
from uuid import uuid4

import pytest_asyncio

# Defaults for all API tests — individual tests may override via monkeypatch.
os.environ.setdefault("ENV", "dev")
os.environ.setdefault("OTP_DEV_FIXED", "123456")
os.environ.setdefault("JWT_SECRET", "test-secret-key-for-pytest-only!!")
os.environ.setdefault("LOG_JSON", "false")
os.environ.setdefault("GEMINI_API_KEY", "")
# A replica set is not required; any reachable MongoDB works (CI: a mongo service container).
os.environ.setdefault("MONGODB_URI", os.environ.get("TEST_MONGODB_URI", "mongodb://127.0.0.1:27017/?directConnection=true"))

JPEG = b"\xff\xd8\xff\xe0" + b"\x00" * 64


@pytest_asyncio.fixture
async def mongo(tmp_path_factory):
    """A fresh, uniquely named database per test (dropped afterwards)."""
    from app.core.cache import MemoryStore, set_store
    from app.core.config import settings
    from app.db.mongo import close_client, ensure_indexes, get_client, get_database
    from app.services.storage import LocalStorage, set_storage

    storage = tmp_path_factory.mktemp("uploads")
    previous_db = settings.mongodb_db
    settings.mongodb_db = f"gst_test_{uuid4().hex[:12]}"
    await close_client()  # clients are bound to the event loop that created them
    set_store(MemoryStore())
    set_storage(LocalStorage(storage))
    db = get_database()
    await ensure_indexes(db)
    try:
        yield db
    finally:
        await get_client().drop_database(settings.mongodb_db)
        await close_client()
        set_storage(None)
        set_store(None)
        settings.mongodb_db = previous_db
