export const MIN_PASSWORD = 10
export const PASSWORD_HINT = `${MIN_PASSWORD}+ characters`
export const GSTIN_PATTERN = /^[0-9]{2}[A-Z0-9]{10}[0-9A-Z]Z[0-9A-Z]$/

/** Same rule for registration, reset, change and super-admin provisioning. */
export function passwordProblem(password: string): string | null {
  if (password.length < MIN_PASSWORD) return `Password must be at least ${MIN_PASSWORD} characters.`
  if (password.trim().length === 0) return 'Password cannot be only spaces.'
  return null
}

export function isEmail(value: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(value.trim())
}

export function isGstin(value: string): boolean {
  return GSTIN_PATTERN.test(value.trim().toUpperCase())
}

/** Strips spaces, dashes and brackets; the API canonicalises Indian numbers to 10 digits. */
export function cleanMobile(value: string): string {
  return value.replace(/[\s\-()]/g, '')
}

export function isMobile(value: string): boolean {
  return /^\+?[0-9]{10,15}$/.test(cleanMobile(value))
}
