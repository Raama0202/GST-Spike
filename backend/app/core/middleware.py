import json
import logging
import time
from uuid import uuid4

from starlette.exceptions import HTTPException
from starlette.types import ASGIApp, Message, Receive, Scope, Send

from app.core.config import settings
from app.core.logging import request_id_var
from app.core.ratelimit import allow

logger = logging.getLogger("app.request")

UNLIMITED_PATHS = ("/health", "/ready", "/v1/payments/razorpay/webhook")


class BodyTooLarge(HTTPException):
    """HTTPException so FastAPI's body parser re-raises it instead of turning it into a 400."""

    def __init__(self) -> None:
        super().__init__(413, f"Request exceeds {settings.max_request_mb} MB")


class RequestContextMiddleware:
    """Request id, access log, security headers, body size cap, per-IP flood
    limit, and a JSON 500 for unhandled errors.

    Must be registered *inside* CORSMiddleware so error responses still carry
    CORS headers (otherwise browsers report them as network failures).
    """

    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        max_body = settings.max_request_mb * 1024 * 1024
        ip_limit = settings.api_rate_per_minute * 4

        headers = {k.decode().lower(): v.decode() for k, v in scope.get("headers", [])}
        request_id = headers.get("x-request-id", "")[:64] or uuid4().hex
        token = request_id_var.set(request_id)
        started = time.perf_counter()
        status_holder = {"status": 500}
        path = scope.get("path", "")

        async def send_with_headers(message: Message) -> None:
            if message["type"] == "http.response.start":
                status_holder["status"] = message["status"]
                extra = [
                    (b"x-request-id", request_id.encode()),
                    (b"x-content-type-options", b"nosniff"),
                    (b"x-frame-options", b"DENY"),
                    (b"referrer-policy", b"no-referrer"),
                ]
                if settings.is_production:
                    extra.append((b"strict-transport-security", b"max-age=31536000; includeSubDomains"))
                message["headers"] = list(message.get("headers", [])) + extra
            await send(message)

        try:
            length = headers.get("content-length")
            if length and length.isdigit() and int(length) > max_body:
                await self._json(send_with_headers, 413, {"message": f"Request exceeds {settings.max_request_mb} MB"})
                return

            if not path.startswith(UNLIMITED_PATHS) and scope.get("method") != "OPTIONS":
                ip = headers.get("x-forwarded-for", "").split(",")[0].strip() or (scope.get("client") or ("unknown",))[0]
                if not await allow(f"ip:{ip}", ip_limit, 60):
                    await self._json(send_with_headers, 429, {"message": "Too many requests. Please slow down."}, retry_after=60)
                    return

            received = 0

            async def limited_receive() -> Message:
                nonlocal received
                message = await receive()
                if message["type"] == "http.request":
                    received += len(message.get("body", b""))
                    if received > max_body:
                        raise BodyTooLarge()
                return message

            await self.app(scope, limited_receive, send_with_headers)
        except BodyTooLarge:
            await self._json(send_with_headers, 413, {"message": f"Request exceeds {settings.max_request_mb} MB"})
        except Exception:
            logger.exception("Unhandled error on %s %s", scope.get("method"), path)
            await self._json(send_with_headers, 500, {"message": "Something went wrong on our side. Please try again.", "requestId": request_id})
        finally:
            duration_ms = round((time.perf_counter() - started) * 1000, 1)
            if path not in ("/health",):
                logger.info(
                    "%s %s %s %sms",
                    scope.get("method"),
                    path,
                    status_holder["status"],
                    duration_ms,
                    extra={"extra_fields": {"method": scope.get("method"), "path": path, "status": status_holder["status"], "durationMs": duration_ms}},
                )
            request_id_var.reset(token)

    @staticmethod
    async def _json(send: Send, status: int, body: dict, retry_after: int | None = None) -> None:
        payload = json.dumps(body).encode()
        headers = [(b"content-type", b"application/json"), (b"content-length", str(len(payload)).encode())]
        if retry_after:
            headers.append((b"retry-after", str(retry_after).encode()))
        try:
            await send({"type": "http.response.start", "status": status, "headers": headers})
            await send({"type": "http.response.body", "body": payload})
        except RuntimeError:
            # Response already started; nothing more we can send.
            pass
