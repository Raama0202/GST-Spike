/** Optional Sentry error reporting; the SDK is only downloaded when VITE_SENTRY_DSN is set. */
type SentryModule = typeof import('@sentry/react')

const dsn = import.meta.env.VITE_SENTRY_DSN as string | undefined
let sentry: Promise<SentryModule | null> | null = null

export function initMonitoring() {
  if (!dsn || sentry) return
  sentry = import('@sentry/react')
    .then((module) => {
      module.init({
        dsn,
        environment: import.meta.env.MODE,
        release: import.meta.env.VITE_RELEASE as string | undefined,
        tracesSampleRate: 0,
      })
      return module
    })
    .catch(() => null)
}

export function reportError(error: unknown, context?: Record<string, unknown>) {
  if (!sentry) return
  void sentry.then((module) => module?.captureException(error, context ? { extra: context } : undefined))
}

export function setMonitoringScope(scope: { role: string; companyId?: string | null } | null) {
  if (!sentry) return
  void sentry.then((module) => {
    module?.setTag('role', scope?.role ?? 'anonymous')
    module?.setTag('company', scope?.companyId ?? 'none')
  })
}
