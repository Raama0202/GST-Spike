export const API_BASE_URL = (
  import.meta.env.VITE_API_BASE_URL ?? 'https://gst-expense-scanner.onrender.com/v1'
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

export class ApiError extends Error {
  status: number
  constructor(status: number, message: string) {
    super(message)
    this.status = status
  }
}

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

let refreshing: Promise<boolean> | null = null

async function refreshTokens(): Promise<boolean> {
  const session = loadSession()
  if (!session?.refreshToken) return false
  refreshing ??= (async () => {
    try {
      const res = await fetch(`${API_BASE_URL}/auth/token/refresh`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ refreshToken: session.refreshToken }),
      })
      if (!res.ok) return false
      const data = await res.json()
      saveSession({ ...session, accessToken: data.accessToken, refreshToken: data.refreshToken })
      return true
    } catch {
      return false
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

async function errorMessage(res: Response): Promise<string> {
  if (res.status === 429) {
    const wait = Number(res.headers.get('Retry-After'))
    const fallback = wait ? `Too many requests. Try again in ${wait >= 60 ? `${Math.ceil(wait / 60)} min` : `${wait} s`}.` : 'Too many requests. Please slow down.'
    try {
      const data = await res.json()
      return typeof data?.message === 'string' ? data.message : fallback
    } catch {
      return fallback
    }
  }
  try {
    const data = await res.json()
    if (typeof data?.message === 'string') {
      const suffix = res.status >= 500 && data.requestId ? ` (ref ${String(data.requestId).slice(0, 8)})` : ''
      return data.message + suffix
    }
  } catch {
    /* non-JSON body */
  }
  if (res.status === 413) return 'That file is too large.'
  if (res.status === 503) return 'This service is temporarily unavailable. Please try again shortly.'
  return `Request failed (${res.status})`
}

export async function api<T = unknown>(path: string, options: RequestOptions = {}, retried = false): Promise<T> {
  const { method = 'GET', body, query, auth = true } = options
  const session = loadSession()
  const headers: Record<string, string> = { Accept: 'application/json' }
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
    throw new ApiError(0, 'Cannot reach the server. It may be waking up — try again in a moment.')
  }

  if (res.status === 401 && auth && !retried) {
    if (await refreshTokens()) return api<T>(path, options, true)
    saveSession(null)
    onUnauthorized()
    throw new ApiError(401, 'Your session has expired. Please sign in again.')
  }
  if (!res.ok) throw new ApiError(res.status, await errorMessage(res))
  if (res.status === 204) return undefined as T
  const text = await res.text()
  return (text ? JSON.parse(text) : undefined) as T
}

export function mediaUrl(path: string | null | undefined): string | null {
  if (!path) return null
  return /^https?:\/\//.test(path) ? path : API_ORIGIN + path
}
