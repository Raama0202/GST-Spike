import os

import pytest_asyncio
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

# Defaults for all API tests — individual tests may override via fixtures.
os.environ.setdefault("ENV", "dev")
os.environ.setdefault("OTP_DEV_FIXED", "123456")
os.environ.setdefault("JWT_SECRET", "test-secret-key-for-pytest-only!!")
os.environ.setdefault("LOG_JSON", "false")

JPEG = b"\xff\xd8\xff\xe0" + b"\x00" * 64


@pytest_asyncio.fixture
async def db_engine(tmp_path_factory, request):
    db_path = tmp_path_factory.mktemp("db") / f"{request.node.name}.db"
    storage = tmp_path_factory.mktemp("uploads")
    os.environ["DATABASE_URL"] = f"sqlite+aiosqlite:///{db_path.as_posix()}"
    os.environ["STORAGE_PATH"] = str(storage)

    from app.core.config import get_settings

    get_settings.cache_clear()

    from app.core.cache import MemoryStore, set_store
    from app.db.base import Base
    from app.db.session import get_db
    from app.main import app
    from app.services.storage import LocalStorage, set_storage

    set_store(MemoryStore())
    set_storage(LocalStorage(storage))

    engine = create_async_engine(f"sqlite+aiosqlite:///{db_path.as_posix()}")
    session_factory = async_sessionmaker(engine, expire_on_commit=False)

    async with engine.begin() as connection:
        await connection.run_sync(Base.metadata.create_all)

    async def override_db():
        async with session_factory() as session:
            yield session

    app.dependency_overrides[get_db] = override_db
    yield engine, session_factory, storage
    app.dependency_overrides.pop(get_db, None)
    set_storage(None)
    set_store(None)
    async with engine.begin() as connection:
        await connection.run_sync(Base.metadata.drop_all)
    await engine.dispose()
    get_settings.cache_clear()
