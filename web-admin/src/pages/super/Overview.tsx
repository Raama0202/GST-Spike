import { useState } from 'react'
import { Link } from 'react-router-dom'
import { ArrowRight, Building2, CalendarClock, CheckCircle2, Clock, FileText, IndianRupee, PauseCircle, TrendingUp, UserPlus, Users } from 'lucide-react'
import { Area, AreaChart, CartesianGrid, Cell, Pie, PieChart, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts'
import { api } from '../../api/client'
import type { Company, Page, PlatformMetrics } from '../../api/types'
import { Badge, Card, Empty, ErrorState, Loading, PageHeader, Stat, useAsync } from '../../components/ui'
import { date, dayLabel, daysUntil, money, relative, toNumber } from '../../lib/format'

const tooltipStyle = { background: '#121a3a', border: '1px solid rgba(255,255,255,.15)', borderRadius: 12 }

type Series = 'revenue' | 'invoices' | 'signups'
const SERIES: { key: Series; label: string; color: string }[] = [
  { key: 'revenue', label: 'Revenue', color: '#34d399' },
  { key: 'invoices', label: 'Invoices', color: '#7c9cff' },
  { key: 'signups', label: 'Sign-ups', color: '#fbbf24' },
]

export default function SuperOverview() {
  const [series, setSeries] = useState<Series>('revenue')
  const { data, error, loading, reload } = useAsync(async () => {
    const [metrics, recent] = await Promise.all([
      api<PlatformMetrics>('/super/metrics'),
      api<Page<Company>>('/super/companies', { query: { pageSize: 6 } }),
    ])
    return { metrics, recent: recent.items }
  })

  if (loading && !data) return <><PageHeader title="Platform overview" /><Card><Loading /></Card></>
  if (error || !data) return <><PageHeader title="Platform overview" /><Card><ErrorState message={error ?? ''} onRetry={reload} /></Card></>

  const { metrics: m, recent } = data
  const health = [
    { name: 'Active', value: m.companies.active, color: '#34d399' },
    { name: 'Pending', value: m.companies.pending, color: '#fbbf24' },
    { name: 'Suspended', value: m.companies.suspended, color: '#f87171' },
  ].filter((x) => x.value > 0)
  const daily = m.daily.map((d) => ({ day: dayLabel(d.date), revenue: toNumber(d.revenueInr) ?? 0, invoices: d.invoices, signups: d.signups }))
  const active = SERIES.find((s) => s.key === series)!

  return (
    <>
      <PageHeader
        title="Platform overview"
        subtitle="Tenants, revenue and usage across web, Android and iOS."
        actions={<Link to="/super/companies" className="btn primary"><Building2 size={16} /> Manage companies</Link>}
      />
      <div className="stack">
        <div className="grid cols-4">
          <Stat icon={<Building2 size={20} />} label="Total companies" value={m.companies.all} tone="#7c9cff" to="/super/companies" />
          <Stat icon={<CheckCircle2 size={20} />} label="Active" value={m.companies.active} tone="#34d399" to="/super/companies?status=active" />
          <Stat icon={<Clock size={20} />} label="Awaiting activation" value={m.companies.pending} tone="#fbbf24" to="/super/companies?status=pending" />
          <Stat icon={<PauseCircle size={20} />} label="Suspended" value={m.companies.suspended} tone="#f87171" to="/super/companies?status=suspended" />
        </div>
        <div className="grid cols-4">
          <Stat icon={<TrendingUp size={20} />} label="MRR (active subscriptions)" value={money(m.mrrInr)} tone="#34d399" />
          <Stat icon={<IndianRupee size={20} />} label={`Revenue · 30 days (total ${money(m.revenueTotalInr, true)})`} value={money(m.revenue30dInr)} tone="#a78bfa" to="/super/payments" />
          <Stat icon={<FileText size={20} />} label="Invoices · 30 days" value={m.invoices30d.toLocaleString('en-IN')} tone="#7c9cff" />
          <Stat icon={<Users size={20} />} label={`Active employees · ${m.signups30d} new compan${m.signups30d === 1 ? 'y' : 'ies'} in 30 days`} value={m.employeesActive.toLocaleString('en-IN')} tone="#fbbf24" />
        </div>

        <div className="grid cols-3">
          <Card
            title="Last 30 days"
            className="span-2"
            actions={
              <div className="segmented" role="group" aria-label="Chart series">
                {SERIES.map((s) => (
                  <button key={s.key} className={series === s.key ? 'on' : ''} aria-pressed={series === s.key} onClick={() => setSeries(s.key)}>{s.label}</button>
                ))}
              </div>
            }
          >
            {daily.length === 0 ? <Empty title="No activity yet" /> : (
              <div className="chart-box">
                <ResponsiveContainer>
                  <AreaChart data={daily} margin={{ left: 0, right: 8, top: 10 }}>
                    <defs>
                      <linearGradient id="platform" x1="0" y1="0" x2="0" y2="1">
                        <stop offset="0%" stopColor={active.color} stopOpacity={0.45} />
                        <stop offset="100%" stopColor={active.color} stopOpacity={0} />
                      </linearGradient>
                    </defs>
                    <CartesianGrid stroke="rgba(255,255,255,.06)" vertical={false} />
                    <XAxis dataKey="day" stroke="rgba(226,232,255,.45)" fontSize={11} tickLine={false} axisLine={false} minTickGap={16} />
                    <YAxis
                      stroke="rgba(226,232,255,.45)"
                      fontSize={11}
                      tickLine={false}
                      axisLine={false}
                      allowDecimals={false}
                      width={series === 'revenue' ? 70 : 36}
                      tickFormatter={(v) => (series === 'revenue' ? money(v, true) : String(v))}
                    />
                    <Tooltip contentStyle={tooltipStyle} formatter={(v) => [series === 'revenue' ? money(v) : String(v), active.label]} />
                    <Area type="monotone" dataKey={series} stroke={active.color} strokeWidth={2.5} fill="url(#platform)" />
                  </AreaChart>
                </ResponsiveContainer>
              </div>
            )}
          </Card>

          <Card title="Expiring soon" subtitle="Subscriptions ending in the next 14 days">
            {m.expiringSoon.length === 0 ? <Empty icon={<CalendarClock size={24} />} title="Nothing expiring" message="No subscriptions end in the next two weeks." /> : (
              m.expiringSoon.map((x) => {
                const left = daysUntil(x.endsAt) ?? 0
                return (
                  <Link key={x.companyId} to={`/super/companies/${x.companyId}`} className="list-item list-link">
                    <div className="dot-icon"><CalendarClock size={16} /></div>
                    <div style={{ flex: 1, minWidth: 0 }}>
                      <div className="cell-title">{x.companyName}</div>
                      <div className="cell-sub">{x.planCode} · ends {date(x.endsAt)}</div>
                    </div>
                    <span className={`badge ${left <= 3 ? 'red' : 'amber'}`}>{left <= 0 ? 'today' : `${left}d`}</span>
                  </Link>
                )
              })
            )}
          </Card>
        </div>

        <div className="grid cols-3">
          <Card title="Tenant health" subtitle="Companies by status">
            {health.length === 0 ? <Empty title="No companies yet" /> : (
              <div className="chart-box">
                <ResponsiveContainer>
                  <PieChart>
                    <Pie data={health} dataKey="value" nameKey="name" innerRadius={62} outerRadius={96} paddingAngle={3} stroke="none">
                      {health.map((x) => <Cell key={x.name} fill={x.color} />)}
                    </Pie>
                    <Tooltip contentStyle={tooltipStyle} />
                  </PieChart>
                </ResponsiveContainer>
              </div>
            )}
            <div className="row wrap" style={{ justifyContent: 'center' }}>
              {health.map((x) => (
                <span key={x.name} className="row faint" style={{ gap: 6, fontSize: 12.5 }}>
                  <span style={{ width: 8, height: 8, borderRadius: 4, background: x.color }} /> {x.name} · {x.value}
                </span>
              ))}
            </div>
          </Card>
          <Card
            title="Recent companies"
            subtitle="Newest tenants first"
            className="span-2"
            actions={<Link to="/super/companies" className="btn sm ghost">View all <ArrowRight size={14} /></Link>}
          >
            {recent.length === 0 ? <Empty icon={<UserPlus size={24} />} title="No companies yet" message="Create your first tenant from Companies." /> : (
              <div className="table-wrap">
                <table className="table">
                  <tbody>
                    {recent.map((c) => (
                      <tr key={c.id}>
                        <td>
                          <Link className="cell-title linkish" to={`/super/companies/${c.id}`}>{c.name}</Link>
                          <div className="cell-sub">{c.adminEmail || c.industry || '—'}</div>
                        </td>
                        <td>{c.planName ?? c.planCode ?? '—'}</td>
                        <td><Badge status={c.status} /></td>
                        <td className="right faint">{relative(c.createdAt)}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </Card>
        </div>
      </div>
    </>
  )
}
