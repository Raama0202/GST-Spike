const requiredProductionEnv = ['JWT_SECRET', 'MONGODB_URI', 'WEB_ORIGIN'] as const;

export function validateEnvironment(config: Record<string, string | undefined>) {
  const nodeEnv = config.NODE_ENV ?? 'development';

  if (nodeEnv === 'production') {
    const missing = requiredProductionEnv.filter((key) => !config[key]);
    if (missing.length > 0) {
      throw new Error(`Missing required production environment variables: ${missing.join(', ')}`);
    }

    if (config.JWT_SECRET === 'dev-secret' || config.JWT_SECRET === 'change-this-secret') {
      throw new Error('JWT_SECRET must be changed before production deployment');
    }
  }

  return {
    ...config,
    NODE_ENV: nodeEnv,
    PORT: config.PORT ?? '4000',
    WEB_ORIGIN: config.WEB_ORIGIN ?? 'http://localhost:5173',
    JWT_SECRET: config.JWT_SECRET ?? 'dev-secret',
    MONGODB_URI: config.MONGODB_URI ?? 'mongodb://127.0.0.1:27017/gst-suite',
    USE_MEMORY_MONGO: config.USE_MEMORY_MONGO ?? 'auto',
    AUTO_SEED_DEMO: config.AUTO_SEED_DEMO ?? (nodeEnv === 'production' ? 'false' : 'true'),
    FAST2SMS_API_KEY: config.FAST2SMS_API_KEY ?? config.SMS_PROVIDER_API_KEY ?? '',
    FAST2SMS_ROUTE: config.FAST2SMS_ROUTE ?? 'q',
    GEMINI_API_KEY: config.GEMINI_API_KEY ?? '',
    GEMINI_MODEL: config.GEMINI_MODEL ?? 'gemini-2.0-flash',
    RAZORPAY_KEY_ID: config.RAZORPAY_KEY_ID ?? '',
    RAZORPAY_KEY_SECRET: config.RAZORPAY_KEY_SECRET ?? '',
    RAZORPAY_PLAN_MONTHLY_PAISE: config.RAZORPAY_PLAN_MONTHLY_PAISE ?? '99900',
    RAZORPAY_PLAN_YEARLY_PAISE: config.RAZORPAY_PLAN_YEARLY_PAISE ?? '999900',
    UPLOAD_DIR: config.UPLOAD_DIR ?? '',
  };
}

export function parseOrigins(value?: string) {
  return (value ?? 'http://localhost:5173')
    .split(',')
    .map((origin) => origin.trim())
    .filter(Boolean);
}
