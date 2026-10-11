from functools import lru_cache
from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict

WEAK_SECRETS = {"change-this-in-production-32-bytes-minimum", "secret", "changeme"}


class Settings(BaseSettings):
    app_name: str = "GST Expense Scanner API"
    env: str = "dev"
    log_level: str = "INFO"
    log_json: bool = True

    database_url: str = "postgresql+asyncpg://postgres:postgres@localhost:5432/gst_expenses"
    db_pool_size: int = 10
    db_max_overflow: int = 10
    db_pool_recycle_seconds: int = 1800
    db_statement_timeout_ms: int = 15000

    # Empty → in-process fallback (fine for a single dev process only).
    redis_url: str = ""

    jwt_secret: str = "change-this-in-production-32-bytes-minimum"
    jwt_access_minutes: int = 60
    jwt_refresh_days: int = 30
    cors_origins: str = "http://localhost:3000,http://localhost:8000,http://localhost:8080,http://127.0.0.1:8080,http://localhost:5000"
    max_request_mb: int = 40

    # Rate limits (per minute unless stated otherwise)
    rate_limit_enabled: bool = True
    api_rate_per_minute: int = 240
    login_rate_per_minute: int = 5
    login_lockout_failures: int = 10
    login_lockout_minutes: int = 15
    otp_ip_rate_per_hour: int = 30
    auth_cache_seconds: int = 30

    # OTP delivery: console (dev only) | msg91 | twilio
    otp_dev_fixed: str | None = "123456"
    sms_provider: str = "console"
    msg91_auth_key: str = ""
    msg91_template_id: str = ""
    twilio_account_sid: str = ""
    twilio_auth_token: str = ""
    twilio_from_number: str = ""
    # Store-review / demo logins: these comma-separated mobiles skip SMS and accept
    # DEMO_OTP_CODE (6 digits). Off unless both are set.
    demo_otp_mobiles: str = ""
    demo_otp_code: str = ""
    # Seed the Acme demo tenant (well-known passwords) even when ENV=production.
    seed_demo_data: bool = False
    # One instance without Redis/R2: allows local disk + in-process caches in production.
    # Uploaded images on local disk are lost on every redeploy.
    allow_single_instance: bool = False

    # Image storage: local | r2
    storage_backend: str = "local"
    storage_path: Path = Path("./uploads")
    r2_account_id: str = ""
    r2_endpoint_url: str = ""
    r2_access_key_id: str = ""
    r2_secret_access_key: str = ""
    r2_bucket: str = ""
    signed_url_seconds: int = 900

    # Razorpay — billing endpoints return 503 until all three are set.
    razorpay_key_id: str = ""
    razorpay_key_secret: str = ""
    razorpay_webhook_secret: str = ""
    # GST added on top of the plan price at checkout (set 0 if prices already include tax).
    billing_tax_percent: float = 18.0

    sentry_dsn: str = ""
    sentry_traces_sample_rate: float = 0.05
    public_web_url: str = ""

    # GSTR files above this many rows are processed in the background.
    gstr_background_rows: int = 3000
    gstr_max_rows: int = 200000

    # Free Gemini API key from https://aistudio.google.com/apikey — required for
    # AI invoice extraction. Leave empty to force clients onto on-device OCR.
    gemini_api_key: str = ""
    gemini_model: str = "gemini-3.5-flash"
    gsp_base_url: str = ""
    gsp_client_id: str = ""
    gsp_client_secret: str = ""
    smtp_host: str = ""
    smtp_port: int = 587
    smtp_user: str = ""
    smtp_password: str = ""
    smtp_from: str = ""

    model_config = SettingsConfigDict(env_file=".env", case_sensitive=False, extra="ignore")

    @property
    def is_production(self) -> bool:
        return self.env.strip().lower() in {"production", "prod"}

    @property
    def cors_origin_list(self) -> list[str]:
        return [item.strip() for item in self.cors_origins.split(",") if item.strip()]

    @property
    def fixed_otp(self) -> str | None:
        return None if self.is_production else (self.otp_dev_fixed or None)

    @property
    def demo_otp_mobile_set(self) -> set[str]:
        if not (len(self.demo_otp_code) == 6 and self.demo_otp_code.isdigit()):
            return set()
        return {item.strip() for item in self.demo_otp_mobiles.split(",") if item.strip()}

    def demo_otp_for(self, mobile: str) -> str | None:
        return self.demo_otp_code if mobile in self.demo_otp_mobile_set else None

    @property
    def payments_configured(self) -> bool:
        return bool(self.razorpay_key_id and self.razorpay_key_secret and self.razorpay_webhook_secret)

    @property
    def r2_endpoint(self) -> str:
        if self.r2_endpoint_url:
            return self.r2_endpoint_url
        return f"https://{self.r2_account_id}.r2.cloudflarestorage.com" if self.r2_account_id else ""

    @property
    def async_database_url(self) -> str:
        url = self.database_url
        if url.startswith("postgres://"):
            url = url.replace("postgres://", "postgresql+asyncpg://", 1)
        if url.startswith("postgresql://"):
            url = url.replace("postgresql://", "postgresql+asyncpg://", 1)
        # Neon / libpq use sslmode=; asyncpg expects ssl=
        url = url.replace("sslmode=require", "ssl=require")
        return url

    def production_problems(self) -> list[str]:
        if not self.is_production:
            return []
        problems = []
        if len(self.jwt_secret) < 32 or self.jwt_secret in WEAK_SECRETS:
            problems.append("JWT_SECRET must be a random value of at least 32 characters")
        if not self.cors_origin_list or "*" in self.cors_origin_list:
            problems.append("CORS_ORIGINS must list the allowed web origins explicitly (no '*')")
        if self.storage_backend == "r2":
            if not (self.r2_endpoint and self.r2_access_key_id and self.r2_secret_access_key and self.r2_bucket):
                problems.append("R2_ACCOUNT_ID (or R2_ENDPOINT_URL), R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY and R2_BUCKET are required")
        elif not self.allow_single_instance:
            problems.append("STORAGE_BACKEND must be 'r2' (local disk is not shared between instances)")
        if not self.redis_url and not self.allow_single_instance:
            problems.append("REDIS_URL is required (rate limits and caches are shared between instances)")
        if self.demo_otp_mobiles and not (len(self.demo_otp_code) == 6 and self.demo_otp_code.isdigit()):
            problems.append("DEMO_OTP_CODE must be 6 digits when DEMO_OTP_MOBILES is set")
        return problems

    def production_warnings(self) -> list[str]:
        if not self.is_production:
            return []
        warnings = []
        if self.allow_single_instance:
            if self.storage_backend != "r2":
                warnings.append("Local image storage: uploads are lost on redeploy and not shared between instances")
            if not self.redis_url:
                warnings.append("No REDIS_URL: rate limits and caches are per-process")
        if self.demo_otp_mobile_set:
            warnings.append(f"Demo OTP enabled for {len(self.demo_otp_mobile_set)} mobile(s)")
        if not self.sms_configured:
            warnings.append("No SMS provider configured: employee OTP login returns 503 until SMS_PROVIDER is set")
        if not self.payments_configured:
            warnings.append("Razorpay keys missing: billing endpoints return 503")
        if not self.sentry_dsn:
            warnings.append("SENTRY_DSN not set: errors are only in logs")
        return warnings

    @property
    def sms_configured(self) -> bool:
        provider = self.sms_provider.strip().lower()
        if provider == "msg91":
            return bool(self.msg91_auth_key and self.msg91_template_id)
        if provider == "twilio":
            return bool(self.twilio_account_sid and self.twilio_auth_token and self.twilio_from_number)
        return provider == "console" and not self.is_production


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
