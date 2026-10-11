"""Gunicorn settings for production (uvicorn workers).

Tune with env vars: WEB_CONCURRENCY, PORT, GUNICORN_TIMEOUT.
Each worker holds DB_POOL_SIZE + DB_MAX_OVERFLOW connections at most, so keep
workers x instances x (pool + overflow) below the Postgres connection limit.
"""
import multiprocessing
import os

bind = f"0.0.0.0:{os.getenv('PORT', '8000')}"
worker_class = "uvicorn.workers.UvicornWorker"
workers = int(os.getenv("WEB_CONCURRENCY", min(multiprocessing.cpu_count() * 2 + 1, 8)))
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
