import { useEffect, useState } from 'react'
import { Building2, CalendarPlus, Check, Copy, Pause, Play, Plus, Search } from 'lucide-react'
import { api } from '../../api/client'
import type { Company, Items, Page, Plan } from '../../api/types'
import {
  Alert, Badge, Card, Confirm, Empty, ErrorState, Field, Loading, Modal, PageHeader, Pagination, Spinner, useAsync, useDebounced, useToast,
} from '../../components/ui'
import { date, money } from '../../lib/format'

type Filter = 'all' | 'active' | 'pending' | 'suspended'
type CompanyPage = Page<Company> & { counts?: Record<Filter, number> }

const PAGE_SIZE = 25

export default function Companies() {
  const toast = useToast()
  const [filter, setFilter] = useState<Filter>('all')
  const [query, setQuery] = useState('')
  const [page, setPage] = useState(1)
  const search = useDebounced(query.trim())
  const { data, error, loading, reload } = useAsync(
    () => api<CompanyPage>('/super/companies', {
      query: { page, pageSize: PAGE_SIZE, status: filter === 'all' ? undefined : filter, q: search || undefined },
    }),
    [page, filter, search],
  )
  const [creating, setCreating] = useState(false)
  const [extend, setExtend] = useState<Company | null>(null)
  const [confirm, setConfirm] = useState<{ company: Company; action: 'suspend' | 'reactivate' } | null>(null)
  const [busy, setBusy] = useState(false)

  useEffect(() => setPage(1), [filter, search])

  const list = data?.items ?? []
  const counts = (s: Filter) => data?.counts?.[s] ?? 0

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
          <div className="segmented">
            {(['all', 'active', 'pending', 'suspended'] as Filter[]).map((f) => (
              <button key={f} className={filter === f ? 'on' : ''} onClick={() => setFilter(f)}>
                {f[0].toUpperCase() + f.slice(1)} <span className="count">{counts(f)}</span>
              </button>
            ))}
          </div>
          <div className="input-icon" style={{ width: 280 }}>
            <Search size={16} />
            <input className="input" placeholder="Search companies or codes" value={query} onChange={(e) => setQuery(e.target.value)} />
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
                <tr><th>Company</th><th>Status</th><th>Activation code</th><th>Created</th><th className="right">Actions</th></tr>
              </thead>
              <tbody>
                {list.map((c) => (
                  <tr key={c.id}>
                    <td><div className="cell-title">{c.name}</div><div className="cell-sub">{c.industry || 'No industry set'}</div></td>
                    <td><Badge status={c.status} /></td>
                    <td><CopyCode code={c.activationCode} /></td>
                    <td className="faint nowrap">{date(c.createdAt)}</td>
                    <td className="right">
                      <div className="actions" style={{ justifyContent: 'flex-end' }}>
                        <button className="btn sm" onClick={() => setExtend(c)}><CalendarPlus size={14} /> Extend</button>
                        {c.status === 'suspended' ? (
                          <button className="btn sm success" onClick={() => setConfirm({ company: c, action: 'reactivate' })}><Play size={14} /> Reactivate</button>
                        ) : (
                          <button className="btn sm danger" onClick={() => setConfirm({ company: c, action: 'suspend' })}><Pause size={14} /> Suspend</button>
                        )}
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
        {data && <Pagination page={page} pageSize={PAGE_SIZE} total={data.total} onPage={setPage} />}
      </Card>

      {creating && <CreateCompany onClose={() => setCreating(false)} onCreated={reload} />}
      {extend && <ExtendDialog company={extend} onClose={() => setExtend(null)} />}
      {confirm && (
        <Confirm
          title={confirm.action === 'suspend' ? `Suspend ${confirm.company.name}?` : `Reactivate ${confirm.company.name}?`}
          message={confirm.action === 'suspend'
            ? 'All admins and employees of this company will lose access on web, Android and iOS until it is reactivated.'
            : 'Admins and employees of this company will regain access immediately.'}
          confirmLabel={confirm.action === 'suspend' ? 'Suspend' : 'Reactivate'}
          danger={confirm.action === 'suspend'}
          busy={busy}
          onConfirm={runStatus}
          onClose={() => setConfirm(null)}
        />
      )}
    </>
  )
}

function CopyCode({ code }: { code: string }) {
  const [copied, setCopied] = useState(false)
  return (
    <span className="code-pill">
      <span className="mono">{code}</span>
      <button
        className="btn ghost icon sm"
        style={{ width: 26, height: 26 }}
        title="Copy code"
        aria-label="Copy activation code"
        onClick={async () => {
          await navigator.clipboard.writeText(code)
          setCopied(true)
          setTimeout(() => setCopied(false), 1500)
        }}
      >
        {copied ? <Check size={14} color="#34d399" /> : <Copy size={14} />}
      </button>
    </span>
  )
}

function CreateCompany({ onClose, onCreated }: { onClose: () => void; onCreated: () => void }) {
  const toast = useToast()
  const plans = useAsync(() => api<Items<Plan>>('/super/plans').then((r) => r.items))
  const [form, setForm] = useState({
    name: '', industry: '', adminEmail: '', adminPassword: '', planCode: '', seats: '10', subscriptionDays: '30',
  })
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [created, setCreated] = useState<{ name: string; activationCode: string } | null>(null)

  const plan = plans.data?.find((p) => p.code === form.planCode)
  const set = (key: keyof typeof form) => (e: React.ChangeEvent<HTMLInputElement | HTMLSelectElement>) =>
    setForm((f) => ({ ...f, [key]: e.target.value }))

  async function submit() {
    setError(null)
    if (form.adminPassword.length < 8) return setError('Admin password must be at least 8 characters.')
    if (plan?.maxEmployees && Number(form.seats) > plan.maxEmployees) return setError(`The ${plan.name} plan allows at most ${plan.maxEmployees} seats.`)
    setBusy(true)
    try {
      const res = await api<{ name: string; activationCode: string }>('/super/companies', {
        method: 'POST',
        body: {
          name: form.name.trim(),
          industry: form.industry.trim() || null,
          adminEmail: form.adminEmail.trim(),
          adminPassword: form.adminPassword,
          planCode: form.planCode,
          seats: Number(form.seats),
          subscriptionDays: Number(form.subscriptionDays),
        },
      })
      setCreated(res)
      toast(`${res.name} created`)
      onCreated()
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not create company')
    } finally {
      setBusy(false)
    }
  }

  if (created) {
    return (
      <Modal title="Company created" onClose={onClose} footer={<button className="btn primary" onClick={onClose}>Done</button>}>
        <div className="stack">
          <Alert kind="success">
            <b>{created.name}</b> is ready. Share the activation code with the customer — they activate once, then sign in with the admin email and password you set.
          </Alert>
          <div className="row" style={{ justifyContent: 'center', padding: 10 }}><CopyCode code={created.activationCode} /></div>
        </div>
      </Modal>
    )
  }

  const valid = form.name.trim() && form.adminEmail.includes('@') && form.adminPassword && form.planCode && Number(form.seats) > 0 && Number(form.subscriptionDays) > 0

  return (
    <Modal
      title="Create company"
      subtitle="Sets up the tenant, its first company admin and a subscription."
      onClose={onClose}
      wide
      footer={
        <>
          <button className="btn" onClick={onClose}>Cancel</button>
          <button className="btn primary" disabled={!valid || busy} onClick={submit}>{busy && <Spinner small />} Create company</button>
        </>
      }
    >
      <div className="stack">
        {error && <Alert kind="error">{error}</Alert>}
        <div className="form-grid">
          <Field label="Company name"><input className="input" value={form.name} onChange={set('name')} placeholder="Acme Infra Pvt Ltd" autoFocus /></Field>
          <Field label="Industry" hint="optional"><input className="input" value={form.industry} onChange={set('industry')} placeholder="Construction" /></Field>
          <Field label="Admin email"><input className="input" type="email" value={form.adminEmail} onChange={set('adminEmail')} placeholder="admin@customer.com" /></Field>
          <Field label="Admin password" hint="min 8 characters"><input className="input" type="text" value={form.adminPassword} onChange={set('adminPassword')} placeholder="Temporary password" /></Field>
          <Field label="Plan">
            <select className="select" value={form.planCode} onChange={set('planCode')}>
              <option value="">{plans.loading ? 'Loading plans…' : 'Select a plan'}</option>
              {plans.data?.map((p) => (
                <option key={p.id} value={p.code}>{p.name} — {money(p.monthlyPriceInr)}/mo · {p.maxEmployees ? `${p.maxEmployees} seats max` : 'unlimited'}</option>
              ))}
            </select>
          </Field>
          <Field label="Seats" hint={plan?.maxEmployees ? `max ${plan.maxEmployees}` : undefined}>
            <input className="input" type="number" min={1} value={form.seats} onChange={set('seats')} />
          </Field>
          <Field label="Subscription length" hint="days">
            <input className="input" type="number" min={1} value={form.subscriptionDays} onChange={set('subscriptionDays')} />
          </Field>
        </div>
        {plans.error && <Alert kind="error">Couldn't load plans: {plans.error}</Alert>}
      </div>
    </Modal>
  )
}

function ExtendDialog({ company, onClose }: { company: Company; onClose: () => void }) {
  const toast = useToast()
  const [days, setDays] = useState('30')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function submit() {
    setBusy(true)
    setError(null)
    try {
      const res = await api<{ endsAt: string }>(`/super/companies/${company.id}/subscription/extend`, { method: 'POST', body: { days: Number(days) } })
      toast(`Subscription extended to ${date(res.endsAt)}`)
      onClose()
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not extend subscription')
    } finally {
      setBusy(false)
    }
  }

  return (
    <Modal
      title={`Extend ${company.name}`}
      subtitle="Adds days to the current subscription end date (or from today if already expired)."
      onClose={onClose}
      footer={
        <>
          <button className="btn" onClick={onClose}>Cancel</button>
          <button className="btn primary" disabled={!(Number(days) > 0) || busy} onClick={submit}>{busy && <Spinner small />} Extend</button>
        </>
      }
    >
      <div className="stack">
        {error && <Alert kind="error">{error}</Alert>}
        <div className="row wrap">
          {[30, 90, 180, 365].map((d) => (
            <button key={d} className={`btn sm ${days === String(d) ? 'primary' : ''}`} onClick={() => setDays(String(d))}>{d} days</button>
          ))}
        </div>
        <Field label="Custom days"><input className="input" type="number" min={1} value={days} onChange={(e) => setDays(e.target.value)} /></Field>
      </div>
    </Modal>
  )
}
