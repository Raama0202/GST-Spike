from functools import lru_cache
from pathlib import Path

from pydantic import AliasChoices, Field
from pydantic_settings import BaseSettings, SettingsConfigDict

WEAK_SECRETS = {"change-this-in-production-32-bytes-minimum", "secret", "changeme"}
LOCAL_MONGO_HOSTS = ("mongodb://localhost", "mongodb://127.0.0.1", "mongodb://mongo:")


class Settings(BaseSettings):
    app_name: str = "GST Expense Scanner API"
    # Fail safe: a forgotten ENV must never enable dev OTPs or skip the production checks.
    env: str = "production"
    log_level: str = "INFO"
    log_json: bool = True

    # MongoDB Atlas: mongodb+srv://<user>:<password>@<cluster>.mongodb.net/gst_expenses?retryWrites=true&w=majority
    mongodb_uri: str = Field(
        default="mongodb://127.0.0.1:27017/?directConnection=true",
        validation_alias=AliasChoices("MONGODB_URI", "MONGO_URL", "MONGODB_URL"),
    )
    # Empty → the database named in the URI path, else "gst_expenses".
    mongodb_db: str = ""
    mongodb_max_pool_size: int = 20
    mongodb_timeout_ms: int = 10000

    # Shared store for rate limits and short-lived caches: mongo | redis | memory.
    # REDIS_URL, when set, wins. Mongo works across instances with no extra service.
    cache_backend: str = "mongo"
    redis_url: str = ""

    jwt_secret: str = "change-this-in-production-32-bytes-minimum"
    jwt_access_minutes: int = 60
    jwt_refresh_days: int = 30
    cors_origins: str = "http://localhost:3000,http://localhost:5173,http://localhost:8000,http://localhost:8080,http://127.0.0.1:8080,http://localhost:5000"
    max_request_mb: int = 40

    # Rate limits (per minute unless stated otherwise)
    rate_limit_enabled: bool = True
    api_rate_per_minute: int = 240
    login_rate_per_minute: int = 5
    login_lockout_failures: int = 10
    login_lockout_minutes: int = 15
    otp_ip_rate_per_hour: int = 30
    auth_cache_seconds: int = 30
    # Proxies in front of the app that append to X-Forwarded-For (Render: 1).
    trusted_proxy_hops: int = 1

    # OTP codes. In dev every code is OTP_DEV_FIXED; production always generates random codes.
    otp_dev_fixed: str | None = "123456"
    otp_ttl_minutes: int = 10
    # Employee login OTP channel: auto (email when the employee has one, else SMS) | email | sms
    employee_otp_channel: str = "auto"

    # SMS delivery (paid): console (dev only) | msg91 | twilio
    sms_provider: str = "console"
    msg91_auth_key: str = ""
    msg91_template_id: str = ""
    twilio_account_sid: str = ""
    twilio_auth_token: str = ""
    twilio_from_number: str = ""

    # Email delivery (free): brevo (300/day free) | resend (100/day free) | smtp (e.g. Gmail app
    # password) | console (dev only). A comma-separated list ("brevo,resend") is tried in order.
    email_provider: str = "console"
    brevo_api_key: str = ""
    resend_api_key: str = ""
    email_from: str = ""
    email_from_name: str = "GST Expense"
    smtp_host: str = ""
    smtp_port: int = 587
    smtp_user: str = ""
    smtp_password: str = ""
    smtp_from: str = ""

    # Store-review / demo logins: these comma-separated mobiles skip delivery and accept
    # DEMO_OTP_CODE (6 digits). Off unless both are set.
    demo_otp_mobiles: str = ""
    demo_otp_code: str = ""
    # Seed the Acme demo tenant (well-known passwords) even when ENV=production.
    seed_demo_data: bool = False
    # Single instance with local-disk images: allowed in production only when set.
    allow_single_instance: bool = False

    # Self-service firm registration from the web console.
    allow_self_signup: bool = True
    # Require an emailed code before the firm is created. Turning this off lets
    # sign-up work without an email provider, at the cost of unverified emails.
    signup_verify_email: bool = True
    signup_plan_code: str = "starter"
    signup_trial_days: int = 14
    signup_trial_seats: int = 5

    # Image storage: gridfs (inside MongoDB, no extra service) | r2 | local
    storage_backend: str = "gridfs"
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
    # Only charged when BUSINESS_GSTIN is set: an unregistered seller cannot collect GST.
    billing_tax_percent: float = 18.0
    # Your business: printed on subscription tax invoices, receipts and the public legal pages
    # (Razorpay checks these pages before activating live payments).
    business_name: str = "GST Expense"
    business_legal_name: str = ""
    business_gstin: str = ""
    business_address: str = ""
    business_email: str = ""
    business_phone: str = ""
    # SAC for SaaS subscriptions (997331 = licence to use software); confirm with your CA.
    billing_sac_code: str = "997331"
    billing_invoice_prefix: str = "GSTX"
    # Subscription renewal reminder emails, days before expiry.
    renewal_reminder_days: str = "7,3,1"
    # In-process hourly jobs (renewal reminders). Safe with several workers.
    background_jobs: bool = True

    sentry_dsn: str = ""
    sentry_traces_sample_rate: float = 0.05
    public_web_url: str = ""

    # GSTR files above this many rows are processed in the background.
    gstr_background_rows: int = 3000
    gstr_max_rows: int = 200000

    # Free Gemini API key from https://aistudio.google.com/apikey — required for
    # AI invoice extraction. Leave empty to force clients onto on-device OCR.
    gemini_api_key: str = ""
    gemini_model: str = "gemini-flash-latest"
    gsp_base_url: str = ""
    gsp_client_id: str = ""
    gsp_client_secret: str = ""

    # Live GSTIN verification against the GST network (registration status, legal name).
    # The GST portal only grants API access through GSPs, so use one of:
    #   sandbox  - Sandbox by Quicko (developer.sandbox.co.in): API key + API secret
    #   appyflow - AppyFlow (appyflow.in/verify-gst): key_secret as the API key
    #   custom   - any GSP: GSTIN_VERIFY_BASE_URL with "{gstin}", key sent in GSTIN_VERIFY_KEY_HEADER
    # Empty provider = only the offline format/checksum check runs.
    gstin_verify_provider: str = ""
    gstin_verify_api_key: str = ""
    gstin_verify_api_secret: str = ""
    gstin_verify_base_url: str = ""
    gstin_verify_key_header: str = "x-api-key"
    gstin_verify_cache_hours: int = 24
    # Refuse firm registration when the portal says the GSTIN does not exist or is cancelled.
    gstin_verify_enforce_signup: bool = True

    # Firebase Cloud Messaging (free). Paste the service-account JSON (raw or
    # base64) from Firebase console > Project settings > Service accounts.
    # Empty = notifications stay in-app only.
    fcm_service_account_json: str = ""

    # `python -m app.cli backup`: S3-compatible bucket (reuses the R2_* keys).
    # Empty = archives are written to ./backups instead.
    backup_bucket: str = ""
    backup_prefix: str = "backups"
    backup_keep_days: int = 14

    model_config = SettingsConfigDict(env_file=".env", case_sensitive=False, extra="ignore", populate_by_name=True)

    @property
    def gstin_verify_configured(self) -> bool:
        provider = self.gstin_verify_provider.strip().lower()
        if provider == "sandbox":
            return bool(self.gstin_verify_api_key and self.gstin_verify_api_secret)
        if provider == "appyflow":
            return bool(self.gstin_verify_api_key)
        if provider == "custom":
            return "{gstin}" in self.gstin_verify_base_url
        return False

    @property
    def is_production(self) -> bool:
        return self.env.strip().lower() in {"production", "prod"}

    @property
    def cors_origin_list(self) -> list[str]:
        return [item.strip().rstrip("/") for item in self.cors_origins.split(",") if item.strip()]

    @property
    def fixed_otp(self) -> str | None:
        return None if self.is_production else (self.otp_dev_fixed or None)

    @property
    def demo_otp_mobile_set(self) -> set[str]:
        from app.services.phone import canonical_mobile

        if not (len(self.demo_otp_code) == 6 and self.demo_otp_code.isdigit()):
            return set()
        mobiles = set()
        for item in self.demo_otp_mobiles.split(","):
            try:
                mobiles.add(canonical_mobile(item))
            except ValueError:
                continue
        return mobiles

    def demo_otp_for(self, mobile: str) -> str | None:
        return self.demo_otp_code if mobile in self.demo_otp_mobile_set else None

    @property
    def payments_configured(self) -> bool:
        return bool(self.razorpay_key_id and self.razorpay_key_secret and self.razorpay_webhook_secret)

    @property
    def payments_live(self) -> bool:
        return self.razorpay_key_id.startswith("rzp_live_")

    @property
    def business_gstin_clean(self) -> str:
        return self.business_gstin.strip().upper()

    @property
    def effective_tax_percent(self) -> float:
        return self.billing_tax_percent if self.business_gstin_clean else 0.0

    @property
    def renewal_reminder_day_list(self) -> list[int]:
        days = {int(d) for d in self.renewal_reminder_days.split(",") if d.strip().isdigit()}
        return sorted((d for d in days if 0 < d <= 60), reverse=True)

    @property
    def r2_endpoint(self) -> str:
        if self.r2_endpoint_url:
            return self.r2_endpoint_url
        return f"https://{self.r2_account_id}.r2.cloudflarestorage.com" if self.r2_account_id else ""

    @property
    def sender_email(self) -> str:
        return self.email_from or self.smtp_from or self.smtp_user

    def production_problems(self) -> list[str]:
        if not self.is_production:
            return []
        problems = []
        if len(self.jwt_secret) < 32 or self.jwt_secret in WEAK_SECRETS:
            problems.append("JWT_SECRET must be a random value of at least 32 characters")
        if not self.cors_origin_list or "*" in self.cors_origin_list:
            problems.append("CORS_ORIGINS must list the allowed web origins explicitly (no '*')")
        if self.mongodb_uri.startswith(LOCAL_MONGO_HOSTS):
            problems.append("MONGODB_URI must point at your MongoDB Atlas cluster (mongodb+srv://...)")
        if self.storage_backend == "r2":
            if not (self.r2_endpoint and self.r2_access_key_id and self.r2_secret_access_key and self.r2_bucket):
                problems.append("R2_ACCOUNT_ID (or R2_ENDPOINT_URL), R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY and R2_BUCKET are required")
        elif self.storage_backend == "local" and not self.allow_single_instance:
            problems.append("STORAGE_BACKEND must be 'gridfs' or 'r2' (local disk is wiped on every Render deploy)")
        elif self.storage_backend not in ("gridfs", "local"):
            problems.append("STORAGE_BACKEND must be one of gridfs, r2, local")
        if self.cache_backend == "memory" and not self.redis_url and not self.allow_single_instance:
            problems.append("CACHE_BACKEND=memory is per-process; use mongo or set REDIS_URL")
        if self.demo_otp_mobiles and not (len(self.demo_otp_code) == 6 and self.demo_otp_code.isdigit()):
            problems.append("DEMO_OTP_CODE must be 6 digits when DEMO_OTP_MOBILES is set")
        unknown = [p.strip() for p in self.email_provider.split(",") if p.strip().lower() not in {"brevo", "resend", "smtp", "console", ""}]
        if unknown:
            problems.append(f"EMAIL_PROVIDER has unknown provider(s): {', '.join(unknown)} (use brevo, resend or smtp)")
        return problems

    def production_warnings(self) -> list[str]:
        if not self.is_production:
            return []
        warnings = []
        if self.seed_demo_data:
            warnings.append("SEED_DEMO_DATA is on: demo companies and logins will be created in the production database.")
        if any("localhost" in origin or "127.0.0.1" in origin for origin in self.cors_origin_list):
            warnings.append("CORS_ORIGINS still allows localhost origins")
        if self.storage_backend == "local":
            warnings.append("Local image storage: uploads are lost on redeploy and not shared between instances")
        if self.storage_backend == "gridfs":
            warnings.append("Images are stored in MongoDB GridFS; watch Atlas storage (M0 free tier = 512 MB) or switch to R2")
        if self.demo_otp_mobile_set:
            warnings.append(f"Demo OTP enabled for {len(self.demo_otp_mobile_set)} mobile(s)")
        if not self.email_configured:
            warnings.append(
                "No email provider configured: password reset, email OTP"
                + (" and firm sign-up" if self.signup_verify_email else "")
                + " return 503 until EMAIL_PROVIDER is set"
            )
        if not self.sms_configured and not self.email_configured:
            warnings.append("Neither SMS nor email OTP is configured: employee login returns 503")
        if not self.payments_configured:
            warnings.append("Razorpay keys missing: billing endpoints return 503")
        elif not self.payments_live:
            warnings.append("Razorpay TEST keys in production: customers cannot pay real money (switch to rzp_live_ keys)")
        missing_business = [
            name for name, value in (
                ("BUSINESS_LEGAL_NAME", self.business_legal_name), ("BUSINESS_ADDRESS", self.business_address),
                ("BUSINESS_EMAIL", self.business_email), ("BUSINESS_PHONE", self.business_phone),
            ) if not value.strip()
        ]
        if missing_business:
            warnings.append(
                f"{', '.join(missing_business)} not set: invoices and the legal/contact pages Razorpay reviews show placeholders"
            )
        if not self.business_gstin_clean:
            warnings.append("BUSINESS_GSTIN not set: subscriptions are sold without GST (bill of supply, no tax charged)")
        if not self.gemini_api_key:
            warnings.append("GEMINI_API_KEY not set: bills are read on-device only (no handwritten bill support)")
        if not self.sentry_dsn:
            warnings.append("SENTRY_DSN not set: errors are only in logs")
        if not self.fcm_service_account_json:
            warnings.append("FCM_SERVICE_ACCOUNT_JSON not set: no push notifications (in-app inbox only)")
        if not self.gstin_verify_configured:
            warnings.append("GSTIN_VERIFY_PROVIDER/API key not set: GSTINs are format-checked only, not verified with the GST portal")
        return warnings

    @property
    def sms_configured(self) -> bool:
        provider = self.sms_provider.strip().lower()
        if provider == "msg91":
            return bool(self.msg91_auth_key and self.msg91_template_id)
        if provider == "twilio":
            return bool(self.twilio_account_sid and self.twilio_auth_token and self.twilio_from_number)
        return provider == "console" and not self.is_production

    @property
    def email_providers(self) -> list[str]:
        """Configured email providers that have their credentials, in fallback order."""
        names = [item.strip().lower() for item in self.email_provider.split(",") if item.strip()]
        return [name for name in dict.fromkeys(names) if self._email_provider_ready(name)]

    def _email_provider_ready(self, name: str) -> bool:
        if name == "brevo":
            return bool(self.brevo_api_key and self.sender_email)
        if name == "resend":
            return bool(self.resend_api_key and self.sender_email)
        if name == "smtp":
            return bool(self.smtp_host and self.sender_email)
        return name == "console" and not self.is_production

    @property
    def email_configured(self) -> bool:
        return bool(self.email_providers)


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
