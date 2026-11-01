import { useEffect, useRef, useState } from 'react'
import { AlertTriangle, ExternalLink, FileImage, Maximize2, RefreshCw, RotateCw, ShieldCheck, X, ZoomIn } from 'lucide-react'
import { api, mediaUrl } from '../../api/client'
import type { GstinCheck, InvoiceDetail, InvoiceFields, InvoiceHistoryEntry, NamedResource } from '../../api/types'
import { Alert, Card, Field, Modal, Spinner, useToast } from '../../components/ui'
import { date, localToday, money, toNumber } from '../../lib/format'
import { GSTIN_STATUS, GstinBadge } from '../../lib/gstin'
import { loadCategories } from '../../lib/lookups'
import { GSTIN_PATTERN, isEmail } from '../../lib/validation'

/* ---------- Bill image with zoom and expired-link recovery ---------- */

export function BillImage({ invoice, onExpired }: { invoice: InvoiceDetail; onExpired: () => Promise<void> }) {
  const src = mediaUrl(invoice.imageUrl ?? invoice.originalImageUrl)
  const original = mediaUrl(invoice.originalImageUrl) ?? src
  const [failedSrc, setFailedSrc] = useState<string | null>(null)
  const [autoRetried, setAutoRetried] = useState(false)
  const [retrying, setRetrying] = useState(false)
  const [viewing, setViewing] = useState(false)
  const failed = !src || failedSrc === src

  async function refresh() {
    setRetrying(true)
    try { await onExpired() } finally { setRetrying(false) }
  }

  function onError() {
    // Image links are short-lived signed URLs; fetching the invoice again issues fresh ones.
    if (!autoRetried) {
      setAutoRetried(true)
      void refresh()
    } else {
      setFailedSrc(src)
    }
  }

  return (
    <>
      <div className="image-frame">
        {!failed ? (
          <button type="button" className="linkish" style={{ width: '100%', display: 'block' }} onClick={() => setViewing(true)} aria-label="Open the bill image full size">
            <img className="zoomable" src={src} alt="Bill" onError={onError} />
          </button>
        ) : (
          <div className="empty">
            <div className="empty-icon"><FileImage size={24} /></div>
            <h4>Image unavailable</h4>
            <div>{src ? 'The image link expired or the file could not be loaded.' : 'No image was uploaded with this bill.'}</div>
            {src && (
              <button className="btn sm" style={{ marginTop: 14 }} disabled={retrying} onClick={() => { setFailedSrc(null); void refresh() }}>
                {retrying ? <Spinner small /> : <RefreshCw size={14} />} Try again
              </button>
            )}
          </div>
        )}
      </div>
      {!failed && (
        <div className="row wrap" style={{ marginTop: 12 }}>
          <button className="btn sm" onClick={() => setViewing(true)}><Maximize2 size={14} /> View full size</button>
          {original && <a className="btn sm ghost" href={original} target="_blank" rel="noreferrer"><ExternalLink size={14} /> Open in new tab</a>}
        </div>
      )}
      {viewing && original && <Lightbox src={original} onClose={() => setViewing(false)} />}
    </>
  )
}

function Lightbox({ src, onClose }: { src: string; onClose: () => void }) {
  const [zoomed, setZoomed] = useState(false)
  const [rotation, setRotation] = useState(0)
  const closeRef = useRef<HTMLButtonElement>(null)

  useEffect(() => {
    const previous = document.activeElement instanceof HTMLElement ? document.activeElement : null
    closeRef.current?.focus()
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && onClose()
    document.addEventListener('keydown', onKey)
    document.body.classList.add('modal-open')
    return () => {
      document.removeEventListener('keydown', onKey)
      document.body.classList.remove('modal-open')
      if (previous?.isConnected) previous.focus()
    }
  }, [onClose])

  return (
    <div className="lightbox" role="dialog" aria-modal="true" aria-label="Bill image">
      <div className="lightbox-bar">
        <button className="btn sm" onClick={() => setZoomed((z) => !z)} aria-pressed={zoomed}><ZoomIn size={14} /> {zoomed ? 'Fit to screen' : 'Actual size'}</button>
        <button className="btn sm" onClick={() => setRotation((r) => (r + 90) % 360)}><RotateCw size={14} /> Rotate</button>
        <a className="btn sm ghost" href={src} target="_blank" rel="noreferrer"><ExternalLink size={14} /> New tab</a>
        <button ref={closeRef} className="btn sm" style={{ marginLeft: 'auto' }} onClick={onClose} aria-label="Close image"><X size={16} /> Close</button>
      </div>
      <div className={`lightbox-stage ${zoomed ? 'zoomed' : ''}`} onClick={(e) => e.target === e.currentTarget && onClose()}>
        <img src={src} alt="Bill, full size" style={{ transform: rotation ? `rotate(${rotation}deg)` : undefined }} onClick={() => setZoomed((z) => !z)} />
      </div>
    </div>
  )
}

