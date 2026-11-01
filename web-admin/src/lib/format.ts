const inr = new Intl.NumberFormat('en-IN', { style: 'currency', currency: 'INR', maximumFractionDigits: 2 })
const inrCompact = new Intl.NumberFormat('en-IN', { style: 'currency', currency: 'INR', notation: 'compact', maximumFractionDigits: 1 })

export const PAYMENT_LABELS: Record<string, string> = { created: 'Pending', authorized: 'Authorized', paid: 'Paid', failed: 'Failed', refunded: 'Refunded' }

export function toNumber(value: unknown): number | null {
  if (value === null || value === undefined || value === '') return null
  const n = typeof value === 'number' ? value : Number(value)
  return Number.isFinite(n) ? n : null
}

export function money(value: unknown, compact = false): string {
  const n = toNumber(value)
  if (n === null) return '—'
  return (compact ? inrCompact : inr).format(n)
}

const DAY_ONLY = /^\d{4}-\d{2}-\d{2}$/

/** Parses timestamps normally, but reads bare YYYY-MM-DD as a local calendar day (not UTC midnight). */
function parse(value: string): Date {
  if (DAY_ONLY.test(value)) {
    const [y, m, d] = value.split('-').map(Number)
    return new Date(y, m - 1, d)
  }
  return new Date(value)
}

export function date(value: string | null | undefined, withTime = false): string {
  if (!value) return '—'
  const d = parse(value)
  if (Number.isNaN(d.getTime())) return value
  return d.toLocaleString('en-IN', withTime
    ? { day: '2-digit', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' }
    : { day: '2-digit', month: 'short', year: 'numeric' })
}

/** Short axis label ("05 Mar") for a YYYY-MM-DD day. */
export function dayLabel(value: string): string {
  const d = parse(value)
  return Number.isNaN(d.getTime()) ? value : d.toLocaleDateString('en-IN', { day: '2-digit', month: 'short' })
}

export function relative(value: string | null | undefined): string {
  if (!value) return '—'
  const diff = Date.now() - new Date(value).getTime()
  const minutes = Math.round(diff / 60000)
  if (minutes < 1) return 'just now'
  if (minutes < 60) return `${minutes}m ago`
  const hours = Math.round(minutes / 60)
  if (hours < 24) return `${hours}h ago`
  const days = Math.round(hours / 24)
  if (days < 30) return `${days}d ago`
  return date(value)
}

export function daysUntil(value: string | null | undefined): number | null {
  if (!value) return null
  const t = new Date(value).getTime()
  return Number.isNaN(t) ? null : Math.ceil((t - Date.now()) / 86400000)
}

export function initials(text: string): string {
  const parts = text.split(/[\s@._-]+/).filter(Boolean)
  return ((parts[0]?.[0] ?? '') + (parts[1]?.[0] ?? '')).toUpperCase() || '?'
}

export function currentPeriod(): string {
  const d = new Date()
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`
}

/** Today's local calendar day as YYYY-MM-DD. */
export function localToday(): string {
  const d = new Date()
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
}

export function todayStamp(): string {
  return localToday().replace(/-/g, '')
}

export function downloadBlob(filename: string, blob: Blob) {
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = filename
  document.body.appendChild(a)
  a.click()
  a.remove()
  // Safari and Firefox abort the download if the URL is revoked synchronously.
  setTimeout(() => URL.revokeObjectURL(url), 30_000)
}

export function downloadText(filename: string, text: string, mime = 'text/csv') {
  // The BOM makes Excel read CSVs as UTF-8 (₹ and Indic names otherwise come out garbled).
  const body = mime === 'text/csv' && !text.startsWith('\uFEFF') ? `\uFEFF${text}` : text
  downloadBlob(filename, new Blob([body], { type: `${mime};charset=utf-8` }))
}

function csvCell(value: unknown): string {
  if (value === null || value === undefined) return ''
  let text = String(value)
  // Neutralise spreadsheet formulas.
  if (typeof value === 'string' && /^[=+\-@]/.test(text)) text = `'${text}`
  return /[",\n\r]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text
}

export function toCsv(header: string[], rows: unknown[][]): string {
  return [header, ...rows].map((row) => row.map(csvCell).join(',')).join('\r\n')
}
