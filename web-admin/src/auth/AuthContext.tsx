import { createContext, useCallback, useContext, useEffect, useState, type ReactNode } from 'react'
import { api, loadSession, saveSession, setUnauthorizedHandler, type Role, type Session } from '../api/client'

interface LoginResponse {
  accessToken: string
  refreshToken: string
  billingRequired?: boolean
  user: { id: string; email: string; role: Role; companyId: string | null }
}

interface AuthValue {
  session: Session | null
  login: (email: string, password: string) => Promise<Session>
  logout: () => Promise<void>
  /** Merge fields into the stored session (new tokens, billing state). */
  updateSession: (patch: Partial<Session>) => void
}

const AuthContext = createContext<AuthValue | null>(null)

export function AuthProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(() => loadSession())

  useEffect(() => setUnauthorizedHandler(() => setSession(null)), [])

  const login = useCallback(async (email: string, password: string) => {
    const data = await api<LoginResponse>('/admin/auth/login', {
      method: 'POST',
      auth: false,
      body: { email: email.trim(), password },
    })
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
    return next
  }, [])

  const updateSession = useCallback((patch: Partial<Session>) => {
    const current = loadSession()
    if (!current) return
    const next = { ...current, ...patch }
    saveSession(next)
    setSession(next)
  }, [])

  const logout = useCallback(async () => {
    const current = loadSession()
    saveSession(null)
    setSession(null)
    if (current?.refreshToken) {
      await api('/auth/logout', { method: 'POST', auth: false, body: { refreshToken: current.refreshToken } }).catch(() => {})
    }
  }, [])

  return <AuthContext.Provider value={{ session, login, logout, updateSession }}>{children}</AuthContext.Provider>
}

export function useAuth() {
  const value = useContext(AuthContext)
  if (!value) throw new Error('useAuth must be used inside AuthProvider')
  return value
}
