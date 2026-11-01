"""Gunicorn settings for production (uvicorn workers).

Tune with env vars: WEB_CONCURRENCY, PORT, GUNICORN_TIMEOUT.
Each worker opens up to MONGODB_MAX_POOL_SIZE connections, so keep
workers x instances x pool below the Atlas connection limit (500 on M0-M5).
"""
import os

bind = f"0.0.0.0:{os.getenv('PORT', '8000')}"
worker_class = "uvicorn.workers.UvicornWorker"
# cpu_count() reports the host's CPUs on Render, not the container's share.
workers = int(os.getenv("WEB_CONCURRENCY", "2"))
timeout = int(os.getenv("GUNICORN_TIMEOUT", "120"))
graceful_timeout = 30
keepalive = 5
# Recycle workers periodically to cap memory growth from large uploads/imports.
max_requests = 2000
max_requests_jitter = 200
forwarded_allow_ips = "*"
accesslog = None
errorlog = "-"
loglevel = os.getenv("LOG_LEVEL", "info").lower()
