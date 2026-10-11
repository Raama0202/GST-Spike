import { Link } from 'react-router-dom'
import { ArrowRight, Building2, CheckCircle2, Clock, PauseCircle, Tags } from 'lucide-react'
import { Cell, Pie, PieChart, ResponsiveContainer, Tooltip } from 'recharts'
import { api } from '../../api/client'
import type { Company, Items, Page, Plan } from '../../api/types'
import { Badge, Card, Empty, ErrorState, Loading, PageHeader, Stat, useAsync } from '../../components/ui'
import { money, relative } from '../../lib/format'

export default function SuperOverview() {
  const { data, error, loading, reload } = useAsync(async () => {
    const [companies, plans] = await Promise.all([
      api<Page<Company> & { counts?: Record<string, number> }>('/super/companies', { query: { pageSize: 6 } }),
      api<Items<Plan>>('/super/plans'),
    ])
    return { companies: companies.items, counts: companies.counts ?? {}, total: companies.total, plans: plans.items }
  })

  if (loading && !data) return <><PageHeader title="Overview" /><Card><Loading /></Card></>
  if (error || !data) return <><PageHeader title="Overview" /><Card><ErrorState message={error ?? ''} onRetry={reload} /></Card></>

  const { companies, plans, counts, total } = data
  const count = (s: string) => counts[s] ?? 0
  const chart = [
    { name: 'Active', value: count('active'), color: '#34d399' },
    { name: 'Pending', value: count('pending'), color: '#fbbf24' },
    { name: 'Suspended', value: count('suspended'), color: '#f87171' },
  ].filter((x) => x.value > 0)

  return (
    <>
      <PageHeader
        title="Platform overview"
        subtitle="Tenants and subscription catalogue across all apps."
        actions={<Link to="/super/companies" className="btn primary"><Building2 size={16} /> Manage companies</Link>}
      />
      <div className="stack">
        <div className="grid cols-4">
          <Stat icon={<Building2 size={20} />} label="Total companies" value={total} tone="#7c9cff" />
          <Stat icon={<CheckCircle2 size={20} />} label="Active" value={count('active')} tone="#34d399" />
          <Stat icon={<Clock size={20} />} label="Awaiting activation" value={count('pending')} tone="#fbbf24" />
          <Stat icon={<PauseCircle size={20} />} label="Suspended" value={count('suspended')} tone="#f87171" />
        </div>
        <div className="grid cols-3">
          <Card title="Tenant health" subtitle="Companies by status">
            {chart.length === 0 ? <Empty title="No companies yet" /> : (
              <div className="chart-box">
                <ResponsiveContainer>
                  <PieChart>
                    <Pie data={chart} dataKey="value" nameKey="name" innerRadius={62} outerRadius={96} paddingAngle={3} stroke="none">
                      {chart.map((x) => <Cell key={x.name} fill={x.color} />)}
                    </Pie>
                    <Tooltip contentStyle={{ background: '#121a3a', border: '1px solid rgba(255,255,255,.15)', borderRadius: 12 }} />
                  </PieChart>
                </ResponsiveContainer>
              </div>
            )}
            <div className="row wrap" style={{ justifyContent: 'center' }}>
              {chart.map((x) => (
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
            {companies.length === 0 ? <Empty title="No companies yet" message="Create your first tenant from Companies." /> : (
              <div className="table-wrap">
                <table className="table">
                  <tbody>
                    {companies.slice(0, 6).map((c) => (
                      <tr key={c.id}>
                        <td><div className="cell-title">{c.name}</div><div className="cell-sub">{c.industry || 'No industry set'}</div></td>
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
        <Card
          title="Subscription catalogue"
          subtitle={`${plans.length} plan${plans.length === 1 ? '' : 's'} available to tenants`}
          actions={<Link to="/super/plans" className="btn sm"><Tags size={14} /> Manage plans</Link>}
        >
          <div className="grid cols-3">
            {plans.map((p) => (
              <div key={p.id} className="glass card">
                <div className="row between">
                  <div className="card-title">{p.name}</div>
                  <span className="badge gray mono" style={{ textTransform: 'none' }}>{p.code}</span>
                </div>
                <div className="stat-value" style={{ marginTop: 10 }}>{money(p.monthlyPriceInr)}<span className="faint" style={{ fontSize: 13, fontWeight: 500 }}> / month</span></div>
                <div className="muted">{p.maxEmployees ? `Up to ${p.maxEmployees} employees` : 'Unlimited employees'}</div>
              </div>
            ))}
          </div>
        </Card>
      </div>
    </>
  )
}
