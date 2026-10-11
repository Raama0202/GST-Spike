import { useEffect, useState } from 'react'
import { CreditCard } from 'lucide-react'
import { api } from '../../api/client'
import type { Page, PaymentOrder } from '../../api/types'
import { Alert, Badge, Card, Empty, ErrorState, Loading, PageHeader, Pagination, useAsync } from '../../components/ui'
import { date, money } from '../../lib/format'

const PAGE_SIZE = 50
const FILTERS = [['', 'All'], ['paid', 'Paid'], ['created', 'Pending'], ['failed', 'Failed']] as const

export default function Payments() {
  const [status, setStatus] = useState('')
  const [page, setPage] = useState(1)
  const { data, error, loading, reload } = useAsync(
    () => api<Page<PaymentOrder> & { paymentsEnabled: boolean }>('/super/payments', { query: { page, pageSize: PAGE_SIZE, status: status || undefined } }),
    [page, status],
  )
  useEffect(() => setPage(1), [status])

  return (
    <>
      <PageHeader title="Payments" subtitle="Online subscription payments from all companies (Razorpay)." />
      <Card>
        {data && !data.paymentsEnabled && (
          <div style={{ marginBottom: 16 }}>
            <Alert kind="info">Razorpay keys are not configured on the API yet, so companies can't pay online. Set RAZORPAY_KEY_ID, RAZORPAY_KEY_SECRET and RAZORPAY_WEBHOOK_SECRET.</Alert>
          </div>
        )}
        <div className="segmented" style={{ marginBottom: 16 }}>
          {FILTERS.map(([key, label]) => (
            <button key={key} className={status === key ? 'on' : ''} onClick={() => setStatus(key)}>{label}</button>
          ))}
        </div>
        {loading && !data ? <Loading /> : error ? <ErrorState message={error} onRetry={reload} /> : !data?.items.length ? (
          <Empty icon={<CreditCard size={24} />} title="No payments yet" message="Renewals paid from a company's Billing page appear here." />
        ) : (
          <div className="table-wrap">
            <table className="table">
              <thead>
                <tr><th>Company</th><th>Plan</th><th>Amount</th><th>Status</th><th>Razorpay IDs</th><th>Date</th></tr>
              </thead>
              <tbody>
                {data.items.map((o) => (
                  <tr key={o.id}>
                    <td className="cell-title">{o.companyName ?? '—'}</td>
                    <td>{o.planCode} · {o.seats} seats · {o.months} mo</td>
                    <td className="nowrap cell-title">{money(o.amount)}</td>
                    <td><Badge status={o.status === 'paid' ? 'approved' : o.status === 'failed' ? 'failed' : 'pending'} label={o.status} /></td>
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
