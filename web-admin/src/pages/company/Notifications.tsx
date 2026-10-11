import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { Bell, Check, CornerUpLeft, Megaphone, X } from 'lucide-react'
import { api } from '../../api/client'
import type { NotificationItem, Page } from '../../api/types'
import { Card, Empty, ErrorState, Loading, PageHeader, Pagination, useAsync } from '../../components/ui'
import { relative } from '../../lib/format'

const PAGE_SIZE = 50

const TYPES: Record<string, { label: string; icon: typeof Bell; color: string }> = {
  billApproved: { label: 'Approved', icon: Check, color: '#34d399' },
  billRejected: { label: 'Rejected', icon: X, color: '#f87171' },
  billReturned: { label: 'Returned', icon: CornerUpLeft, color: '#a78bfa' },
  companyAnnouncement: { label: 'Announcement', icon: Megaphone, color: '#7c9cff' },
}

export default function Notifications() {
  const [type, setType] = useState('all')
  const [page, setPage] = useState(1)
  const { data, error, loading, reload } = useAsync(
    () => api<Page<NotificationItem>>('/admin/notifications', {
      query: {
        page,
        pageSize: PAGE_SIZE,
        type: type === 'all' ? undefined : type,
        excludeType: type === 'all' ? 'companyAnnouncement' : undefined,
      },
    }),
    [type, page],
  )

  useEffect(() => setPage(1), [type])
  const list = data?.items ?? []

  return (
    <>
      <PageHeader title="Activity" subtitle="Decisions sent to employees' notification inboxes in the mobile apps." />
      <Card>
        <div className="segmented" style={{ marginBottom: 16 }}>
          {[['all', 'All'], ['billApproved', 'Approved'], ['billReturned', 'Returned'], ['billRejected', 'Rejected']].map(([k, label]) => (
            <button key={k} className={type === k ? 'on' : ''} onClick={() => setType(k)}>{label}</button>
          ))}
        </div>
        {loading && !data ? <Loading /> : error ? <ErrorState message={error} onRetry={reload} /> : list.length === 0 ? (
          <Empty icon={<Bell size={24} />} title="No activity yet" message="Approving, returning or rejecting invoices creates activity here." />
        ) : (
          list.map((n) => {
            const meta = TYPES[n.type] ?? { label: n.type, icon: Bell, color: '#7c9cff' }
            const Icon = meta.icon
            return (
              <div key={n.id} className="list-item">
                <div className="dot-icon" style={{ color: meta.color }}><Icon size={16} /></div>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div className="row between">
                    <div className="cell-title">{n.title}</div>
                    <span className="faint nowrap" style={{ fontSize: 12.5 }}>{relative(n.createdAt)}</span>
                  </div>
                  <div className="muted">{n.body}</div>
                  <div className="row" style={{ marginTop: 6, gap: 14, fontSize: 12.5 }}>
                    <span className="faint">{n.read ? 'Seen by employee' : 'Not yet seen'}</span>
                    {n.invoiceServerId && <Link to={`/invoices/${n.invoiceServerId}`}>Open invoice →</Link>}
                  </div>
                </div>
              </div>
            )
          })
        )}
        {data && <Pagination page={page} pageSize={PAGE_SIZE} total={data.total} onPage={setPage} />}
      </Card>
    </>
  )
}
