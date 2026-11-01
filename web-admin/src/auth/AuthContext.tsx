import { createContext, useCallback, useContext, useEffect, useState, type ReactNode } from 'react'
import {
  api, COMPANY_SUSPENDED, loadSession, onSessionChangedElsewhere, saveSession, setAccessBlockedHandler, setUnauthorizedHandler,
  SUBSCRIPTION_EXPIRED, type Role, type Session,
} from '../api/client'
import { invalidate } from '../lib/cache'
import { setMonitoringScope } from '../lib/monitoring'

export interface LoginResponse {
  accessToken: string
  refreshToken: string
  billingRequired?: boolean
  user: { id: string; email: string; role: Role; companyId: string | null }
}

interface AuthValue {
  session: Session | null
  /** Set when the API reports the company as suspended mid-session. */
  suspendedMessage: string | null
  login: (email: string, password: string) => Promise<Session>
  /** Store tokens returned by an endpoint that signs the user in (e.g. firm sign-up). */
  adoptSession: (data: LoginResponse) => Session
  logout: () => Promise<void>
  /** Merge fields into the stored session (new tokens, billing state). */
  updateSession: (patch: Partial<Session>) => void
}

const AuthContext = createContext<AuthValue | null>(null)

export function AuthProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(() => loadSession())
  const [suspendedMessage, setSuspendedMessage] = useState<string | null>(null)

  const updateSession = useCallback((patch: Partial<Session>) => {
    const current = loadSession()
    if (!current) return
    const next = { ...current, ...patch }
    saveSession(next)
    setSession(next)
  }, [])

  useEffect(() => setUnauthorizedHandler(() => setSession(null)), [])
  useEffect(() => setAccessBlockedHandler((code, message) => {
    const current = loadSession()
    if (code === SUBSCRIPTION_EXPIRED && current?.role === 'company_admin' && !current.billingRequired) {
      updateSession({ billingRequired: true })
    } else if (code === COMPANY_SUSPENDED) {
      setSuspendedMessage(message)
    }
  }), [updateSession])

  useEffect(() => onSessionChangedElsewhere((next) => {
    setSession((current) => {
      if (!next) return null
      // Token rotations by another tab don't need a re-render; identity or billing changes do.
      const same = current && current.email === next.email && current.role === next.role
        && current.companyId === next.companyId && current.billingRequired === next.billingRequired
        && current.companyName === next.companyName
      return same ? current : next
    })
  }), [])

  useEffect(() => {
    invalidate()
    setSuspendedMessage(null)
  }, [session?.email, session?.companyId])
  useEffect(() => setMonitoringScope(session && { role: session.role, companyId: session.companyId }), [session?.role, session?.companyId])

  const adoptSession = useCallback((data: LoginResponse) => {
    const next: Session = {
      accessToken: data.accessToken,
      refreshToken: data.refreshToken,
      role: data.user.role,
      email: data.user.email,
      companyId: data.user.companyId,
      billingRequired: Boolean(data.billingRequired),
    }
    saveSession(next)
    setSession(next)
    setSuspendedMessage(null)
    return next
  }, [])

  const login = useCallback(async (email: string, password: string) => {
    const data = await api<LoginResponse>('/admin/auth/login', {
      method: 'POST',
      auth: false,
      body: { email: email.trim(), password },
    })
    return adoptSession(data)
  }, [adoptSession])

  const logout = useCallback(async () => {
    const current = loadSession()
    saveSession(null)
    setSession(null)
    invalidate()
    if (current?.refreshToken) {
      await api('/auth/logout', { method: 'POST', auth: false, body: { refreshToken: current.refreshToken } }).catch(() => {})
    }
  }, [])

  return (
    <AuthContext.Provider value={{ session, suspendedMessage, login, adoptSession, logout, updateSession }}>
      {children}
    </AuthContext.Provider>
  )
}

export function useAuth() {
  const value = useContext(AuthContext)
  if (!value) throw new Error('useAuth must be used inside AuthProvider')
  return value
}
