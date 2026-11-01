import { useEffect, useRef, useState } from 'react'
import { Link } from 'react-router-dom'
import { CheckCircle2, FileSpreadsheet, Mail, MessageCircle, Phone, Upload, X } from 'lucide-react'
import { api } from '../../api/client'
import type { Reminder, ReminderResult } from '../../api/types'
import { Alert, Badge, Field, Modal, Spinner, useDebounced, useToast } from '../../components/ui'

export type GstrReturn = '2A' | '2B'

export function ImportDialog({ period, returnType, onClose, onDone }: {
  period: string
  returnType: GstrReturn
  onClose: () => void
  /** Called with the period/return type the file was imported for, so the page can switch to it. */
  onDone: (period: string, returnType: GstrReturn) => void
}) {
  const toast = useToast()
  const fileRef = useRef<HTMLInputElement>(null)
  const [file, setFile] = useState<File | null>(null)
  const [p, setP] = useState(period)
  const [rt, setRt] = useState(returnType)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function upload() {
    if (!file || !p) return
    setBusy(true)
    setError(null)
    const form = new FormData()
    form.append('period', p)
    form.append('returnType', rt)
    form.append('file', file)
    try {
      const res = await api<{ rowCount: number; status?: string }>('/admin/itc/import', { method: 'POST', body: form })
      if (res.status === 'processing') {
        toast(`Large file: ${res.rowCount.toLocaleString('en-IN')} rows are importing in the background. This page updates when it's done.`, 'info')
      } else {
        toast(`Imported ${res.rowCount.toLocaleString('en-IN')} rows and reconciled`)
      }
      onDone(p, rt)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Import failed')
      setBusy(false)
    }
  }

  return (
    <Modal
      title="Import GSTR file"
      subtitle="Excel (.xlsx) or CSV exported from the GST portal. Re-importing the same period and return type replaces the earlier rows."
      onClose={onClose}
      busy={busy}
      dirty={Boolean(file)}
      footer={
        <>
          <button className="btn" onClick={onClose} disabled={busy}>Cancel</button>
          <button className="btn primary" disabled={!file || !p || busy} onClick={upload}>{busy ? <Spinner small /> : <Upload size={16} />} Import</button>
        </>
      }
    >
      <div className="stack">
        {error && <Alert kind="error">{error}</Alert>}
        <div className="form-grid">
          <Field label="Period"><input className="input" type="month" value={p} onChange={(e) => setP(e.target.value)} /></Field>
          <Field label="Return type">
            <select className="select" value={rt} onChange={(e) => setRt(e.target.value as GstrReturn)}>
              <option value="2B">GSTR-2B</option>
              <option value="2A">GSTR-2A</option>
            </select>
          </Field>
        </div>
        <input ref={fileRef} type="file" accept=".xlsx,.xls,.csv" hidden onChange={(e) => setFile(e.target.files?.[0] ?? null)} />
        <button
          type="button"
          className="glass"
          onClick={() => fileRef.current?.click()}
          style={{ padding: 28, textAlign: 'center', cursor: 'pointer', borderStyle: 'dashed', color: 'inherit' }}
        >
          <FileSpreadsheet size={28} style={{ color: 'var(--primary)' }} />
          <div className="cell-title" style={{ marginTop: 8 }}>{file ? file.name : 'Choose a file'}</div>
          <div className="faint">{file ? `${(file.size / 1024).toFixed(1)} KB` : '.xlsx, .xls or .csv, up to 25 MB'}</div>
        </button>
      </div>
    </Modal>
  )
}

export function RemindersDialog({ items, skipped, onClose }: { items: ReminderResult[]; skipped?: number; onClose: () => void }) {
  return (
    <Modal
      title={items.length === 1 ? 'Supplier reminder ready' : `${items.length} supplier reminders ready`}
      subtitle="Open WhatsApp or email to send. Suppliers without contact details were added to follow-ups."
      onClose={onClose}
      wide
      footer={<button className="btn primary" onClick={onClose}>Done</button>}
    >
      <div className="stack">
        {skipped ? <Alert kind="info">{skipped} supplier{skipped === 1 ? ' already has' : 's already have'} an open reminder and {skipped === 1 ? 'was' : 'were'} skipped.</Alert> : null}
        {items.map((r) => (
          <div key={r.id} className="glass card" style={{ padding: 16 }}>
            {(r.contactPhone || r.contactEmail) && (
              <div className="faint" style={{ fontSize: 12.5, marginBottom: 6 }}>{[r.contactPhone, r.contactEmail].filter(Boolean).join(' · ')}</div>
            )}
            <div className="muted" style={{ whiteSpace: 'pre-wrap', fontSize: 13 }}>{r.message}</div>
            <div className="row wrap" style={{ marginTop: 12 }}>
              {r.whatsappUrl && <a className="btn sm success" href={r.whatsappUrl} target="_blank" rel="noreferrer"><MessageCircle size={14} /> WhatsApp</a>}
              {r.mailtoUrl && <a className="btn sm" href={r.mailtoUrl}><Mail size={14} /> Email</a>}
              {!r.whatsappUrl && !r.mailtoUrl && <Badge status="manual_followup" label="Manual follow-up" />}
              {r.invoiceId && <Link className="btn sm ghost" to={`/invoices/${r.invoiceId}`}>Invoice</Link>}
            </div>
          </div>
        ))}
      </div>
    </Modal>
  )
}

export function FollowUpItem({ reminder, busy, onUpdate }: {
  reminder: Reminder
  busy: boolean
  onUpdate: (body: Record<string, unknown>, message: string) => Promise<void>
}) {
  const saved = reminder.promisedBy ?? ''
  const [promised, setPromised] = useState(saved)
  const pending = useDebounced(promised, 800)
  const onUpdateRef = useRef(onUpdate)
  onUpdateRef.current = onUpdate

  useEffect(() => setPromised(saved), [saved])
  useEffect(() => {
    if (pending === saved || (pending && !/^\d{4}-\d{2}-\d{2}$/.test(pending))) return
    void onUpdateRef.current({ promisedBy: pending || null }, pending ? 'Promise date saved' : 'Promise date cleared')
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [pending])

  return (
    <div className="list-item">
      <div className="dot-icon"><Phone size={16} /></div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div className="muted" style={{ fontSize: 13 }}>{reminder.messagePreview}</div>
        <div className="row wrap" style={{ marginTop: 8 }}>
          <button
            className={`btn sm ${reminder.called ? 'success' : ''}`}
            disabled={busy}
            onClick={() => onUpdate({ called: !reminder.called }, reminder.called ? 'Marked as not called' : 'Marked as called')}
          >
            {reminder.called ? <CheckCircle2 size={14} /> : <Phone size={14} />} {reminder.called ? 'Called' : 'Mark called'}
          </button>
          <span className="inline-group">
            <input
              className="input" type="date" style={{ width: 160, height: 32 }}
              value={promised}
              onChange={(e) => setPromised(e.target.value)}
              aria-label="Supplier promised to file by"
              title="Supplier promised to file by"
            />
            {promised && (
              <button className="btn ghost icon sm" aria-label="Clear promise date" title="Clear promise date" onClick={() => setPromised('')}><X size={14} /></button>
            )}
          </span>
          <button className="btn sm success" disabled={busy} onClick={() => onUpdate({ resolved: true }, 'Follow-up resolved')}>Resolve</button>
          <Link className="btn sm ghost" to={`/invoices/${reminder.invoiceId}`}>Invoice</Link>
        </div>
      </div>
    </div>
  )
}
