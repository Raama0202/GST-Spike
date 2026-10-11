import { useState } from 'react'
import { Link, useNavigate, useParams } from 'react-router-dom'
import { ArrowLeft, Check, CornerUpLeft, ExternalLink, FileImage, MapPin, X } from 'lucide-react'
import { api, mediaUrl } from '../../api/client'
import type { InvoiceDetail as Detail, InvoiceFields } from '../../api/types'
import { Alert, Badge, Card, ErrorState, Field, Loading, Modal, PageHeader, Spinner, useAsync, useToast } from '../../components/ui'
import { date, money } from '../../lib/format'

const FIELDS: { key: keyof InvoiceFields; label: string; kind?: 'money' | 'date' }[] = [
  { key: 'vendorName', label: 'Vendor' },
  { key: 'gstin', label: 'GSTIN' },
  { key: 'invoiceNumber', label: 'Invoice number' },
  { key: 'invoiceDate', label: 'Invoice date', kind: 'date' },
  { key: 'expenseCategoryName', label: 'Category' },
  { key: 'taxableValue', label: 'Taxable value', kind: 'money' },
  { key: 'cgst', label: 'CGST', kind: 'money' },
  { key: 'sgst', label: 'SGST', kind: 'money' },
  { key: 'igst', label: 'IGST', kind: 'money' },
  { key: 'discount', label: 'Discount', kind: 'money' },
  { key: 'netAmount', label: 'Net amount', kind: 'money' },
  { key: 'supplierPhone', label: 'Supplier phone' },
  { key: 'supplierEmail', label: 'Supplier email' },
  { key: 'remarks', label: 'Employee remarks' },
]

type Decision = 'approve' | 'reject' | 'return'

function show(value: unknown, kind?: 'money' | 'date') {
  if (value === null || value === undefined || value === '') return '—'
  if (kind === 'money') return money(value)
  if (kind === 'date') return date(String(value))
  return String(value)
}

export default function InvoiceDetail() {
  const { id } = useParams()
  const navigate = useNavigate()
  const { data, error, loading, reload, setData } = useAsync(() => api<Detail>(`/admin/invoices/${id}`), [id])
  const [decision, setDecision] = useState<Decision | null>(null)
  const [imageFailed, setImageFailed] = useState(false)

  if (loading && !data) return <><PageHeader title="Invoice" /><Card><Loading /></Card></>
  if (error || !data) return <><PageHeader title="Invoice" /><Card><ErrorState message={error ?? ''} onRetry={reload} /></Card></>

  const edited = data.editedData ?? {}
  const ocr = data.ocrData ?? {}
  const image = mediaUrl(data.imageUrl ?? data.originalImageUrl)
  const original = mediaUrl(data.originalImageUrl)
  const hasLocation = data.latitude !== null && data.longitude !== null

  return (
    <>
      <PageHeader
        title={data.vendorName || String(edited.vendorName ?? 'Invoice')}
        subtitle={`Invoice ${data.invoiceNumber || '—'} · uploaded ${date(data.uploadedAt, true)}`}
        actions={
          <>
            <button className="btn" onClick={() => (window.history.length > 1 ? navigate(-1) : navigate('/invoices'))}><ArrowLeft size={16} /> Back</button>
            <button className="btn success" onClick={() => setDecision('approve')} disabled={data.approvalStatus === 'approved'}><Check size={16} /> Approve</button>
            <button className="btn warn" onClick={() => setDecision('return')}><CornerUpLeft size={16} /> Return</button>
            <button className="btn danger" onClick={() => setDecision('reject')} disabled={data.approvalStatus === 'rejected'}><X size={16} /> Reject</button>
          </>
        }
      />
      <div className="invoice-layout">
        <Card
          title="Bill image"
          actions={original && <a className="btn sm" href={original} target="_blank" rel="noreferrer"><ExternalLink size={14} /> Open original</a>}
        >
          <div className="image-frame">
            {image && !imageFailed ? (
              <img src={image} alt="Invoice" onError={() => setImageFailed(true)} />
            ) : (
              <div className="empty">
                <div className="empty-icon"><FileImage size={24} /></div>
                <h4>Image unavailable</h4>
                <div>The image file is no longer on the server (free hosting clears uploads on restart).</div>
              </div>
            )}
          </div>
        </Card>

        <div className="stack">
          <Card title="Review status">
            <div className="row between">
              <Badge status={data.approvalStatus} />
              <span className="stat-value" style={{ marginTop: 0, fontSize: 24 }}>{money(data.netAmount ?? edited.netAmount)}</span>
            </div>
            {data.adminRemarks && <div style={{ marginTop: 14 }}><Alert>Admin remarks: {data.adminRemarks}</Alert></div>}
          </Card>
          <Card title="Extracted details" subtitle="Values confirmed by the employee. Fields changed from the scan are marked.">
            <dl className="kv">
              {FIELDS.map(({ key, label, kind }) => {
                const value = edited[key] ?? ocr[key]
                const changed = ocr[key] !== undefined && edited[key] !== undefined && String(ocr[key] ?? '') !== String(edited[key] ?? '')
                return (
                  <div key={key} style={{ display: 'contents' }}>
                    <dt>{label}</dt>
                    <dd className={key === 'gstin' || key === 'invoiceNumber' ? 'mono' : ''}>
                      {show(value, kind)}
                      {changed && <span className="changed" title={`Scanned: ${show(ocr[key], kind)}`}>edited</span>}
                    </dd>
                  </div>
                )
              })}
            </dl>
          </Card>
          <Card title="Capture metadata">
            <dl className="kv">
              <dt>Device</dt><dd className="mono">{data.deviceId || '—'}</dd>
              <dt>Location</dt>
              <dd>
                {hasLocation ? (
                  <a href={`https://www.google.com/maps?q=${data.latitude},${data.longitude}`} target="_blank" rel="noreferrer" className="row" style={{ gap: 6 }}>
                    <MapPin size={14} /> {Number(data.latitude).toFixed(5)}, {Number(data.longitude).toFixed(5)}
                  </a>
                ) : 'Not captured'}
              </dd>
              <dt>Reference</dt><dd className="mono">{data.localIdempotencyKey}</dd>
            </dl>
          </Card>
          <Link to="/invoices" className="faint" style={{ fontSize: 12.5 }}>← All invoices</Link>
        </div>
      </div>

      {decision && (
        <DecisionDialog
          id={data.id}
          decision={decision}
          onClose={() => setDecision(null)}
          onDone={(updated) => setData({ ...data, ...updated })}
        />
      )}
    </>
  )
}

