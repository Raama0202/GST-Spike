import { useState } from 'react'
import { Link, useNavigate, useSearchParams } from 'react-router-dom'
import { Building2, CalendarPlus, Pause, Play, Plus, Search } from 'lucide-react'
import { api } from '../../api/client'
import type { Company, Page } from '../../api/types'
import {
  Badge, Card, Empty, ErrorState, Loading, PageHeader, Pagination, useAsync, useDebounced, usePaged, useToast,
} from '../../components/ui'
import { date } from '../../lib/format'
import { CopyCode, CreateCompany, EndsCell, ExtendDialog, StatusConfirm, statusAction, type StatusAction } from './companyDialogs'

type Filter = 'all' | 'active' | 'pending' | 'suspended'
type CompanyPage = Page<Company> & { counts?: Record<Filter, number> }

const FILTERS: Filter[] = ['all', 'active', 'pending', 'suspended']
const PAGE_SIZE = 25

export default function Companies() {
  const toast = useToast()
  const navigate = useNavigate()
  const [params, setParams] = useSearchParams()
  const filter = (FILTERS.includes(params.get('status') as Filter) ? params.get('status') : 'all') as Filter
  const [query, setQuery] = useState('')
  const search = useDebounced(query.trim())
  const [page, setPage] = usePaged(`${filter}|${search}`)
  const { data, error, loading, reload } = useAsync(
    () => api<CompanyPage>('/super/companies', {
      query: { page, pageSize: PAGE_SIZE, status: filter === 'all' ? undefined : filter, q: search || undefined },
    }),
    [page, filter, search],
  )
  const [creating, setCreating] = useState(false)
  const [extend, setExtend] = useState<Company | null>(null)
  const [confirm, setConfirm] = useState<{ company: Company; action: StatusAction } | null>(null)
  const [busy, setBusy] = useState(false)

  const list = data?.items ?? []
  const counts = (s: Filter) => data?.counts?.[s] ?? 0

  function setFilter(next: Filter) {
    setParams((p) => {
      const n = new URLSearchParams(p)
      if (next === 'all') n.delete('status')
      else n.set('status', next)
      return n
    }, { replace: true })
  }

  async function runStatus() {
    if (!confirm) return
    setBusy(true)
    try {
      await api(`/super/companies/${confirm.company.id}/${confirm.action}`, { method: 'POST' })
      toast(`${confirm.company.name} ${confirm.action === 'suspend' ? 'suspended' : 'reactivated'}`)
      setConfirm(null)
      await reload()
    } catch (e) {
      toast(e instanceof Error ? e.message : 'Action failed', 'error')
    } finally {
      setBusy(false)
    }
  }

  return (
    <>
      <PageHeader
        title="Companies"
        subtitle="Provision tenants, share activation codes and control subscription access."
        actions={<button className="btn primary" onClick={() => setCreating(true)}><Plus size={16} /> Create company</button>}
      />
      <Card>
        <div className="row wrap between" style={{ marginBottom: 16 }}>
          <div className="segmented" role="group" aria-label="Status">
            {FILTERS.map((f) => (
              <button key={f} className={filter === f ? 'on' : ''} aria-pressed={filter === f} onClick={() => setFilter(f)}>
                {f[0].toUpperCase() + f.slice(1)} <span className="count">{counts(f)}</span>
              </button>
            ))}
          </div>
          <div className="input-icon" style={{ width: 280, maxWidth: '100%' }}>
            <Search size={16} />
            <input className="input" aria-label="Search companies" placeholder="Search name, admin email or code" value={query} onChange={(e) => setQuery(e.target.value)} />
          </div>
        </div>
        {loading && !data ? <Loading /> : error ? <ErrorState message={error} onRetry={reload} /> : list.length === 0 ? (
          <Empty
            icon={<Building2 size={24} />}
            title={counts('all') ? 'No companies match' : 'No companies yet'}
            message={counts('all') ? 'Try a different filter or search.' : 'Create a company to give a new customer access.'}
          />
        ) : (
          <div className="table-wrap">
            <table className="table">
              <thead>
                <tr>
                  <th>Company</th><th>Status</th><th>Plan</th><th>Ends</th><th className="right">Employees</th>
                  <th>Last activity</th><th>Activation code</th><th className="right">Actions</th>
                </tr>
              </thead>
              <tbody>
                {list.map((c) => {
                  const action = statusAction(c.status)
                  return (
                    <tr
                      key={c.id}
                      className="clickable"
                      onClick={(e) => {
                        if ((e.target as HTMLElement).closest('button, a')) return
                        navigate(`/super/companies/${c.id}`)
                      }}
                    >
                      <td>
                        <Link className="cell-title linkish" to={`/super/companies/${c.id}`}>{c.name}</Link>
                        <div className="cell-sub">{c.adminEmail || c.industry || 'No admin email'}</div>
                      </td>
                      <td><Badge status={c.status} /></td>
                      <td>
                        <div className="nowrap">{c.planName ?? c.planCode ?? '—'}</div>
                        {c.seats != null && <div className="cell-sub">{c.seats} seats</div>}
                      </td>
                      <td><EndsCell endsAt={c.endsAt} /></td>
                      <td className="right nowrap">{c.employeeCount ?? '—'}{c.seats != null && c.employeeCount != null && <span className="faint"> / {c.seats}</span>}</td>
                      <td className="faint nowrap">{c.lastActivityAt ? date(c.lastActivityAt, true) : 'Never'}</td>
                      <td><CopyCode code={c.activationCode} /></td>
                      <td className="right">
                        <div className="actions" style={{ justifyContent: 'flex-end' }}>
                          <button className="btn sm" onClick={() => setExtend(c)}><CalendarPlus size={14} /> Extend</button>
                          {action === 'reactivate' && (
                            <button className="btn sm success" onClick={() => setConfirm({ company: c, action })}><Play size={14} /> Reactivate</button>
                          )}
                          {action === 'suspend' && (
                            <button className="btn sm danger" onClick={() => setConfirm({ company: c, action })}><Pause size={14} /> Suspend</button>
                          )}
                        </div>
                      </td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>
        )}
        {data && <Pagination page={page} pageSize={PAGE_SIZE} total={data.total} onPage={setPage} />}
      </Card>

      {creating && <CreateCompany onClose={() => setCreating(false)} onCreated={reload} />}
      {extend && <ExtendDialog company={extend} endsAt={extend.endsAt ?? null} onClose={() => setExtend(null)} onDone={() => void reload()} />}
      {confirm && (
        <StatusConfirm company={confirm.company} action={confirm.action} busy={busy} onConfirm={runStatus} onClose={() => setConfirm(null)} />
      )}
    </>
  )
}
