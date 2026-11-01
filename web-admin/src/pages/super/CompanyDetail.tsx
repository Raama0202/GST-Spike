import { useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import { Activity, ArrowLeft, CalendarPlus, FileText, KeyRound, Pause, Pencil, Play, Receipt, Repeat, Trash2, Users } from 'lucide-react'
import { api, ApiError } from '../../api/client'
import type { CompanyDetail as CompanyDetailData } from '../../api/types'
import { Badge, Card, Empty, ErrorState, Loading, PageHeader, Stat, useAsync, useToast } from '../../components/ui'
import { date, money, PAYMENT_LABELS } from '../../lib/format'
import { CopyCode, EndsCell, ExtendDialog, StatusConfirm, statusAction } from './companyDialogs'
import { DeleteTenantDialog, EditCompanyDialog, ResetPasswordDialog, SubscriptionDialog } from './CompanyDetailParts'

type Dialog =
  | { kind: 'edit' }
  | { kind: 'subscription' }
  | { kind: 'extend' }
  | { kind: 'status' }
  | { kind: 'reset'; admin: { id: string; email: string } }
  | { kind: 'delete' }

export default function CompanyDetail() {
  const { id = '' } = useParams()
  const toast = useToast()
  const { data, error, loading, reload, setData } = useAsync(() => api<CompanyDetailData>(`/super/companies/${id}`), [id])
  const [dialog, setDialog] = useState<Dialog | null>(null)
  const [busy, setBusy] = useState(false)

  if (loading && (!data || data.company.id !== id)) return <><PageHeader title="Company" /><Card><Loading /></Card></>
  if (error || !data) {
    return (
      <>
        <PageHeader title="Company" actions={<Link to="/super/companies" className="btn ghost"><ArrowLeft size={16} /> All companies</Link>} />
        <Card><ErrorState message={error ?? 'Company not found'} onRetry={reload} /></Card>
      </>
    )
  }

  const { company, subscription, usage, admins, payments } = data
  const action = statusAction(company.status)

  async function runStatus() {
    if (!action) return
    setBusy(true)
    try {
      await api(`/super/companies/${company.id}/${action}`, { method: 'POST' })
      toast(`${company.name} ${action === 'suspend' ? 'suspended' : 'reactivated'}`)
      setDialog(null)
      await reload()
    } catch (e) {
      toast(e instanceof Error ? e.message : 'Action failed', 'error')
      if (e instanceof ApiError && e.status === 409) await reload()
    } finally {
      setBusy(false)
    }
  }

  return (
    <>
      <PageHeader
        title={company.name}
        subtitle={<span className="row wrap" style={{ gap: 8 }}><Badge status={company.status} /> <span>Created {date(company.createdAt)}</span> <CopyCode code={company.activationCode} /></span>}
        actions={
          <>
            <Link to="/super/companies" className="btn ghost"><ArrowLeft size={16} /> All companies</Link>
            <Link to={`/super/activity?companyId=${company.id}&companyName=${encodeURIComponent(company.name)}`} className="btn"><Activity size={16} /> Activity</Link>
            {action === 'suspend' && <button className="btn danger" onClick={() => setDialog({ kind: 'status' })}><Pause size={16} /> Suspend</button>}
            {action === 'reactivate' && <button className="btn success" onClick={() => setDialog({ kind: 'status' })}><Play size={16} /> Reactivate</button>}
          </>
        }
      />

      <div className="stack">
        <div className="grid cols-4">
          <Stat icon={<Users size={20} />} label="Active employees" value={`${usage.activeEmployees}${subscription ? ` / ${subscription.seats}` : ''}`} tone="#34d399" />
          <Stat icon={<FileText size={20} />} label="Invoices (30 days)" value={usage.invoices30d} tone="#7c9cff" />
          <Stat icon={<Receipt size={20} />} label="Pending review" value={usage.pendingInvoices} tone="#fbbf24" />
          <Stat icon={<Activity size={20} />} label="Last activity" value={usage.lastActivityAt ? date(usage.lastActivityAt) : 'Never'} tone="#a78bfa" />
        </div>

        <div className="grid cols-2">
          <Card title="Company details" actions={<button className="btn sm" onClick={() => setDialog({ kind: 'edit' })}><Pencil size={14} /> Edit</button>}>
            <dl className="kv">
              <dt>Display name</dt><dd>{company.name}</dd>
              <dt>Legal name</dt><dd>{company.legalName || '—'}</dd>
              <dt>GSTIN</dt><dd className="mono">{company.gstin || '—'}</dd>
              <dt>Industry</dt><dd>{company.industry || '—'}</dd>
              <dt>Employees</dt><dd>{usage.employees} total · {usage.activeEmployees} active</dd>
              <dt>Invoices</dt><dd>{usage.invoices} all time</dd>
            </dl>
          </Card>

          <Card
            title="Subscription"
            actions={
              <div className="actions">
                <button className="btn sm" onClick={() => setDialog({ kind: 'extend' })}><CalendarPlus size={14} /> Extend</button>
                <button className="btn sm" onClick={() => setDialog({ kind: 'subscription' })}><Repeat size={14} /> Change</button>
              </div>
            }
          >
            {subscription ? (
              <dl className="kv">
                <dt>Plan</dt><dd>{subscription.planName ?? subscription.planCode}</dd>
                <dt>Seats</dt><dd>{subscription.seats} ({usage.activeEmployees} in use)</dd>
                <dt>Status</dt><dd><Badge status={subscription.status} /></dd>
                <dt>Started</dt><dd>{date(subscription.startsAt)}</dd>
                <dt>Ends</dt><dd><EndsCell endsAt={subscription.endsAt} /></dd>
              </dl>
            ) : (
              <Empty title="No subscription" message="Use Change to assign a plan and end date." />
            )}
          </Card>
        </div>

        <div className="grid cols-2">
          <Card title="Company admins" subtitle="Resetting a password signs that admin out everywhere.">
            {admins.length === 0 ? <Empty title="No admins" /> : admins.map((a) => (
              <div key={a.id} className="list-item">
                <div className="dot-icon"><Users size={16} /></div>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div className="cell-title">{a.name || a.email}</div>
                  <div className="cell-sub">{a.name ? `${a.email} · ` : ''}added {date(a.createdAt)}{a.isActive ? '' : ' · inactive'}</div>
                </div>
                <button className="btn sm" onClick={() => setDialog({ kind: 'reset', admin: a })}><KeyRound size={14} /> Reset password</button>
              </div>
            ))}
          </Card>

          <Card title="Recent payments" actions={<Link to={`/super/payments?companyId=${company.id}&companyName=${encodeURIComponent(company.name)}`} className="btn sm ghost">All payments →</Link>}>
            {payments.length === 0 ? <Empty icon={<Receipt size={24} />} title="No payments yet" /> : payments.map((o) => (
              <div key={o.id} className="list-item">
                <div className="dot-icon"><Receipt size={16} /></div>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div className="row between">
                    <div className="cell-title">{money(o.amount)}</div>
                    <Badge status={o.status} label={PAYMENT_LABELS[o.status] ?? o.status} />
                  </div>
                  <div className="cell-sub">{o.planCode} · {o.seats} seats · {o.months} mo · {date(o.paidAt ?? o.createdAt, true)}</div>
                  {o.failureReason && <div className="cell-sub" style={{ color: '#fca5a5' }}>{o.failureReason}</div>}
                </div>
              </div>
            ))}
          </Card>
        </div>

        <Card title="Danger zone" className="danger-card">
          <div className="row wrap between">
            <div className="muted" style={{ maxWidth: 560 }}>
              Permanently delete this company and all of its users, invoices, images and settings. Suspend instead if you only need to block access.
            </div>
            <button className="btn danger" onClick={() => setDialog({ kind: 'delete' })}><Trash2 size={16} /> Delete company</button>
          </div>
        </Card>
      </div>

      {dialog?.kind === 'edit' && (
        <EditCompanyDialog company={company} onClose={() => setDialog(null)} onSaved={(c) => setData({ ...data, company: { ...company, ...c } })} />
      )}
      {dialog?.kind === 'subscription' && (
        <SubscriptionDialog companyId={company.id} subscription={subscription} activeEmployees={usage.activeEmployees} onClose={() => setDialog(null)} onSaved={reload} />
      )}
      {dialog?.kind === 'extend' && (
        <ExtendDialog company={company} endsAt={subscription?.endsAt ?? null} onClose={() => setDialog(null)} onDone={() => void reload()} />
      )}
      {dialog?.kind === 'status' && action && (
        <StatusConfirm company={company} action={action} busy={busy} onConfirm={runStatus} onClose={() => setDialog(null)} />
      )}
      {dialog?.kind === 'reset' && <ResetPasswordDialog companyId={company.id} admin={dialog.admin} onClose={() => setDialog(null)} />}
      {dialog?.kind === 'delete' && <DeleteTenantDialog company={company} onClose={() => setDialog(null)} />}
    </>
  )
}
