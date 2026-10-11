"""Create tables and seed demo data for local development.

Alembic owns the PostgreSQL schema; this helper exists so a laptop can run the
API on SQLite for on-device testing without installing PostgreSQL.
"""

import asyncio

from app.db.base import Base
from app.db.session import engine
from app.seed import seed


async def main() -> None:
    async with engine.begin() as connection:
        await connection.run_sync(Base.metadata.create_all)
    await seed()


if __name__ == "__main__":
    asyncio.run(main())
