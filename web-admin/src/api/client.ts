const CONFIGURED_API = import.meta.env.VITE_API_BASE_URL ?? 'https://gst-expense-scanner.onrender.com/v1'

/** `same-origin` builds (the Windows launcher) call `/v1` on whatever host serves the console. */
export const API_BASE_URL = (
  CONFIGURED_API === 'same-origin' ? `${window.location.origin}/v1` : CONFIGURED_API
).replace(/\/+$/, '')

export const API_ORIGIN = new URL(API_BASE_URL).origin

const SESSION_KEY = 'gst-console.session'

export type Role = 'super_admin' | 'company_admin'

export interface Session {
  accessToken: string
  refreshToken: string
  role: Role
  email: string
  companyId: string | null
  companyName?: string | null
  /** Subscription lapsed; only billing works until the company renews. */
  billingRequired?: boolean
}

export function loadSession(): Session | null {
  try {
    const raw = localStorage.getItem(SESSION_KEY)
    if (!raw) return null
    const parsed = JSON.parse(raw) as Session
    return parsed.accessToken && parsed.role ? parsed : null
  } catch {
    localStorage.removeItem(SESSION_KEY)
    return null
  }
}

export function saveSession(session: Session | null) {
  if (session) localStorage.setItem(SESSION_KEY, JSON.stringify(session))
  else localStorage.removeItem(SESSION_KEY)
}

/** Fires when another tab signs in, refreshes tokens or signs out. */
export function onSessionChangedElsewhere(handler: (session: Session | null) => void): () => void {
  const listener = (e: StorageEvent) => {
    if (e.key === SESSION_KEY || e.key === null) handler(loadSession())
  }
  window.addEventListener('storage', listener)
  return () => window.removeEventListener('storage', listener)
}

export class ApiError extends Error {
  status: number
  code?: string
  constructor(status: number, message: string, code?: string) {
    super(message)
    this.status = status
    this.code = code
  }
}

export const SUBSCRIPTION_EXPIRED = 'SUBSCRIPTION_EXPIRED'
export const COMPANY_SUSPENDED = 'COMPANY_SUSPENDED'

type Query = Record<string, string | number | boolean | null | undefined>

interface RequestOptions {
  method?: 'GET' | 'POST' | 'PUT' | 'PATCH' | 'DELETE'
  body?: unknown
  query?: Query
  auth?: boolean
}

let onUnauthorized: () => void = () => {}
export function setUnauthorizedHandler(handler: () => void) {
  onUnauthorized = handler
}

let onAccessBlocked: (code: string, message: string) => void = () => {}
/** Called for 403s that mean the whole company lost access (expired or suspended). */
export function setAccessBlockedHandler(handler: (code: string, message: string) => void) {
  onAccessBlocked = handler
}

type RefreshResult = 'ok' | 'invalid' | 'unavailable'
let refreshing: Promise<RefreshResult> | null = null

async function doRefresh(usedAccessToken: string): Promise<RefreshResult> {
  const session = loadSession()
  if (!session?.refreshToken) return 'invalid'
  // Another tab (or an earlier call) already rotated the tokens.
  if (session.accessToken !== usedAccessToken) return 'ok'
  let res: Response
  try {
    res = await fetch(`${API_BASE_URL}/auth/token/refresh`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ refreshToken: session.refreshToken }),
    })
  } catch {
    return 'unavailable'
  }
  if (res.status === 401) {
    // A tab that refreshed at the same moment wins the rotation; our copy is then stale, not revoked.
    const latest = loadSession()
    return latest && latest.refreshToken !== session.refreshToken ? 'ok' : 'invalid'
  }
  if (!res.ok) return 'unavailable'
  try {
    const data = await res.json()
    const latest = loadSession() ?? session
    saveSession({ ...latest, accessToken: data.accessToken, refreshToken: data.refreshToken })
    return 'ok'
  } catch {
    return 'unavailable'
  }
}

/** One refresh at a time, per tab and (where Web Locks exist) across tabs. */
function refreshTokens(usedAccessToken: string): Promise<RefreshResult> {
  refreshing ??= (async () => {
    try {
      if (typeof navigator !== 'undefined' && navigator.locks?.request) {
        return await navigator.locks.request('gst-console.refresh', () => doRefresh(usedAccessToken))
      }
      return await doRefresh(usedAccessToken)
    } finally {
      refreshing = null
    }
  })()
  return refreshing
}

