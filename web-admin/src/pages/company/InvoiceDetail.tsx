import { useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import { AlertTriangle, ArrowLeft, Check, ChevronLeft, ChevronRight, CornerUpLeft, MapPin, Pencil, X } from 'lucide-react'
import { api } from '../../api/client'
import type { InvoiceDetail as Detail, InvoiceFields } from '../../api/types'
import { Alert, Badge, Card, ErrorState, Loading, PageHeader, Spinner, useAsync, useToast } from '../../components/ui'
import { date, money } from '../../lib/format'
import { DecisionDialog, useInvoiceNav, vendorOf, type Decision } from './InvoiceParts'
import { BillImage, EditInvoiceDialog, GstinPortalCard, HistoryTimeline } from './InvoiceDetailParts'

const FIELDS: { key: keyof InvoiceFields; label: string; kind?: 'money' | 'date' }[] = [
  { key: 'vendorName', label: 'Vendor' },
  { key: 'gstin', label: 'GSTIN' },
  { key: 'invoiceNumber', label: 'Invoice number' },
  { key: 'invoiceDate', label: 'Invoice date', kind: 'date' },
  { key: 'taxableValue', label: 'Taxable value', kind: 'money' },
  { key: 'cgst', label: 'CGST', kind: 'money' },
  { key: 'sgst', label: 'SGST', kind: 'money' },
  { key: 'igst', label: 'IGST', kind: 'money' },
  { key: 'discount', label: 'Discount', kind: 'money' },
  { key: 'netAmount', label: 'Invoice value', kind: 'money' },
  { key: 'supplierPhone', label: 'Supplier phone' },
  { key: 'supplierEmail', label: 'Supplier email' },
  { key: 'remarks', label: 'Employee remarks' },
]

const DECISION_TOAST: Record<Decision, string> = {
  approve: 'Invoice approved — employee notified',
  reject: 'Invoice rejected — employee notified',
  return: 'Invoice returned — employee notified',
}

function show(value: unknown, kind?: 'money' | 'date') {
  if (value === null || value === undefined || value === '') return '—'
  if (kind === 'money') return money(value)
  if (kind === 'date') return date(String(value))
  return String(value)
}

export default function InvoiceDetail() {
  const { id } = useParams()
  const toast = useToast()
  const { data, error, loading, reload } = useAsync(() => api<Detail>(`/admin/invoices/${id}`), [id])
  const nav = useInvoiceNav(id)
  const [decision, setDecision] = useState<Decision | null>(null)
  const [editing, setEditing] = useState(false)

  const back = <Link className="btn" to={nav.listPath}><ArrowLeft size={16} /> Back to list</Link>
  if (loading && (!data || data.id !== id)) return <><PageHeader title="Invoice" actions={back} /><Card><Loading /></Card></>
  if (error || !data) return <><PageHeader title="Invoice" actions={back} /><Card><ErrorState message={error ?? ''} onRetry={reload} /></Card></>

  const edited = data.editedData ?? {}
  const ocr = data.ocrData ?? {}
  const hasLocation = data.latitude !== null && data.longitude !== null && data.latitude !== undefined
  const status = data.approvalStatus

  async function decide(kind: Decision, remarks: string | null) {
    await api(`/admin/invoices/${data!.id}/${kind}`, { method: 'POST', body: { remarks } })
    toast(DECISION_TOAST[kind])
    await reload()
  }

  return (
    <>
      <PageHeader
        title={vendorOf(data)}
        subtitle={`Invoice ${data.invoiceNumber || '—'} · uploaded ${date(data.uploadedAt, true)}`}
        actions={
          <>
            {back}
            <button className="btn success" onClick={() => setDecision('approve')} disabled={status === 'approved'}><Check size={16} /> Approve</button>
            <button className="btn warn" onClick={() => setDecision('return')} disabled={status === 'returned'}><CornerUpLeft size={16} /> Return</button>
            <button className="btn danger" onClick={() => setDecision('reject')} disabled={status === 'rejected'}><X size={16} /> Reject</button>
          </>
        }
      />
      {nav.position !== null && (
        <div className="row between wrap" style={{ marginTop: -12, marginBottom: 18 }}>
          <span className="faint">Invoice {nav.position.toLocaleString('en-IN')} of {(nav.total ?? 0).toLocaleString('en-IN')} in your list</span>
          <div className="actions">
            {nav.moving && <Spinner small />}
            <button className="btn sm" disabled={!nav.hasPrev || nav.moving} onClick={() => nav.go(-1)}><ChevronLeft size={14} /> Previous</button>
            <button className="btn sm" disabled={!nav.hasNext || nav.moving} onClick={() => nav.go(1)}>Next <ChevronRight size={14} /></button>
          </div>
        </div>
      )}
      <div className="invoice-layout">
        <Card title="Bill image">
          <BillImage key={data.id} invoice={data} onExpired={reload} />
        </Card>

        <div className="stack">
          <Card title="Review status">
            <div className="row between">
              <Badge status={status} />
              <span className="stat-value" style={{ marginTop: 0, fontSize: 24 }}>{money(data.netAmount ?? edited.netAmount)}</span>
            </div>
            {data.adminRemarks && <div style={{ marginTop: 14 }}><Alert>Admin remarks: {data.adminRemarks}</Alert></div>}
            {data.vendorIsCompany && (
              <div className="row" style={{ marginTop: 14, color: 'var(--warning)', fontSize: 13, alignItems: 'flex-start' }}>
                <AlertTriangle size={15} style={{ flexShrink: 0, marginTop: 2 }} />
                The scanned vendor matches your own firm. Check that the supplier's name and GSTIN were read correctly.
              </div>
            )}
            {data.reviewedAt && <div className="faint" style={{ fontSize: 12.5, marginTop: 10 }}>Last decision {date(data.reviewedAt, true)}</div>}
          </Card>
          <Card title="Submitted by">
            <dl className="kv">
              <dt>Employee</dt>
              <dd>
                {data.employeeId
                  ? <Link to={`/invoices?employeeId=${data.employeeId}&employeeName=${encodeURIComponent(data.employeeName ?? '')}`}>{data.employeeName || 'Employee'}</Link>
                  : data.employeeName || '—'}
                {data.employeeCode && <span className="faint mono"> · {data.employeeCode}</span>}
              </dd>
              <dt>Branch</dt><dd>{data.branchName || '—'}</dd>
              <dt>Category</dt><dd>{data.categoryName || String(edited.expenseCategoryName ?? '') || '—'}</dd>
            </dl>
          </Card>
          <Card
            title="Extracted details"
            subtitle="Values confirmed by the employee. Fields changed from the scan are marked."
            actions={<button className="btn sm" onClick={() => setEditing(true)}><Pencil size={14} /> Correct</button>}
          >
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
          <GstinPortalCard invoice={data} onChecked={reload} />
          <Card title="History">
            <HistoryTimeline entries={data.history ?? []} />
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
        </div>
      </div>

      {decision && (
        <DecisionDialog
          decision={decision}
          currentStatus={status}
          onSubmit={(remarks) => decide(decision, remarks)}
          onClose={() => setDecision(null)}
        />
      )}
      {editing && <EditInvoiceDialog invoice={data} onClose={() => setEditing(false)} onSaved={reload} />}
    </>
  )
}