function DecisionDialog({ id, decision, onClose, onDone }: {
  id: string
  decision: Decision
  onClose: () => void
  onDone: (updated: Partial<Detail>) => void
}) {
  const toast = useToast()
  const [remarks, setRemarks] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const required = decision !== 'approve'
  const copy = {
    approve: { title: 'Approve invoice', button: 'Approve', cls: 'success', toast: 'Invoice approved — employee notified' },
    reject: { title: 'Reject invoice', button: 'Reject', cls: 'danger', toast: 'Invoice rejected — employee notified' },
    return: { title: 'Return for correction', button: 'Return', cls: 'warn', toast: 'Invoice returned — employee notified' },
  }[decision]

  async function submit() {
    setBusy(true)
    setError(null)
    try {
      const updated = await api<Partial<Detail>>(`/admin/invoices/${id}/${decision}`, { method: 'POST', body: { remarks: remarks.trim() || null } })
      toast(copy.toast)
      onDone(updated)
      onClose()
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Action failed')
    } finally {
      setBusy(false)
    }
  }

  return (
    <Modal
      title={copy.title}
      subtitle="The employee sees this decision and your remarks in their app."
      onClose={onClose}
      footer={
        <>
          <button className="btn" onClick={onClose}>Cancel</button>
          <button className={`btn ${copy.cls}`} disabled={busy || (required && !remarks.trim())} onClick={submit}>
            {busy && <Spinner small />} {copy.button}
          </button>
        </>
      }
    >
      <div className="stack">
        {error && <Alert kind="error">{error}</Alert>}
        <Field label="Remarks" hint={required ? 'required' : 'optional'}>
          <textarea
            className="textarea"
            value={remarks}
            onChange={(e) => setRemarks(e.target.value)}
            placeholder={decision === 'return' ? 'e.g. GSTIN is unreadable, please rescan' : 'Add a note for the employee'}
            autoFocus
          />
        </Field>
      </div>
    </Modal>
  )
}
