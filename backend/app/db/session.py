from collections.abc import AsyncGenerator

from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.core.config import settings


def _engine_kwargs(url: str) -> dict:
    if not url.startswith("postgresql"):
        return {"pool_pre_ping": True}
    return {
        "pool_pre_ping": True,
        "pool_size": settings.db_pool_size,
        "max_overflow": settings.db_max_overflow,
        "pool_recycle": settings.db_pool_recycle_seconds,
        "pool_timeout": 10,
        "connect_args": {
            "timeout": 10,
            "command_timeout": max(settings.db_statement_timeout_ms / 1000 * 2, 30),
            "server_settings": {
                "statement_timeout": str(settings.db_statement_timeout_ms),
                "idle_in_transaction_session_timeout": "60000",
                "application_name": "gst-expense-api",
            },
        },
    }


engine = create_async_engine(settings.async_database_url, **_engine_kwargs(settings.async_database_url))
SessionLocal = async_sessionmaker(engine, expire_on_commit=False, class_=AsyncSession)


async def get_db() -> AsyncGenerator[AsyncSession, None]:
    async with SessionLocal() as session:
        try:
            yield session
        except Exception:
            await session.rollback()
            raise
