import { useState } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import { CreditCard, Download, FileText, Search } from 'lucide-react'
import { api } from '../../api/client'
import type { PaymentsPage } from '../../api/types'
import { AsyncPicker } from '../../components/Picker'
import { Alert, Badge, Card, Empty, ErrorState, Loading, PageHeader, Pagination, Spinner, useAsync, useDebounced, usePaged, useToast } from '../../components/ui'
import { date, downloadText, money, PAYMENT_LABELS, todayStamp, toCsv, toNumber } from '../../lib/format'
import { searchCompanies } from '../../lib/lookups'

const PAGE_SIZE = 50
const EXPORT_PAGE = 200
const EXPORT_CAP = 10000
const FILTERS = [['', 'All'], ['paid', 'Paid'], ['authorized', 'Authorized'], ['created', 'Pending'], ['failed', 'Failed'], ['refunded', 'Refunded']] as const

export default function Payments() {
  const toast = useToast()
  const [params, setParams] = useSearchParams()
  const status = params.get('status') ?? ''
  const companyId = params.get('companyId') ?? ''
  const dateFrom = params.get('dateFrom') ?? ''
  const dateTo = params.get('dateTo') ?? ''
  const [text, setText] = useState(params.get('q') ?? '')
  const q = useDebounced(text.trim())
  const filters = { status: status || undefined, companyId: companyId || undefined, q: q || undefined, dateFrom: dateFrom || undefined, dateTo: dateTo || undefined }
  const key = JSON.stringify(filters)
  const [page, setPage] = usePaged(key)
  const [exporting, setExporting] = useState(false)
  const { data, error, loading, reload } = useAsync(
    () => api<PaymentsPage>('/super/payments', { query: { ...filters, page, pageSize: PAGE_SIZE } }),
    [key, page],
  )

  function update(patch: Record<string, string>) {
    setParams((p) => {
      const n = new URLSearchParams(p)
      for (const [k, v] of Object.entries(patch)) {
        if (v) n.set(k, v)
        else n.delete(k)
      }
      return n
    }, { replace: true })
  }

  async function exportCsv() {
    setExporting(true)
    try {
      const rows: PaymentsPage['items'] = []
      for (let p = 1; ; p++) {
        const res = await api<PaymentsPage>('/super/payments', { query: { ...filters, page: p, pageSize: EXPORT_PAGE } })
        rows.push(...res.items)
        if (res.items.length < EXPORT_PAGE || rows.length >= res.total || rows.length >= EXPORT_CAP) break
      }
      const csv = toCsv(
        ['Date', 'Company', 'Plan', 'Seats', 'Months', 'Amount (INR)', 'Refunded (INR)', 'Status', 'Invoice', 'Razorpay order', 'Razorpay payment', 'Failure reason'],
        rows.map((o) => [
          date(o.paidAt ?? o.createdAt, true), o.companyName ?? '', o.planCode, o.seats, o.months, o.amount, o.refundedAmount ?? 0,
          PAYMENT_LABELS[o.status] ?? o.status, o.invoiceNumber ?? '', o.providerOrderId, o.providerPaymentId ?? '', o.failureReason ?? '',
        ]),
      )
      downloadText(`payments-${todayStamp()}.csv`, csv)
      toast(rows.length >= EXPORT_CAP ? `Exported the first ${EXPORT_CAP.toLocaleString('en-IN')} payments; narrow the filters for the rest` : `Exported ${rows.length} payment${rows.length === 1 ? '' : 's'}`, rows.length >= EXPORT_CAP ? 'info' : 'success')
    } catch (e) {
      toast(e instanceof Error ? e.message : 'Export failed', 'error')
    } finally {
      setExporting(false)
    }
  }

  const filtered = Boolean(status || companyId || q || dateFrom || dateTo)

  return (
    <>
      <PageHeader
        title="Payments"
        subtitle="Online subscription payments from all companies (Razorpay)."
        actions={
          <button className="btn" onClick={exportCsv} disabled={exporting || !data?.total}>
            {exporting ? <Spinner small /> : <Download size={16} />} Export CSV
          </button>
        }
      />
      <Card>
        {data && !data.paymentsEnabled && (
          <div style={{ marginBottom: 16 }}>
            <Alert kind="info">Razorpay keys are not configured on the API yet, so companies can't pay online. Set RAZORPAY_KEY_ID, RAZORPAY_KEY_SECRET and RAZORPAY_WEBHOOK_SECRET.</Alert>
          </div>
        )}
        <div className="stack" style={{ gap: 12, marginBottom: 16 }}>
          <div className="segmented" role="group" aria-label="Status" style={{ alignSelf: 'flex-start' }}>
            {FILTERS.map(([k, label]) => (
              <button key={k} className={status === k ? 'on' : ''} aria-pressed={status === k} onClick={() => update({ status: k })}>{label}</button>
            ))}
          </div>
          <div className="filters">
            <AsyncPicker
              value={companyId}
              valueLabel={params.get('companyName')}
              onChange={(id, label) => update({ companyId: id, companyName: id ? label : '' })}
              search={searchCompanies}
              allLabel="All companies"
              ariaLabel="Company"
              width={240}
            />
            <div className="input-icon" style={{ width: 240, maxWidth: '100%' }}>
              <Search size={16} />
              <input className="input" aria-label="Search payments" placeholder="Order / payment ID" value={text} onChange={(e) => setText(e.target.value)} />
            </div>
            <div className="inline-group" role="group" aria-label="Payment date">
              <input className="input" type="date" aria-label="From date" value={dateFrom} max={dateTo || undefined} onChange={(e) => update({ dateFrom: e.target.value })} />
              <span>to</span>
              <input className="input" type="date" aria-label="To date" value={dateTo} min={dateFrom || undefined} onChange={(e) => update({ dateTo: e.target.value })} />
            </div>
            {filtered && (
              <button className="btn sm ghost" onClick={() => { setText(''); setParams({}, { replace: true }) }}>Clear filters</button>
            )}
          </div>
          {data?.totals && (
            <div className="faint" role="status">
              <b style={{ color: 'var(--text)' }}>{money(data.totals.paidInr)}</b> collected from {data.totals.paidCount} paid order{data.totals.paidCount === 1 ? '' : 's'}
              {(toNumber(data.totals.refundedInr) ?? 0) > 0 && <> · {money(data.totals.refundedInr)} refunded · <b style={{ color: 'var(--text)' }}>{money(data.totals.netInr)}</b> net</>}
              {filtered ? ' matching these filters' : ''} · {data.total} order{data.total === 1 ? '' : 's'} listed
            </div>
          )}
        </div>
        {loading && !data ? <Loading /> : error ? <ErrorState message={error} onRetry={reload} /> : !data?.items.length ? (
          <Empty
            icon={<CreditCard size={24} />}
            title={filtered ? 'No payments match' : 'No payments yet'}
            message={filtered ? 'Try different filters.' : "Renewals paid from a company's Billing page appear here."}
          />
        ) : (
          <div className="table-wrap">
            <table className="table">
              <thead>
                <tr><th>Company</th><th>Plan</th><th className="right">Amount</th><th>Status</th><th>Razorpay IDs</th><th>Date</th></tr>
              </thead>
              <tbody>
                {data.items.map((o) => (
                  <tr key={o.id}>
                    <td>
                      {o.companyName
                        ? <Link className="cell-title linkish" to={`/super/companies/${o.companyId}`}>{o.companyName}</Link>
                        : <span className="faint">Deleted company</span>}
                    </td>
                    <td className="nowrap">{o.planCode} · {o.seats} seats · {o.months} mo</td>
                    <td className="right nowrap">
                      <div className="cell-title">{money(o.amount)}</div>
                      {(toNumber(o.refundedAmount) ?? 0) > 0 && <div className="cell-sub">−{money(o.refundedAmount)} refunded</div>}
                    </td>
                    <td>
                      <Badge status={o.status} label={PAYMENT_LABELS[o.status] ?? o.status} />
                      {o.failureReason && <div className="cell-sub" style={{ color: '#fca5a5', maxWidth: 240 }}>{o.failureReason}</div>}
                      {(o.status === 'paid' || o.status === 'refunded') && (
                        <div><Link className="linkish" style={{ fontSize: 12 }} to={`/super/payments/${o.id}/invoice`}><FileText size={12} style={{ verticalAlign: -1 }} /> {o.invoiceNumber ?? 'Invoice'}</Link></div>
                      )}
                    </td>
                    <td className="mono" style={{ fontSize: 12 }}>{o.providerOrderId}<br />{o.providerPaymentId ?? ''}</td>
                    <td className="faint nowrap">{date(o.paidAt ?? o.createdAt, true)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
        {data && <Pagination page={page} pageSize={PAGE_SIZE} total={data.total} onPage={setPage} />}
      </Card>
    </>
  )
}
