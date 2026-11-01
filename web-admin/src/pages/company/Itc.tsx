import { useEffect, useRef, useState } from 'react'
import { Link } from 'react-router-dom'
import { BellRing, CheckCircle2, Download, FileSpreadsheet, Phone, RefreshCw, Scale, Trash2, Upload } from 'lucide-react'
import { api } from '../../api/client'
import type { ItcImport, ItcMatch, Items, Reminder, ReminderResult } from '../../api/types'
import {
  Alert, Badge, Card, Confirm, Empty, ErrorState, Field, Loading, PageHeader, Pagination, Spinner, Stat, useAsync, usePaged, useToast,
} from '../../components/ui'
import { currentPeriod, date, downloadText, money } from '../../lib/format'
import { FollowUpItem, ImportDialog, RemindersDialog, type GstrReturn } from './ItcParts'

const MATCH_FILTERS = [
  ['', 'All'], ['matched', 'Matched'], ['partial', 'Partial'], ['mismatch', 'Mismatch'],
  ['missing_in_2b', 'Missing in GSTR'], ['missing_in_books', 'Missing in books'],
] as const
const MATCHES_PER_PAGE = 100
const POLL_MS = 5000

export default function Itc() {
  const toast = useToast()
  const [period, setPeriod] = useState(currentPeriod())
  const [returnType, setReturnType] = useState<GstrReturn>('2B')
  const [status, setStatus] = useState('')
  const [importing, setImporting] = useState(false)
  const [confirmRemindAll, setConfirmRemindAll] = useState(false)
  const [removingImport, setRemovingImport] = useState<ItcImport | null>(null)
  const [reminders, setReminders] = useState<{ items: ReminderResult[]; skipped?: number } | null>(null)
  const [working, setWorking] = useState<string | null>(null)
  const [matchPage, setMatchPage] = usePaged(`${period}|${returnType}|${status}`)

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
  const refreshRef = useRef(refreshAll)
  refreshRef.current = refreshAll

  const processing = imports.data?.some((i) => i.status === 'processing') ?? false
  const wasProcessing = useRef(false)
  useEffect(() => {
    if (!processing) {
      if (wasProcessing.current) {
        wasProcessing.current = false
        toast('Background import finished')
        refreshRef.current()
      }
      return
    }
    wasProcessing.current = true
    const timer = setInterval(() => void imports.reload(), POLL_MS)
    return () => clearInterval(timer)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [processing])

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
    const res = await api<{ count: number; skipped?: number; items: ReminderResult[] }>('/admin/itc/remind-missing', { method: 'POST', query: { period, returnType } })
    setConfirmRemindAll(false)
    if (!res.count) toast(res.skipped ? `All ${res.skipped} suppliers already have an open reminder` : 'No missing or mismatched invoices need reminders', 'info')
    else setReminders({ items: res.items, skipped: res.skipped })
    void followUps.reload()
  })

  const remindOne = (id: string) => run(`remind-${id}`, async () => {
    const res = await api<ReminderResult>(`/admin/itc/matches/${id}/remind`, { method: 'POST' })
    setReminders({ items: [res] })
    void followUps.reload()
  })

  const updateFollowUp = (id: string, body: Record<string, unknown>, message: string) => run(`fu-${id}`, async () => {
    await api(`/admin/itc/reminders/${id}`, { method: 'PATCH', body })
    toast(message)
    await followUps.reload()
  })

  const removeImport = () => run('removeImport', async () => {
    if (!removingImport) return
    await api(`/admin/itc/imports/${removingImport.id}`, { method: 'DELETE' })
    await api('/admin/itc/reconcile', { method: 'POST', query: { period, returnType } }).catch(() => {})
    toast('Import removed and matches recalculated')
    setRemovingImport(null)
    refreshAll()
  })

  const counts = summary.data ?? {}
  const total = Object.values(counts).reduce((a, b) => a + b, 0)
  const rows = matches.data?.slice((matchPage - 1) * MATCHES_PER_PAGE, matchPage * MATCHES_PER_PAGE) ?? []
  const toChase = (counts.missing_in_2b ?? 0) + (counts.mismatch ?? 0)

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
              <Field label="Return type" group>
                <div className="segmented">
                  {(['2B', '2A'] as const).map((t) => (
                    <button key={t} className={returnType === t ? 'on' : ''} aria-pressed={returnType === t} onClick={() => setReturnType(t)}>GSTR-{t}</button>
                  ))}
                </div>
              </Field>
            </div>
            {info.data && (
              <Alert kind="info">
                {info.data.portalApiConfigured ? 'GST portal API connected.' : 'Upload the GSTR-2A/2B Excel or CSV downloaded from the GST portal.'}
              </Alert>
            )}
          </div>
          {processing && (
            <div style={{ marginTop: 14 }}>
              <Alert kind="info"><span className="row" style={{ gap: 8 }}><Spinner small /> A large file is importing in the background. Results refresh automatically.</span></Alert>
            </div>
          )}
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
              <button className="btn sm warn" onClick={() => setConfirmRemindAll(true)} disabled={!toChase}><BellRing size={14} /> Remind all missing</button>
            </>
          }
        >
          <div className="segmented" role="group" aria-label="Match status" style={{ marginBottom: 14, flexWrap: 'wrap' }}>
            {MATCH_FILTERS.map(([k, label]) => (
              <button key={k} className={status === k ? 'on' : ''} aria-pressed={status === k} onClick={() => setStatus(k)}>
                {label}{k && counts[k] ? <span className="count">{counts[k]}</span> : null}
              </button>
            ))}
          </div>
          {matches.loading && !matches.data ? <Loading /> : matches.error ? <ErrorState message={matches.error} onRetry={matches.reload} /> : !matches.data?.length ? (
            <Empty icon={<Scale size={24} />} title="No match results for this period" message="Import the GSTR file for this period, then results appear here." />
          ) : (
            <>
              <div className="table-wrap">
                <table className="table">
                  <thead><tr><th>Status</th><th>Your books</th><th>GSTR portal</th><th>Difference</th><th className="right">Action</th></tr></thead>
                  <tbody>
                    {rows.map((m) => (
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
              <Pagination page={matchPage} pageSize={MATCHES_PER_PAGE} total={matches.data.length} onPage={setMatchPage} />
            </>
          )}
        </Card>

        <div className="grid cols-2">
          <Card title="Supplier follow-ups" subtitle="Suppliers without phone or email — call them manually.">
            {followUps.loading && !followUps.data ? <Loading /> : followUps.error ? <ErrorState message={followUps.error} onRetry={followUps.reload} /> : !followUps.data?.length ? (
              <Empty icon={<Phone size={24} />} title="No pending follow-ups" />
            ) : (
              followUps.data.map((r) => (
                <FollowUpItem key={r.id} reminder={r} busy={working === `fu-${r.id}`} onUpdate={(body, message) => updateFollowUp(r.id, body, message)} />
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
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div className="row between">
                      <div className="cell-title" style={{ overflow: 'hidden', textOverflow: 'ellipsis' }}>{i.originalFilename || 'GSTR file'}</div>
                      <div className="row" style={{ gap: 6 }}>
                        <Badge status={i.status} />
                        {i.status !== 'processing' && (
                          <button className="btn ghost icon sm" title="Remove this import" aria-label={`Remove import ${i.originalFilename ?? ''}`} onClick={() => setRemovingImport(i)}><Trash2 size={14} /></button>
                        )}
                      </div>
                    </div>
                    <div className="cell-sub">GSTR-{i.returnType} · {i.rowCount.toLocaleString('en-IN')} rows · {date(i.createdAt, true)}</div>
                    {i.errorMessage && <div className="cell-sub" style={{ color: 'var(--danger)' }}>{i.errorMessage}</div>}
                  </div>
                </div>
              ))
            )}
          </Card>
        </div>
      </div>

      {importing && (
        <ImportDialog
          period={period}
          returnType={returnType}
          onClose={() => setImporting(false)}
          onDone={(p, rt) => {
            setImporting(false)
            if (p !== period || rt !== returnType) {
              setPeriod(p)
              setReturnType(rt)
            } else {
              refreshAll()
            }
          }}
        />
      )}
      {confirmRemindAll && (
        <Confirm
          title="Remind all suppliers?"
          message={`Creates a reminder for each of the ${toChase} missing or mismatched invoices in GSTR-${returnType} ${period}. Suppliers that already have an open reminder are skipped.`}
          confirmLabel="Prepare reminders"
          busy={working === 'remindAll'}
          onConfirm={remindAll}
          onClose={() => setConfirmRemindAll(false)}
        />
      )}
      {removingImport && (
        <Confirm
          title="Remove this import?"
          message={`Deletes the ${removingImport.rowCount.toLocaleString('en-IN')} rows from ${removingImport.originalFilename || 'this file'} and recalculates matches for ${period}.`}
          confirmLabel="Remove import"
          danger
          busy={working === 'removeImport'}
          onConfirm={removeImport}
          onClose={() => setRemovingImport(null)}
        />
      )}
      {reminders && <RemindersDialog items={reminders.items} skipped={reminders.skipped} onClose={() => setReminders(null)} />}
    </>
  )
}
