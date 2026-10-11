import { useRef, useState } from 'react'
import { Link } from 'react-router-dom'
import { BellRing, CheckCircle2, Download, FileSpreadsheet, Mail, MessageCircle, Phone, RefreshCw, Scale, Upload } from 'lucide-react'
import { api } from '../../api/client'
import type { ItcImport, ItcMatch, Items, Reminder, ReminderResult } from '../../api/types'
import { Alert, Badge, Card, Empty, ErrorState, Field, Loading, Modal, PageHeader, Spinner, Stat, useAsync, useToast } from '../../components/ui'
import { currentPeriod, date, downloadText, money } from '../../lib/format'

const MATCH_FILTERS = [
  ['', 'All'], ['matched', 'Matched'], ['partial', 'Partial'], ['mismatch', 'Mismatch'],
  ['missing_in_2b', 'Missing in GSTR'], ['missing_in_books', 'Missing in books'],
] as const

export default function Itc() {
  const toast = useToast()
  const [period, setPeriod] = useState(currentPeriod())
  const [returnType, setReturnType] = useState<'2A' | '2B'>('2B')
  const [status, setStatus] = useState('')
  const [importing, setImporting] = useState(false)
  const [reminders, setReminders] = useState<ReminderResult[] | null>(null)
  const [working, setWorking] = useState<string | null>(null)

  const info = useAsync(() => api<{ portalApiConfigured: boolean }>('/admin/itc/status'))
  const summary = useAsync(
    () => api<{ counts: Record<string, number> }>('/admin/itc/summary', { query: { period, returnType } }).then((r) => r.counts),
    [period, returnType],
  )
  const matches = useAsync(
    () => api<Items<ItcMatch>>('/admin/itc/matches', { query: { period, returnType, status: status || undefined } }).then((r) => r.items),
    [period, returnType, status],
  )
  const imports = useAsync(() => api<Items<ItcImport>>('/admin/itc/imports', { query: { period } }).then((r) => r.items), [period])
  const followUps = useAsync(() => api<Items<Reminder>>('/admin/itc/reminders', { query: { status: 'manual_followup' } }).then((r) => r.items))

  const refreshAll = () => { void summary.reload(); void matches.reload(); void imports.reload(); void followUps.reload() }

  async function run(key: string, fn: () => Promise<void>) {
    setWorking(key)
    try { await fn() } catch (e) { toast(e instanceof Error ? e.message : 'Action failed', 'error') } finally { setWorking(null) }
  }

  const reconcile = () => run('reconcile', async () => {
    await api('/admin/itc/reconcile', { method: 'POST', query: { period, returnType } })
    toast('Reconciliation re-run')
    refreshAll()
  })

  const exportCsv = () => run('export', async () => {
    const res = await api<{ csv: string; filename: string }>('/admin/itc/matches/export', { query: { period, returnType, status: status || 'all' } })
    downloadText(res.filename, res.csv)
  })

  const remindAll = () => run('remindAll', async () => {
    const res = await api<{ count: number; items: ReminderResult[] }>('/admin/itc/remind-missing', { method: 'POST', query: { period, returnType } })
    if (!res.count) toast('No missing or mismatched invoices need reminders', 'info')
    else setReminders(res.items)
    void followUps.reload()
  })

  const remindOne = (id: string) => run(`remind-${id}`, async () => {
    const res = await api<ReminderResult>(`/admin/itc/matches/${id}/remind`, { method: 'POST' })
    setReminders([res])
    void followUps.reload()
  })

  const updateFollowUp = (id: string, body: Record<string, unknown>, message: string) => run(`fu-${id}`, async () => {
    await api(`/admin/itc/reminders/${id}`, { method: 'PATCH', body })
    toast(message)
    await followUps.reload()
  })

  const counts = summary.data ?? {}
  const total = Object.values(counts).reduce((a, b) => a + b, 0)

  return (
    <>
      <PageHeader
        title="ITC reconciliation"
        subtitle="Match approved bills against GSTR-2A/2B and follow up with suppliers who haven't filed."
        actions={
          <>
            <button className="btn" onClick={reconcile} disabled={working === 'reconcile'}>{working === 'reconcile' ? <Spinner small /> : <RefreshCw size={16} />} Re-run match</button>
            <button className="btn primary" onClick={() => setImporting(true)}><Upload size={16} /> Import GSTR file</button>
          </>
        }
      />
      <div className="stack">
        <Card>
          <div className="row wrap between">
            <div className="row wrap">
              <Field label="Return period">
                <input className="input" type="month" value={period} onChange={(e) => e.target.value && setPeriod(e.target.value)} style={{ width: 190 }} />
              </Field>
              <Field label="Return type">
                <div className="segmented">
                  {(['2B', '2A'] as const).map((t) => <button key={t} className={returnType === t ? 'on' : ''} onClick={() => setReturnType(t)}>GSTR-{t}</button>)}
                </div>
              </Field>
            </div>
            {info.data && (
              <Alert kind="info">
                {info.data.portalApiConfigured ? 'GST portal API connected.' : 'Upload the GSTR-2A/2B Excel or CSV downloaded from the GST portal.'}
              </Alert>
            )}
          </div>
        </Card>

        <div className="grid cols-4">
          <Stat icon={<Scale size={20} />} label="Rows compared" value={summary.loading ? '…' : total} tone="#7c9cff" />
          <Stat icon={<CheckCircle2 size={20} />} label="Matched" value={summary.loading ? '…' : (counts.matched ?? 0) + (counts.partial ?? 0)} tone="#34d399" />
          <Stat icon={<BellRing size={20} />} label="Missing in GSTR (chase supplier)" value={summary.loading ? '…' : counts.missing_in_2b ?? 0} tone="#f87171" />
          <Stat icon={<FileSpreadsheet size={20} />} label="Mismatch / not in books" value={summary.loading ? '…' : (counts.mismatch ?? 0) + (counts.missing_in_books ?? 0)} tone="#fbbf24" />
        </div>

        <Card
          title="Match results"
          subtitle={`GSTR-${returnType} · ${period}`}
          actions={
            <>
              <button className="btn sm" onClick={exportCsv} disabled={working === 'export'}>{working === 'export' ? <Spinner small /> : <Download size={14} />} Export CSV</button>
              <button className="btn sm warn" onClick={remindAll} disabled={working === 'remindAll'}>{working === 'remindAll' ? <Spinner small /> : <BellRing size={14} />} Remind all missing</button>
            </>
          }
        >
          <div className="segmented" style={{ marginBottom: 14, flexWrap: 'wrap' }}>
            {MATCH_FILTERS.map(([k, label]) => (
              <button key={k} className={status === k ? 'on' : ''} onClick={() => setStatus(k)}>
                {label}{k && counts[k] ? <span className="count">{counts[k]}</span> : null}
              </button>
            ))}
          </div>
          {matches.loading && !matches.data ? <Loading /> : matches.error ? <ErrorState message={matches.error} onRetry={matches.reload} /> : !matches.data?.length ? (
            <Empty icon={<Scale size={24} />} title="No match results for this period" message="Import the GSTR file for this period, then results appear here." />
          ) : (
            <div className="table-wrap">
              <table className="table">
                <thead><tr><th>Status</th><th>Your books</th><th>GSTR portal</th><th>Difference</th><th className="right">Action</th></tr></thead>
                <tbody>
                  {matches.data.map((m) => (
                    <tr key={m.id}>
                      <td><Badge status={m.status} /></td>
                      <td>
                        {m.invoice ? (
                          <Link to={`/invoices/${m.invoice.id}`}>
                            <div className="cell-title" style={{ color: 'var(--text)' }}>{m.invoice.vendorName || 'Unknown vendor'}</div>
                            <div className="cell-sub mono">{m.invoice.invoiceNumber} · {money(m.invoice.netAmount)}</div>
                          </Link>
                        ) : <span className="faint">Not in books</span>}
                      </td>
                      <td>
                        {m.portalRow ? (
                          <>
                            <div className="cell-title">{m.portalRow.supplierName || m.portalRow.supplierGstin}</div>
                            <div className="cell-sub mono">{m.portalRow.invoiceNumber} · {money(m.portalRow.netAmount)}</div>
                          </>
                        ) : <span className="faint">Not filed by supplier</span>}
                      </td>
                      <td className="nowrap">{m.amountDelta ? money(m.amountDelta) : '—'}{m.notes && <div className="cell-sub">{m.notes}</div>}</td>
                      <td className="right">
                        {m.invoice && (m.status === 'missing_in_2b' || m.status === 'mismatch') && (
                          <button className="btn sm" onClick={() => remindOne(m.id)} disabled={working === `remind-${m.id}`}>
                            {working === `remind-${m.id}` ? <Spinner small /> : <BellRing size={14} />} Remind
                          </button>
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </Card>

        <div className="grid cols-2">
          <Card title="Supplier follow-ups" subtitle="Suppliers without phone or email — call them manually.">
            {followUps.loading && !followUps.data ? <Loading /> : followUps.error ? <ErrorState message={followUps.error} onRetry={followUps.reload} /> : !followUps.data?.length ? (
              <Empty icon={<Phone size={24} />} title="No pending follow-ups" />
            ) : (
              followUps.data.map((r) => (
                <div key={r.id} className="list-item">
                  <div className="dot-icon"><Phone size={16} /></div>
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div className="muted" style={{ fontSize: 13 }}>{r.messagePreview}</div>
                    <div className="row wrap" style={{ marginTop: 8 }}>
                      <button className={`btn sm ${r.called ? 'success' : ''}`} onClick={() => updateFollowUp(r.id, { called: !r.called }, r.called ? 'Marked as not called' : 'Marked as called')}>
                        {r.called ? <CheckCircle2 size={14} /> : <Phone size={14} />} {r.called ? 'Called' : 'Mark called'}
                      </button>
                      <input
                        className="input" type="date" style={{ width: 160, height: 32 }}
                        value={r.promisedBy ?? ''}
                        onChange={(e) => e.target.value && updateFollowUp(r.id, { promisedBy: e.target.value }, 'Promise date saved')}
                        aria-label="Supplier promised filing by"
                        title="Supplier promised to file by"
                      />
                      <button className="btn sm success" onClick={() => updateFollowUp(r.id, { resolved: true }, 'Follow-up resolved')}>Resolve</button>
                      <Link className="btn sm ghost" to={`/invoices/${r.invoiceId}`}>Invoice</Link>
                    </div>
                  </div>
                </div>
              ))
            )}
          </Card>
          <Card title="Import history" subtitle={`Files imported for ${period}`}>
            {imports.loading && !imports.data ? <Loading /> : imports.error ? <ErrorState message={imports.error} onRetry={imports.reload} /> : !imports.data?.length ? (
              <Empty icon={<FileSpreadsheet size={24} />} title="No imports for this period" action={<button className="btn sm" onClick={() => setImporting(true)}><Upload size={14} /> Import now</button>} />
            ) : (
              imports.data.map((i) => (
                <div key={i.id} className="list-item">
                  <div className="dot-icon"><FileSpreadsheet size={16} /></div>
                  <div style={{ flex: 1 }}>
                    <div className="row between">
                      <div className="cell-title">{i.originalFilename || 'GSTR file'}</div>
                      <Badge status={i.status} />
                    </div>
                    <div className="cell-sub">GSTR-{i.returnType} · {i.rowCount} rows · {date(i.createdAt, true)}</div>
                    {i.errorMessage && <div className="cell-sub" style={{ color: 'var(--danger)' }}>{i.errorMessage}</div>}
                  </div>
                </div>
              ))
            )}
          </Card>
        </div>
      </div>

      {importing && (
        <ImportDialog period={period} returnType={returnType} onClose={() => setImporting(false)} onDone={() => { setImporting(false); refreshAll() }} />
      )}
      {reminders && <RemindersDialog items={reminders} onClose={() => setReminders(null)} />}
    </>
  )
}

function ImportDialog({ period, returnType, onClose, onDone }: { period: string; returnType: '2A' | '2B'; onClose: () => void; onDone: () => void }) {
  const toast = useToast()
  const fileRef = useRef<HTMLInputElement>(null)
  const [file, setFile] = useState<File | null>(null)
  const [p, setP] = useState(period)
  const [rt, setRt] = useState(returnType)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function upload() {
    if (!file) return
    setBusy(true)
    setError(null)
    const form = new FormData()
    form.append('period', p)
    form.append('returnType', rt)
    form.append('file', file)
    try {
      const res = await api<{ rowCount: number; status?: string; matchCounts: Record<string, number> | null }>('/admin/itc/import', { method: 'POST', body: form })
      if (res.status === 'processing') {
        toast(`Large file: ${res.rowCount.toLocaleString('en-IN')} rows are being imported in the background. Refresh in a minute.`, 'info')
      } else {
        toast(`Imported ${res.rowCount.toLocaleString('en-IN')} rows and reconciled`)
      }
      onDone()
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Import failed')
    } finally {
      setBusy(false)
    }
  }

  return (
    <Modal
      title="Import GSTR file"
      subtitle="Excel (.xlsx) or CSV exported from the GST portal. Matching runs automatically."
      onClose={onClose}
      footer={
        <>
          <button className="btn" onClick={onClose}>Cancel</button>
          <button className="btn primary" disabled={!file || busy} onClick={upload}>{busy ? <Spinner small /> : <Upload size={16} />} Import</button>
        </>
      }
    >
      <div className="stack">
        {error && <Alert kind="error">{error}</Alert>}
        <div className="form-grid">
          <Field label="Period"><input className="input" type="month" value={p} onChange={(e) => setP(e.target.value)} /></Field>
          <Field label="Return type">
            <select className="select" value={rt} onChange={(e) => setRt(e.target.value as '2A' | '2B')}>
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
          <div className="faint">{file ? `${(file.size / 1024).toFixed(1)} KB` : '.xlsx, .xls or .csv'}</div>
        </button>
      </div>
    </Modal>
  )
}

function RemindersDialog({ items, onClose }: { items: ReminderResult[]; onClose: () => void }) {
  return (
    <Modal
      title={items.length === 1 ? 'Supplier reminder ready' : `${items.length} supplier reminders ready`}
      subtitle="Open WhatsApp or email to send. Suppliers without contact details were added to follow-ups."
      onClose={onClose}
      wide
      footer={<button className="btn primary" onClick={onClose}>Done</button>}
    >
      <div className="stack">
        {items.map((r) => (
          <div key={r.id} className="glass card" style={{ padding: 16 }}>
            <div className="muted" style={{ whiteSpace: 'pre-wrap', fontSize: 13 }}>{r.message}</div>
            <div className="row wrap" style={{ marginTop: 12 }}>
              {r.whatsappUrl && <a className="btn sm success" href={r.whatsappUrl} target="_blank" rel="noreferrer"><MessageCircle size={14} /> WhatsApp</a>}
              {r.mailtoUrl && <a className="btn sm" href={r.mailtoUrl}><Mail size={14} /> Email</a>}
              {!r.whatsappUrl && !r.mailtoUrl && <Badge status="manual_followup" label="Manual follow-up" />}
            </div>
          </div>
        ))}
      </div>
    </Modal>
  )
}