/* ---------- Supplier GSTIN on the GST portal ---------- */

export function GstinPortalCard({ invoice, onChecked }: { invoice: InvoiceDetail; onChecked: () => Promise<void> }) {
  const toast = useToast()
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const check = invoice.gstinCheck
  const vendor = String(invoice.editedData?.vendorName ?? invoice.ocrData?.vendorName ?? invoice.vendorName ?? '')
  const portalName = check?.legalName || check?.tradeName
  const nameDiffers = Boolean(portalName && vendor && !sameName(vendor, check?.legalName) && !sameName(vendor, check?.tradeName))

  async function verify() {
    setBusy(true)
    setError(null)
    try {
      const result = await api<{ gstinCheck: GstinCheck | null }>(`/admin/invoices/${invoice.id}/verify-gstin`, { method: 'POST' })
      toast(result.gstinCheck ? GSTIN_STATUS[result.gstinCheck.status]?.label ?? 'GSTIN checked' : 'GSTIN checked')
      await onChecked()
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not reach the GST portal')
    } finally {
      setBusy(false)
    }
  }

  return (
    <Card
      title="Supplier GSTIN"
      subtitle={invoice.gstin ? undefined : 'No GSTIN on this bill'}
      actions={invoice.gstin ? (
        <button className="btn sm" onClick={verify} disabled={busy}>
          {busy ? <Spinner small /> : <ShieldCheck size={14} />} Verify with GST portal
        </button>
      ) : undefined}
    >
      {error && <div style={{ marginBottom: 12 }}><Alert kind="error">{error}</Alert></div>}
      {!invoice.gstin ? (
        <div className="faint">Add the supplier's GSTIN with <b>Correct</b> to claim input tax credit.</div>
      ) : !check ? (
        <div className="faint">Checking with the GST portal… Refresh in a moment, or verify now.</div>
      ) : (
        <div className="stack" style={{ gap: 10 }}>
          <div className="row wrap" style={{ gap: 8 }}>
            <GstinBadge status={check.status} />
            <span className="mono">{invoice.gstin}</span>
          </div>
          {(check.legalName || check.tradeName) && (
            <dl className="kv">
              {check.legalName && <><dt>Legal name</dt><dd>{check.legalName}</dd></>}
              {check.tradeName && check.tradeName !== check.legalName && <><dt>Trade name</dt><dd>{check.tradeName}</dd></>}
              {check.cancellationDate && <><dt>Cancelled on</dt><dd>{date(check.cancellationDate)}</dd></>}
            </dl>
          )}
          {check.status !== 'active' && check.message && <div className="muted" style={{ fontSize: 13 }}>{check.message}</div>}
          {nameDiffers && (
            <div className="row" style={{ color: 'var(--warning)', fontSize: 13, alignItems: 'flex-start' }}>
              <AlertTriangle size={15} style={{ flexShrink: 0, marginTop: 2 }} />
              The vendor on the bill ("{vendor}") doesn't match the name registered for this GSTIN.
            </div>
          )}
          {check.checkedAt && <div className="faint" style={{ fontSize: 12 }}>Checked {date(check.checkedAt, true)}</div>}
        </div>
      )}
    </Card>
  )
}

