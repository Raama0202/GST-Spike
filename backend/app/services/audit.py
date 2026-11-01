"""Who-did-what trail for company admins and the super admin (`audit_logs`)."""
import logging
from typing import TYPE_CHECKING, Any

from pymongo.asynchronous.database import AsyncDatabase

from app.db.mongo import new_id, utcnow

if TYPE_CHECKING:
    from app.core.deps import Principal

logger = logging.getLogger(__name__)


async def record_audit(
    db: AsyncDatabase,
    principal: "Principal | None",
    action: str,
    target_type: str,
    target_id: str | None,
    summary: str,
    *,
    company_id: str | None = None,
    details: dict[str, Any] | None = None,
) -> None:
    """Best effort: an audit write failure must never fail the action itself."""
    try:
        await db.audit_logs.insert_one({
            "_id": new_id(),
            "company_id": company_id if company_id is not None else (principal.company_id if principal else None),
            "actor_id": principal.user.id if principal else None,
            "actor_email": principal.user.email if principal else None,
            "actor_role": principal.user.role.value if principal else "system",
            "action": action,
            "target_type": target_type,
            "target_id": target_id,
            "summary": summary[:500],
            "details": details or {},
            "created_at": utcnow(),
        })
    except Exception:  # noqa: BLE001
        logger.exception("Could not write audit log entry %s", action)


def audit_json(row: dict, company_names: dict[str, str] | None = None) -> dict:
    item = {
        "id": row["_id"],
        "action": row["action"],
        "targetType": row.get("target_type"),
        "targetId": row.get("target_id"),
        "summary": row.get("summary"),
        "actorEmail": row.get("actor_email"),
        "actorRole": row.get("actor_role"),
        "createdAt": row.get("created_at"),
    }
    if company_names is not None:
        item["companyId"] = row.get("company_id")
        item["companyName"] = company_names.get(row.get("company_id") or "") or (row.get("details") or {}).get("name")
    return item
