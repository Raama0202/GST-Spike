import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { FileImage } from 'lucide-react'
import { api, mediaUrl } from '../../api/client'
import type { ApprovalStatus, Invoice, Page } from '../../api/types'
import { Alert, Field, Modal, Spinner, useToast } from '../../components/ui'

export const PAGE_SIZE = 25
export const STATUSES = ['all', 'pending', 'approved', 'returned', 'rejected'] as const
export const SORTS = [
  ['uploaded_desc', 'Newest uploads first'],
  ['uploaded_asc', 'Oldest uploads first'],
  ['amount_desc', 'Highest amount first'],
  ['amount_asc', 'Lowest amount first'],
] as const
const FILTER_KEYS = ['employeeId', 'branchId', 'categoryId', 'gstinStatus', 'dateFrom', 'dateTo', 'q', 'sort'] as const

export type InvoiceQuery = Record<string, string | undefined>

/** API filters for the list/export endpoints, read from the page URL. */
export function invoiceQuery(params: URLSearchParams): InvoiceQuery {
  const query: InvoiceQuery = {}
  const status = params.get('status')
  if (status && status !== 'all') query.status = status
  for (const key of FILTER_KEYS) {
    const value = params.get(key)
    if (value) query[key] = value
  }
  return query
}

export function vendorOf(inv: Pick<Invoice, 'vendorName' | 'editedData'>): string {
  return inv.vendorName || String(inv.editedData?.vendorName ?? '') || 'Unknown vendor'
}

export function InvoiceThumb({ invoice }: { invoice: Invoice }) {
  const [failed, setFailed] = useState(false)
  const src = mediaUrl(invoice.thumbnailUrl ?? invoice.imageUrl)
  return (
    <div className="thumb">
      {src && !failed ? <img src={src} alt="" loading="lazy" onError={() => setFailed(true)} /> : <FileImage size={18} />}
    </div>
  )
}

/* ---------- Previous / next through the list the admin came from ---------- */

const NAV_KEY = 'gst-console.invoice-nav'

interface InvoiceNav {
  ids: string[]
  query: InvoiceQuery
  page: number
  pageSize: number
  total: number
  /** The list page's own URL search string, for "back to list". */
  search: string
}

export function saveInvoiceNav(nav: InvoiceNav) {
  try {
    sessionStorage.setItem(NAV_KEY, JSON.stringify(nav))
  } catch {
    /* storage full or disabled: prev/next just won't show */
  }
}

function loadInvoiceNav(): InvoiceNav | null {
  try {
    const raw = sessionStorage.getItem(NAV_KEY)
    return raw ? (JSON.parse(raw) as InvoiceNav) : null
  } catch {
    return null
  }
}

export function useInvoiceNav(id: string | undefined) {
  const navigate = useNavigate()
  const toast = useToast()
  const [nav, setNav] = useState(loadInvoiceNav)
  const [moving, setMoving] = useState(false)
  useEffect(() => setNav(loadInvoiceNav()), [id])

  const index = nav && id ? nav.ids.indexOf(id) : -1
  const known = nav !== null && index >= 0
  const hasPrev = known && (index > 0 || nav.page > 1)
  const hasNext = known && (index < nav.ids.length - 1 || nav.page * nav.pageSize < nav.total)

  async function go(dir: 1 | -1) {
    if (!nav || !known || moving) return
    const target = index + dir
    if (target >= 0 && target < nav.ids.length) {
      navigate(`/invoices/${nav.ids[target]}`)
      return
    }
    setMoving(true)
    try {
      const page = nav.page + dir
      const res = await api<Page<Invoice>>('/admin/invoices', { query: { ...nav.query, page, pageSize: nav.pageSize } })
      if (!res.items.length) return
      const next = { ...nav, ids: res.items.map((x) => x.id), page, total: res.total }
      saveInvoiceNav(next)
      setNav(next)
      navigate(`/invoices/${dir > 0 ? next.ids[0] : next.ids[next.ids.length - 1]}`)
    } catch (e) {
      toast(e instanceof Error ? e.message : 'Could not load the next invoices', 'error')
    } finally {
      setMoving(false)
    }
  }

  return {
    hasPrev,
    hasNext,
    moving,
    go,
    position: known ? (nav.page - 1) * nav.pageSize + index + 1 : null,
    total: nav?.total ?? null,
    listPath: `/invoices${nav?.search ? `?${nav.search}` : ''}`,
  }
}

/* ---------- Approve / reject / return (single or bulk) ---------- */

export type Decision = 'approve' | 'reject' | 'return'
export const DECISION_STATUS: Record<Decision, ApprovalStatus> = { approve: 'approved', reject: 'rejected', return: 'returned' }
const MAX_REMARKS = 1000

const COPY: Record<Decision, { title: string; button: string; cls: string }> = {
  approve: { title: 'Approve', button: 'Approve', cls: 'success' },
  reject: { title: 'Reject', button: 'Reject', cls: 'danger' },
  return: { title: 'Return for correction', button: 'Return', cls: 'warn' },
}

export function DecisionDialog({ decision, count, currentStatus, onSubmit, onClose }: {
  decision: Decision
  /** Bulk mode: number of selected invoices. */
  count?: number
  currentStatus?: ApprovalStatus
  onSubmit: (remarks: string | null) => Promise<void>
  onClose: () => void
}) {
  const [remarks, setRemarks] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const required = decision !== 'approve'
  const copy = COPY[decision]
  const target = DECISION_STATUS[decision]
  const changing = currentStatus && currentStatus !== 'pending' && currentStatus !== target
  const tooLong = remarks.length > MAX_REMARKS

  async function submit() {
    setBusy(true)
    setError(null)
    try {
      await onSubmit(remarks.trim() || null)
      onClose()
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Action failed')
      setBusy(false)
    }
  }

  const title = count ? `${copy.title} ${count} invoice${count === 1 ? '' : 's'}` : `${copy.title} invoice`
  return (
    <Modal
      title={title}
      subtitle="Employees see the decision and your remarks in their app."
      onClose={onClose}
      busy={busy}
      dirty={Boolean(remarks.trim())}
      footer={
        <>
          <button className="btn" onClick={onClose} disabled={busy}>Cancel</button>
          <button className={`btn ${copy.cls}`} disabled={busy || tooLong || (required && !remarks.trim())} onClick={submit}>
            {busy && <Spinner small />} {changing ? `Change to ${target}` : copy.button}
          </button>
        </>
      }
    >
      <div className="stack">
        {error && <Alert kind="error">{error}</Alert>}
        {changing && (
          <Alert kind="info">
            This invoice is already <b>{currentStatus}</b>. Changing the decision notifies the employee again and is kept in the invoice history.
          </Alert>
        )}
        {count ? <div className="muted">Invoices that are already {target} are skipped.</div> : null}
        <Field label="Remarks" hint={required ? 'required' : 'optional'}>
          <textarea
            className="textarea"
            value={remarks}
            maxLength={MAX_REMARKS + 50}
            onChange={(e) => setRemarks(e.target.value)}
            placeholder={decision === 'return' ? 'e.g. GSTIN is unreadable, please rescan' : 'Add a note for the employee'}
            autoFocus
          />
        </Field>
        <div className="faint" style={{ fontSize: 12, textAlign: 'right', color: tooLong ? '#fca5a5' : undefined }}>
          {remarks.length} / {MAX_REMARKS}
        </div>
      </div>
    </Modal>
  )
}