function buildUrl(path: string, query?: Query) {
  const url = new URL(API_BASE_URL + path)
  for (const [key, value] of Object.entries(query ?? {})) {
    if (value !== undefined && value !== null && value !== '') url.searchParams.set(key, String(value))
  }
  return url.toString()
}

async function readError(res: Response): Promise<{ message: string; code?: string }> {
  let data: { message?: unknown; code?: unknown; requestId?: unknown } | null = null
  try {
    data = await res.json()
  } catch {
    /* non-JSON body */
  }
  const code = typeof data?.code === 'string' ? data.code : undefined
  if (typeof data?.message === 'string') {
    const suffix = res.status >= 500 && data.requestId ? ` (ref ${String(data.requestId).slice(0, 8)})` : ''
    return { message: data.message + suffix, code }
  }
  if (res.status === 429) {
    const wait = Number(res.headers.get('Retry-After'))
    return { message: wait ? `Too many requests. Try again in ${wait >= 60 ? `${Math.ceil(wait / 60)} min` : `${wait} s`}.` : 'Too many requests. Please slow down.' }
  }
  if (res.status === 413) return { message: 'That file is too large.' }
  if (res.status === 503) return { message: 'This service is temporarily unavailable. Please try again shortly.' }
  return { message: `Request failed (${res.status})`, code }
}

function blockedCode(status: number, error: { message: string; code?: string }): string | null {
  if (status !== 403) return null
  if (error.code === SUBSCRIPTION_EXPIRED || error.code === COMPANY_SUSPENDED) return error.code
  // Older API builds send only the message.
  if (/^subscription expired/i.test(error.message)) return SUBSCRIPTION_EXPIRED
  if (/^company is (suspended|not active)/i.test(error.message)) return COMPANY_SUSPENDED
  return null
}

const NETWORK_ERROR = 'Cannot reach the server. It may be waking up — try again in a moment.'

async function send(path: string, options: RequestOptions, accept: string, retried = false): Promise<Response> {
  const { method = 'GET', body, query, auth = true } = options
  const session = loadSession()
  const headers: Record<string, string> = { Accept: accept }
  let payload: BodyInit | undefined
  if (body instanceof FormData) payload = body
  else if (body !== undefined) {
    headers['Content-Type'] = 'application/json'
    payload = JSON.stringify(body)
  }
  if (auth && session) {
    headers.Authorization = `Bearer ${session.accessToken}`
    if (session.companyId) headers['X-Company-Id'] = session.companyId
  }

  let res: Response
  try {
    res = await fetch(buildUrl(path, query), { method, headers, body: payload })
  } catch {
    throw new ApiError(0, NETWORK_ERROR)
  }

  if (res.status === 401 && auth && session && !retried) {
    const outcome = await refreshTokens(session.accessToken)
    if (outcome === 'ok') return send(path, options, accept, true)
    if (outcome === 'unavailable') throw new ApiError(0, NETWORK_ERROR)
    saveSession(null)
    onUnauthorized()
    throw new ApiError(401, 'Your session has expired. Please sign in again.')
  }
  if (!res.ok) {
    const error = await readError(res)
    const blocked = auth ? blockedCode(res.status, error) : null
    if (blocked) {
      const message = blocked === COMPANY_SUSPENDED
        ? 'Your company account is suspended. Contact GST Expense support to restore access.'
        : 'Your subscription has expired. Renew it on the Billing page to restore access.'
      onAccessBlocked(blocked, message)
      throw new ApiError(res.status, message, blocked)
    }
    throw new ApiError(res.status, error.message, error.code)
  }
  return res
}

export async function api<T = unknown>(path: string, options: RequestOptions = {}): Promise<T> {
  const res = await send(path, options, 'application/json')
  if (res.status === 204) return undefined as T
  const text = await res.text()
  return (text ? JSON.parse(text) : undefined) as T
}

/** Authenticated file download (exports need the Bearer header, so a plain link won't do). */
export async function apiBlob(path: string, query: Query, fallbackName: string): Promise<{ blob: Blob; filename: string }> {
  const res = await send(path, { query }, '*/*')
  const disposition = res.headers.get('Content-Disposition') ?? ''
  const match = /filename\*=UTF-8''([^;]+)|filename="?([^";]+)"?/i.exec(disposition)
  const filename = match ? decodeURIComponent(match[1] ?? match[2]) : fallbackName
  return { blob: await res.blob(), filename }
}

export function mediaUrl(path: string | null | undefined): string | null {
  if (!path) return null
  return /^https?:\/\//.test(path) ? path : API_ORIGIN + path
}
