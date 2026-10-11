from collections.abc import Callable
from typing import Any

from sqlalchemy import Select, func, select
from sqlalchemy.ext.asyncio import AsyncSession


async def paginate(
    db: AsyncSession,
    query: Select,
    page: int,
    page_size: int,
    serialize: Callable[[Any], dict],
    *,
    scalars: bool = True,
) -> dict:
    """Run `query` for one page and return `{items, total, page, pageSize}`.

    `query` must already carry its ORDER BY (needed for stable pages).
    """
    total = await db.scalar(select(func.count()).select_from(query.order_by(None).subquery()))
    paged = query.offset((page - 1) * page_size).limit(page_size)
    rows = (await db.scalars(paged)).all() if scalars else (await db.execute(paged)).all()
    return {
        "items": [serialize(row) for row in rows],
        "total": total or 0,
        "page": page,
        "pageSize": page_size,
    }
