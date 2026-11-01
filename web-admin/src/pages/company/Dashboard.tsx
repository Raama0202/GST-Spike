import { Link, useNavigate } from 'react-router-dom'
import { ArrowRight, CheckCircle2, Clock, CornerUpLeft, PieChart, Receipt, Upload, Users, XCircle } from 'lucide-react'
import { Area, AreaChart, Bar, BarChart, CartesianGrid, Cell, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts'
import { api } from '../../api/client'
import type { Dashboard as DashboardData, Invoice, Page } from '../../api/types'
import { Badge, Card, Empty, ErrorState, Loading, PageHeader, Stat, useAsync } from '../../components/ui'
import { dayLabel, money, relative, toNumber } from '../../lib/format'
import { InvoiceThumb, vendorOf } from './InvoiceParts'

const tooltipStyle = { background: '#121a3a', border: '1px solid rgba(255,255,255,.15)', borderRadius: 12 }

export default function Dashboard() {
  const navigate = useNavigate()
  const { data, error, loading, reload } = useAsync(async () => {
    const [stats, recent] = await Promise.all([
      api<DashboardData>('/admin/dashboard'),
      api<Page<Invoice>>('/admin/invoices', { query: { pageSize: 6 } }),
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
  const spend = (stats.daily ?? []).map((d) => ({ day: dayLabel(d.date), amount: toNumber(d.amount) ?? 0, count: d.count }))
  const topCategories = stats.topCategories ?? []
  const seats = stats.seats
  const seatShare = seats?.limit ? Math.min(100, Math.round((seats.used / seats.limit) * 100)) : null

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
          <Stat icon={<Upload size={20} />} label="Uploaded today" value={stats.todayUploads} tone="#22d3ee" to="/invoices?sort=uploaded_desc" />
          <Stat
            icon={<Clock size={20} />}
            label={stats.pendingAmount !== undefined ? `Awaiting review · ${money(stats.pendingAmount, true)}` : 'Awaiting review'}
            value={stats.pendingCount}
            tone="#fbbf24"
            to="/invoices?status=pending"
          />
          <Stat
            icon={<CheckCircle2 size={20} />}
            label={stats.approvedAmount !== undefined ? `Approved · ${money(stats.approvedAmount, true)}` : 'Approved'}
            value={stats.approvedCount}
            tone="#34d399"
            to="/invoices?status=approved"
          />
          <Stat icon={<CornerUpLeft size={20} />} label="Returned for correction" value={stats.returnedCount} tone="#a78bfa" to="/invoices?status=returned" />
        </div>

        <div className="grid cols-3">
          <Card title="Submitted value" subtitle="Invoice value uploaded per day · last 14 days (IST)" className="span-2">
            {spend.length === 0 ? <Empty title="No uploads in the last 14 days" /> : (
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
                    <Tooltip
                      contentStyle={tooltipStyle}
                      formatter={(v, _name, item) => [`${money(v)} · ${(item.payload as { count: number }).count} bills`, 'Uploaded']}
                    />
                    <Area type="monotone" dataKey="amount" stroke="#7c9cff" strokeWidth={2.5} fill="url(#spend)" />
                  </AreaChart>
                </ResponsiveContainer>
              </div>
            )}
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

        <div className="grid cols-3">
          <Card
            title="Recent submissions"
            subtitle="Newest bills from your field teams"
            className="span-2"
            actions={<Link to="/invoices" className="btn sm ghost">All invoices <ArrowRight size={14} /></Link>}
          >
            {invoices.length === 0 ? (
              <Empty icon={<Receipt size={24} />} title="No invoices yet" message="Bills scanned in the employee apps will appear here." />
            ) : (
              <div className="table-wrap">
                <table className="table">
                  <tbody>
                    {invoices.map((inv) => (
                      <tr
                        key={inv.id}
                        className="clickable"
                        tabIndex={0}
                        onClick={() => navigate(`/invoices/${inv.id}`)}
                        onKeyDown={(e) => { if (e.key === 'Enter' && e.target === e.currentTarget) navigate(`/invoices/${inv.id}`) }}
                      >
                        <td>
                          <div className="row">
                            <InvoiceThumb invoice={inv} />
                            <div>
                              <div className="cell-title">{vendorOf(inv)}</div>
                              <div className="cell-sub">{inv.employeeName ?? inv.invoiceNumber ?? 'No invoice number'}</div>
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
          <div className="stack">
            {seats && (
              <Card title="Employee seats" actions={<Link to="/employees" className="btn sm ghost"><Users size={14} /> Manage</Link>}>
                <div className="stat-value" style={{ marginTop: 0 }}>
                  {seats.used}<span className="faint" style={{ fontSize: 16, fontWeight: 500 }}> of {seats.limit ?? '∞'} used</span>
                </div>
                {seatShare !== null && <div className={`progress ${seatShare >= 90 ? 'warn' : ''}`}><span style={{ width: `${seatShare}%` }} /></div>}
                {seatShare !== null && seatShare >= 90 && (
                  <div className="faint" style={{ fontSize: 12.5, marginTop: 8 }}>Running out of seats. <Link to="/billing">Add seats</Link></div>
                )}
              </Card>
            )}
            <Card title="Top categories" subtitle="By amount">
              {topCategories.length === 0 ? <Empty icon={<PieChart size={22} />} title="No categorised bills yet" /> : (
                topCategories.map((c) => (
                  <div key={c.name} className="list-item" style={{ padding: '10px 0' }}>
                    <div style={{ flex: 1, minWidth: 0 }}>
                      <div className="cell-title">{c.name}</div>
                      <div className="cell-sub">{c.count} bill{c.count === 1 ? '' : 's'}</div>
                    </div>
                    <div className="cell-title nowrap">{money(c.amount, true)}</div>
                  </div>
                ))
              )}
            </Card>
          </div>
        </div>
        {stats.rejectedCount > 0 && (
          <Link to="/invoices?status=rejected" className="faint row" style={{ fontSize: 12.5 }}><XCircle size={14} /> {stats.rejectedCount} rejected bills are kept for audit.</Link>
        )}
      </div>
    </>
  )
}
