import { useEffect, useState } from 'react'
import { ShieldCheck } from 'lucide-react'
import { api } from '../api/client'
import type { GstinLookup, GstinStatus } from '../api/types'
import { Spinner } from '../components/ui'
import { isGstin } from './validation'

export const GSTIN_STATUS: Record<GstinStatus, { label: string; short: string; tone: string }> = {
  active: { label: 'Active on GST portal', short: 'Active', tone: 'green' },
  cancelled: { label: 'GSTIN cancelled', short: 'Cancelled', tone: 'red' },
  suspended: { label: 'GSTIN suspended', short: 'Suspended', tone: 'red' },
  inactive: { label: 'GSTIN inactive', short: 'Inactive', tone: 'amber' },
  not_found: { label: 'Not on GST portal', short: 'Not found', tone: 'red' },
  invalid_format: { label: 'Invalid GSTIN', short: 'Invalid', tone: 'red' },
  unverified: { label: 'Not verified', short: 'Not verified', tone: 'gray' },
}

export const GSTIN_PROBLEMS: GstinStatus[] = ['cancelled', 'suspended', 'inactive', 'not_found', 'invalid_format']

export function GstinBadge({ status, short }: { status: GstinStatus; short?: boolean }) {
  const meta = GSTIN_STATUS[status] ?? GSTIN_STATUS.unverified
  return <span className={`badge ${meta.tone}`} style={{ textTransform: 'none' }} title={meta.label}>{short ? meta.short : meta.label}</span>
}

/**
 * Checks a GSTIN on the GST portal as soon as it is complete, and offers the registered legal name.
 * `publicCheck` uses the unauthenticated sign-up endpoint.
 */
export function GstinVerifier({ gstin, publicCheck, legalName, onUseLegalName }: {
  gstin: string
  publicCheck?: boolean
  legalName?: string
  onUseLegalName?: (name: string) => void
}) {
  const value = gstin.trim().toUpperCase()
  const [result, setResult] = useState<GstinLookup | null>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const ready = isGstin(value)
  const current = result?.gstin === value ? result : null

  async function check(refresh = false) {
    setBusy(true)
    setError(null)
    try {
      const data = publicCheck
        ? await api<GstinLookup>('/public/gstin/check', { method: 'POST', auth: false, body: { gstin: value } })
        : await api<GstinLookup>(`/gstin/${value}`, { query: refresh ? { refresh: 'true' } : undefined })
      setResult(data)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not reach the GST portal')
    } finally {
      setBusy(false)
    }
  }

  useEffect(() => {
    if (ready && result?.gstin !== value) void check()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [value, ready])

  if (!ready) return null
  const portalName = current?.legalName || current?.tradeName
  return (
    <div className="full row wrap" style={{ gap: 8, fontSize: 13, marginTop: -6 }} aria-live="polite">
      {busy ? (
        <span className="faint row" style={{ gap: 6 }}><Spinner small /> Checking with the GST portal…</span>
      ) : error ? (
        <>
          <span style={{ color: 'var(--danger)' }}>{error}</span>
          <button type="button" className="btn sm ghost" onClick={() => check()}>Try again</button>
        </>
      ) : current ? (
        <>
          <GstinBadge status={current.status} />
          {current.liveCheck && portalName && <span className="muted">{portalName}{current.stateName ? ` · ${current.stateName}` : ''}</span>}
          {!current.liveCheck && <span className="faint">{current.message}</span>}
          {current.liveCheck && current.status !== 'active' && current.message && <span className="muted">{current.message}</span>}
          {onUseLegalName && current.legalName && current.legalName !== legalName?.trim() && (
            <button type="button" className="btn sm ghost" onClick={() => onUseLegalName(current.legalName!)}>Use registered legal name</button>
          )}
          {!publicCheck && current.liveCheck && (
            <button type="button" className="btn sm ghost" onClick={() => check(true)}><ShieldCheck size={14} /> Re-check</button>
          )}
        </>
      ) : null}
    </div>
  )
}