function sameName(a: string, b: string | null | undefined) {
  if (!b) return false
  const clean = (s: string) => s.toLowerCase().replace(/\b(m\/s|pvt|private|ltd|limited|llp|the|and|&)\b/g, '').replace(/[^a-z0-9]/g, '')
  const x = clean(a)
  const y = clean(b)
  return Boolean(x && y && (x.includes(y) || y.includes(x)))
}

/* ---------- Decision history ---------- */

const ACTIONS: Record<string, { label: string; tone: string }> = {
  uploaded: { label: 'Uploaded', tone: '#22d3ee' },
  resubmitted: { label: 'Resubmitted', tone: '#22d3ee' },
  approved: { label: 'Approved', tone: '#34d399' },
  rejected: { label: 'Rejected', tone: '#f87171' },
  returned: { label: 'Returned for correction', tone: '#a78bfa' },
  edited: { label: 'Edited by admin', tone: '#fbbf24' },
}

export function HistoryTimeline({ entries }: { entries: InvoiceHistoryEntry[] }) {
  if (!entries.length) return <div className="faint">No history recorded yet.</div>
  return (
    <ol className="timeline">
      {entries.map((entry, i) => {
        const meta = ACTIONS[entry.action] ?? { label: entry.action, tone: '#7c9cff' }
        return (
          <li key={`${entry.at}-${i}`} style={{ '--tone': meta.tone } as React.CSSProperties}>
            <div className="row between wrap" style={{ gap: 6 }}>
              <span className="cell-title">{meta.label}</span>
              <span className="faint nowrap" style={{ fontSize: 12 }}>{date(entry.at, true)}</span>
            </div>
            {entry.byName && <div className="cell-sub">by {entry.byName}</div>}
            {entry.remarks && <div className="muted" style={{ marginTop: 4, whiteSpace: 'pre-wrap', fontSize: 13 }}>{entry.remarks}</div>}
          </li>
        )
      })}
    </ol>
  )
}

/* ---------- Admin correction of extracted fields ---------- */

const EDITABLE: { key: Extract<keyof InvoiceFields, string>; label: string; kind: 'text' | 'money' | 'date' | 'gstin' | 'email'; full?: boolean }[] = [
  { key: 'vendorName', label: 'Vendor', kind: 'text', full: true },
  { key: 'gstin', label: 'Vendor GSTIN', kind: 'gstin' },
  { key: 'invoiceNumber', label: 'Invoice number', kind: 'text' },
  { key: 'invoiceDate', label: 'Invoice date', kind: 'date' },
  { key: 'taxableValue', label: 'Taxable value (₹)', kind: 'money' },
  { key: 'cgst', label: 'CGST (₹)', kind: 'money' },
  { key: 'sgst', label: 'SGST (₹)', kind: 'money' },
  { key: 'igst', label: 'IGST (₹)', kind: 'money' },
  { key: 'discount', label: 'Discount (₹)', kind: 'money' },
  { key: 'netAmount', label: 'Invoice value (₹)', kind: 'money' },
  { key: 'supplierPhone', label: 'Supplier phone', kind: 'text' },
  { key: 'supplierEmail', label: 'Supplier email', kind: 'email' },
]

type Draft = Record<string, string>

function draftOf(invoice: InvoiceDetail): Draft {
  const draft: Draft = { categoryId: invoice.categoryId ?? '' }
  for (const { key } of EDITABLE) {
    const value = invoice.editedData?.[key] ?? invoice.ocrData?.[key]
    draft[key] = value === null || value === undefined ? '' : String(value)
  }
  if (!draft.invoiceDate && invoice.invoiceDate) draft.invoiceDate = invoice.invoiceDate
  return draft
}

function problems(draft: Draft): Record<string, string> {
  const out: Record<string, string> = {}
  for (const { key, kind } of EDITABLE) {
    const value = draft[key].trim()
    if (!value) continue
    if (kind === 'money' && (toNumber(value) === null || Number(value) < 0)) out[key] = 'Enter an amount of 0 or more'
    if (kind === 'gstin' && !GSTIN_PATTERN.test(value.toUpperCase())) out[key] = '15 characters, like 36AABCS1429B1Z5'
    if (kind === 'email' && !isEmail(value)) out[key] = 'Not a valid email'
    if (kind === 'date' && (!/^\d{4}-\d{2}-\d{2}$/.test(value) || value > localToday())) out[key] = 'Enter a valid date, not in the future'
  }
  return out
}

