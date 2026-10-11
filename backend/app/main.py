import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.encoders import jsonable_encoder
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware
from fastapi.responses import JSONResponse
from sqlalchemy import text
from sqlalchemy.exc import IntegrityError
from starlette.exceptions import HTTPException as StarletteHTTPException

from app.api.routes import admin, auth, billing, company, devices, employees, invoices, itc, media, notifications, super
from app.core.cache import get_store
from app.core.config import settings
from app.core.logging import configure_logging, init_sentry
from app.core.middleware import RequestContextMiddleware
from app.db.session import engine
from app.services.storage import LocalStorage, R2Storage, get_storage

configure_logging()
init_sentry()
logger = logging.getLogger("app")


@asynccontextmanager
async def lifespan(_: FastAPI):
    problems = settings.production_problems()
    if problems:
        for problem in problems:
            logger.critical("Configuration error: %s", problem)
        raise RuntimeError("Refusing to start in production with unsafe configuration: " + "; ".join(problems))
    for warning in settings.production_warnings():
        logger.warning("Configuration warning: %s", warning)
    if isinstance(get_storage(), LocalStorage):
        settings.storage_path.mkdir(parents=True, exist_ok=True)
    yield
    await get_store().close()
    await engine.dispose()


app = FastAPI(
    title=settings.app_name,
    version="1.1.0",
    lifespan=lifespan,
    docs_url=None if settings.is_production else "/docs",
    redoc_url=None if settings.is_production else "/redoc",
    openapi_url=None if settings.is_production else "/openapi.json",
)
# Order matters: the last added runs first. CORS must wrap RequestContextMiddleware
# so its 413/429/500 responses still carry CORS headers.
app.add_middleware(GZipMiddleware, minimum_size=1024)
app.add_middleware(RequestContextMiddleware)
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origin_list,
    allow_credentials=False,
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type", "X-Company-Id", "X-Request-Id", "Idempotency-Key"],
    expose_headers=["X-Request-Id", "Retry-After"],
    max_age=600,
)

app.include_router(auth.router, prefix="/v1/auth", tags=["auth"])
app.include_router(auth.admin_router, prefix="/v1/admin/auth", tags=["admin-auth"])
app.include_router(employees.router, prefix="/v1/employees", tags=["employees"])
app.include_router(company.router, prefix="/v1/company", tags=["company"])
app.include_router(invoices.router, prefix="/v1/invoices", tags=["invoices"])
app.include_router(notifications.router, prefix="/v1/notifications", tags=["notifications"])
app.include_router(devices.router, prefix="/v1/devices", tags=["devices"])
app.include_router(admin.router, prefix="/v1/admin", tags=["admin"])
app.include_router(employees.admin_router, prefix="/v1/admin/employees", tags=["admin-employees"])
app.include_router(company.admin_router, prefix="/v1/admin/company", tags=["admin-company"])
app.include_router(invoices.admin_router, prefix="/v1/admin/invoices", tags=["admin-invoices"])
app.include_router(itc.router, prefix="/v1/admin/itc", tags=["admin-itc"])
app.include_router(notifications.admin_router, prefix="/v1/admin/notifications", tags=["admin-notifications"])
app.include_router(billing.admin_router, prefix="/v1/admin/billing", tags=["admin-billing"])
app.include_router(billing.webhook_router, prefix="/v1/payments", tags=["payments"])
app.include_router(super.public_router, prefix="/v1/super", tags=["activation"])
app.include_router(super.router, prefix="/v1/super", tags=["super-admin"])
app.include_router(billing.super_router, prefix="/v1/super/payments", tags=["super-admin"])
app.include_router(media.router, prefix="/v1/media", tags=["media"])


@app.get("/health")
async def health():
    """Liveness: the process is up. Does not touch dependencies."""
    return {"status": "ok"}


@app.get("/ready")
async def ready():
    """Readiness: database (and Redis/R2 when configured) are reachable."""
    checks: dict[str, str] = {}
    try:
        async with engine.connect() as conn:
            await conn.execute(text("SELECT 1"))
        checks["database"] = "ok"
    except Exception as exc:  # noqa: BLE001
        logger.error("Readiness: database unavailable: %s", exc)
        checks["database"] = "error"
    if settings.redis_url:
        checks["redis"] = "ok" if await get_store().ping() else "error"
    storage = get_storage()
    if isinstance(storage, R2Storage):
        checks["storage"] = "ok" if await storage.ping() else "error"
    # Only the database is fatal; Redis and R2 failures degrade (fail-open) rather than take instances out of rotation.
    healthy = checks["database"] == "ok"
    degraded = any(value != "ok" for value in checks.values())
    return JSONResponse(
        status_code=200 if healthy else 503,
        content={"status": "degraded" if degraded else "ok", "checks": checks},
    )


@app.exception_handler(StarletteHTTPException)
async def http_error(_: Request, exc: StarletteHTTPException):
    detail = exc.detail if isinstance(exc.detail, str) else "Request failed"
    return JSONResponse(status_code=exc.status_code, content={"message": detail}, headers=getattr(exc, "headers", None))


@app.exception_handler(IntegrityError)
async def integrity_error(_: Request, exc: IntegrityError):
    logger.warning("Integrity error: %s", exc.orig)
    return JSONResponse(status_code=409, content={"message": "This conflicts with an existing record (duplicate name, code or mobile)."})


@app.exception_handler(RequestValidationError)
async def validation_error(_: Request, exc: RequestValidationError):
    errors = [{k: v for k, v in error.items() if k in ("loc", "msg", "type")} for error in exc.errors()]
    first = errors[0] if errors else {}
    field = ".".join(str(part) for part in first.get("loc", [])[1:]) if first else ""
    message = f"{field}: {first.get('msg')}" if field and first.get("msg") else "Invalid request"
    return JSONResponse(
        status_code=400,
        content=jsonable_encoder({"message": message, "code": "VALIDATION_ERROR", "errors": errors}),
    )
