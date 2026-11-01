import type { Role } from '../api/client'

export function home(role: Role, billingRequired?: boolean) {
  if (role === 'super_admin') return '/super/overview'
  return billingRequired ? '/billing' : '/dashboard'
}

/** Where to go after signing in: the page that sent the user to /login, if any. */
export function returnPath(state: unknown): string | null {
  const from = (state as { from?: unknown } | null)?.from
  return typeof from === 'string' && from.startsWith('/') && !from.startsWith('/login') && from !== '/' ? from : null
}