export function EditInvoiceDialog({ invoice, onClose, onSaved }: { invoice: InvoiceDetail; onClose: () => void; onSaved: () => Promise<void> }) {
  const toast = useToast()
  const initial = useRef(draftOf(invoice)).current
  const [draft, setDraft] = useState<Draft>(initial)
  const [categories, setCategories] = useState<NamedResource[] | null>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    loadCategories().then(setCategories).catch(() => setCategories([]))
  }, [])

  const errors = problems(draft)
  const changedKeys = Object.keys(draft).filter((k) => draft[k].trim() !== initial[k].trim())
  const dirty = changedKeys.length > 0
  const sum = ['taxableValue', 'cgst', 'sgst', 'igst'].reduce((s, k) => s + (toNumber(draft[k]) ?? 0), 0) - (toNumber(draft.discount) ?? 0)
  const net = toNumber(draft.netAmount)
  const mismatch = net !== null && toNumber(draft.taxableValue) !== null && Math.abs(sum - net) > 1

  async function save() {
    setBusy(true)
    setError(null)
    const editedData: Record<string, string | number | null> = {}
    for (const key of changedKeys) {
      if (key === 'categoryId') continue
      const field = EDITABLE.find((f) => f.key === key)
      const value = draft[key].trim()
      editedData[key] = !value ? null : field?.kind === 'money' ? Number(value) : field?.kind === 'gstin' ? value.toUpperCase() : value
    }
    const body: Record<string, unknown> = {}
    if (Object.keys(editedData).length) body.editedData = editedData
    if (changedKeys.includes('categoryId')) body.categoryId = draft.categoryId || null
    try {
      await api(`/admin/invoices/${invoice.id}`, { method: 'PATCH', body })
      toast('Invoice details updated')
      await onSaved()
      onClose()
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not save changes')
      setBusy(false)
    }
  }

  const set = (key: string) => (e: { target: { value: string } }) => setDraft((d) => ({ ...d, [key]: e.target.value }))
  return (
    <Modal
      title="Correct invoice details"
      subtitle="Your corrections are saved alongside the employee's values and recorded in the history."
      onClose={onClose}
      wide
      busy={busy}
      dirty={dirty}
      footer={
        <>
          <button className="btn" onClick={onClose} disabled={busy}>Cancel</button>
          <button className="btn primary" disabled={!dirty || busy || Object.keys(errors).length > 0} onClick={save}>
            {busy && <Spinner small />} Save changes
          </button>
        </>
      }
    >
      <div className="stack">
        {error && <Alert kind="error">{error}</Alert>}
        {invoice.approvalStatus !== 'pending' && (
          <Alert kind="info">This invoice is already <b>{invoice.approvalStatus}</b>. Editing doesn't change its status.</Alert>
        )}
        <div className="form-grid">
          {EDITABLE.map(({ key, label, kind, full }) => (
            <Field key={key} label={label} full={full} hint={errors[key]}>
              <input
                className={`input ${kind === 'gstin' ? 'mono' : ''}`}
                type={kind === 'date' ? 'date' : kind === 'money' ? 'number' : kind === 'email' ? 'email' : 'text'}
                step={kind === 'money' ? '0.01' : undefined}
                min={kind === 'money' ? 0 : undefined}
                inputMode={kind === 'money' ? 'decimal' : undefined}
                maxLength={kind === 'gstin' ? 15 : undefined}
                value={draft[key]}
                onChange={set(key)}
                aria-invalid={Boolean(errors[key])}
              />
            </Field>
          ))}
          <Field label="Category" full>
            <select className="select" value={draft.categoryId} onChange={set('categoryId')}>
              <option value="">{categories === null ? 'Loading…' : 'No category'}</option>
              {categories?.filter((c) => c.isActive || c.id === draft.categoryId).map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
            </select>
          </Field>
        </div>
        {mismatch && (
          <Alert kind="info">Taxable value + taxes − discount is {money(sum)}, but the invoice value is {money(net)}. Double-check the figures.</Alert>
        )}
      </div>
    </Modal>
  )
}
