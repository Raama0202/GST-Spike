"""Calendar maths for dashboards and exports. Indian businesses read days in IST, not UTC."""
from datetime import date, datetime, timedelta, timezone

from app.db.mongo import as_utc, utcnow

IST = timezone(timedelta(hours=5, minutes=30), "IST")
IST_OFFSET = "+05:30"


def ist_today() -> date:
    return utcnow().astimezone(IST).date()


def ist_day_start(day: date) -> datetime:
    """UTC instant at which `day` begins in IST."""
    return datetime(day.year, day.month, day.day, tzinfo=IST).astimezone(timezone.utc)


def ist_last_days(count: int) -> tuple[datetime, list[str]]:
    """Start instant of the window and its `count` IST days (oldest first) as YYYY-MM-DD."""
    today = ist_today()
    days = [today - timedelta(days=offset) for offset in range(count - 1, -1, -1)]
    return ist_day_start(days[0]), [day.isoformat() for day in days]


def ist_string(value: datetime | None) -> str:
    return as_utc(value).astimezone(IST).strftime("%Y-%m-%d %H:%M") if value else ""


def day_bucket(field: str) -> dict:
    """Aggregation expression grouping a UTC timestamp by IST calendar day."""
    return {"$dateToString": {"format": "%Y-%m-%d", "date": f"${field}", "timezone": IST_OFFSET}}
