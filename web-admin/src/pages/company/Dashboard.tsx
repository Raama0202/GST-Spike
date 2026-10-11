import { Link, useNavigate } from 'react-router-dom'
import { ArrowRight, CheckCircle2, Clock, CornerUpLeft, Receipt, Upload, XCircle } from 'lucide-react'
import { Area, AreaChart, Bar, BarChart, CartesianGrid, Cell, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts'
import { api } from '../../api/client'
import type { Dashboard as DashboardData, Invoice, Items } from '../../api/types'
import { Badge, Card, Empty, ErrorState, Loading, PageHeader, Stat, useAsync } from '../../components/ui'
import { money, relative, toNumber } from '../../lib/format'
import { InvoiceThumb } from './Invoices'

const tooltipStyle = { background: '#121a3a', border: '1px solid rgba(255,255,255,.15)', borderRadius: 12 }

export default function Dashboard() {
  const navigate = useNavigate()
  const { data, error, loading, reload } = useAsync(async () => {
    const [stats, recent] = await Promise.all([
      api<DashboardData>('/admin/dashboard'),
      api<Items<Invoice>>('/admin/invoices', { query: { pageSize: 100 } }),
    ])
    return { stats, invoices: recent.items }
  })

  if (loading && !data) return <><PageHeader title="Dashboard" /><Card><Loading /></Card></>
  if (error || !data) return <><PageHeader title="Dashboard" /><Card><ErrorState message={error ?? ''} onRetry={reload} /></Card></>

  const { stats, invoices } = data
  const statusChart = [
    { name: 'Pending', value: stats.pendingCount, color: '#fbbf24' },
    { name: 'Approved', value: stats.approvedCount, color: '#34d399' },
    { name: 'Returned', value: stats.returnedCount, color: '#a78bfa' },
    { name: 'Rejected', value: stats.rejectedCount, color: '#f87171' },
  ]

  const byDay = new Map<string, number>()
  for (let i = 13; i >= 0; i--) {
    const d = new Date(Date.now() - i * 86400000)
    byDay.set(d.toISOString().slice(0, 10), 0)
  }
  for (const inv of invoices) {
    const key = inv.uploadedAt?.slice(0, 10)
    if (key && byDay.has(key)) byDay.set(key, (byDay.get(key) ?? 0) + (toNumber(inv.netAmount) ?? 0))
  }
  const spend = [...byDay.entries()].map(([day, amount]) => ({
    day: new Date(day).toLocaleDateString('en-IN', { day: '2-digit', month: 'short' }),
    amount,
  }))
  const approvedValue = invoices.filter((i) => i.approvalStatus === 'approved').reduce((s, i) => s + (toNumber(i.netAmount) ?? 0), 0)
  const pendingValue = invoices.filter((i) => i.approvalStatus === 'pending').reduce((s, i) => s + (toNumber(i.netAmount) ?? 0), 0)

  return (
    <>
      <PageHeader
        title="Dashboard"
        subtitle="Live view of bills submitted from the Android and iOS employee apps."
        actions={
          <Link to="/invoices?status=pending" className="btn primary">
            <Clock size={16} /> Review pending ({stats.pendingCount})
          </Link>
        }
      />
      <div className="stack">
        <div className="grid cols-4">
          <Stat icon={<Upload size={20} />} label="Uploaded today" value={stats.todayUploads} tone="#22d3ee" />
          <Stat icon={<Clock size={20} />} label={`Awaiting review · ${money(pendingValue, true)}`} value={stats.pendingCount} tone="#fbbf24" />
          <Stat icon={<CheckCircle2 size={20} />} label={`Approved · ${money(approvedValue, true)}`} value={stats.approvedCount} tone="#34d399" />
          <Stat
            icon={<CornerUpLeft size={20} />}
            label="Returned / rejected"
            value={<>{stats.returnedCount}<span className="faint" style={{ fontSize: 18 }}> / {stats.rejectedCount}</span></>}
            tone="#a78bfa"
          />
        </div>

        <div className="grid cols-3">
          <Card title="Submitted value" subtitle="Net amount uploaded per day · last 14 days" className="span-2">
            <div className="chart-box">
              <ResponsiveContainer>
                <AreaChart data={spend} margin={{ left: 0, right: 8, top: 10 }}>
                  <defs>
                    <linearGradient id="spend" x1="0" y1="0" x2="0" y2="1">
                      <stop offset="0%" stopColor="#7c9cff" stopOpacity={0.55} />
                      <stop offset="100%" stopColor="#7c9cff" stopOpacity={0} />
                    </linearGradient>
                  </defs>
                  <CartesianGrid stroke="rgba(255,255,255,.06)" vertical={false} />
                  <XAxis dataKey="day" stroke="rgba(226,232,255,.45)" fontSize={11} tickLine={false} axisLine={false} />
                  <YAxis stroke="rgba(226,232,255,.45)" fontSize={11} tickLine={false} axisLine={false} tickFormatter={(v) => money(v, true)} width={70} />
                  <Tooltip contentStyle={tooltipStyle} formatter={(v) => money(v)} />
                  <Area type="monotone" dataKey="amount" stroke="#7c9cff" strokeWidth={2.5} fill="url(#spend)" />
                </AreaChart>
              </ResponsiveContainer>
            </div>
          </Card>
          <Card title="Approval pipeline" subtitle="All-time invoice status">
            <div className="chart-box">
              <ResponsiveContainer>
                <BarChart data={statusChart} margin={{ top: 10 }}>
                  <CartesianGrid stroke="rgba(255,255,255,.06)" vertical={false} />
                  <XAxis dataKey="name" stroke="rgba(226,232,255,.45)" fontSize={11} tickLine={false} axisLine={false} />
                  <YAxis allowDecimals={false} stroke="rgba(226,232,255,.45)" fontSize={11} tickLine={false} axisLine={false} width={28} />
                  <Tooltip contentStyle={tooltipStyle} cursor={{ fill: 'rgba(255,255,255,.04)' }} />
                  <Bar dataKey="value" radius={[8, 8, 0, 0]}>
                    {statusChart.map((x) => <Cell key={x.name} fill={x.color} />)}
                  </Bar>
                </BarChart>
              </ResponsiveContainer>
            </div>
          </Card>
        </div>

        <Card
          title="Recent submissions"
          subtitle="Newest bills from your field teams"
          actions={<Link to="/invoices" className="btn sm ghost">All invoices <ArrowRight size={14} /></Link>}
        >
          {invoices.length === 0 ? (
            <Empty icon={<Receipt size={24} />} title="No invoices yet" message="Bills scanned in the employee apps will appear here." />
          ) : (
            <div className="table-wrap">
              <table className="table">
                <tbody>
                  {invoices.slice(0, 6).map((inv) => (
                    <tr key={inv.id} className="clickable" onClick={() => navigate(`/invoices/${inv.id}`)}>
                      <td>
                        <div className="row">
                          <InvoiceThumb invoice={inv} />
                          <div>
                            <div className="cell-title">{inv.vendorName || inv.editedData?.vendorName || 'Unknown vendor'}</div>
                            <div className="cell-sub mono">{inv.invoiceNumber || 'No invoice number'}</div>
                          </div>
                        </div>
                      </td>
                      <td className="nowrap">{money(inv.netAmount)}</td>
                      <td><Badge status={inv.approvalStatus} /></td>
                      <td className="right faint nowrap">{relative(inv.uploadedAt)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </Card>
        {stats.rejectedCount > 0 && (
          <div className="faint row" style={{ fontSize: 12.5 }}><XCircle size={14} /> {stats.rejectedCount} rejected bills are kept for audit.</div>
        )}
      </div>
    </>
  )
}
