import { Link, useSearchParams } from 'react-router-dom'
import { Building2, CreditCard, FileText, History, Megaphone, Settings, Tags, UserCog, Users } from 'lucide-react'
import type { ReactNode } from 'react'
import { api } from '../api/client'
import type { AuditEntry, Page } from '../api/types'
import { AsyncPicker } from '../components/Picker'
import { Card, Empty, ErrorState, Loading, PageHeader, Pagination, useAsync, usePaged } from '../components/ui'
import { date, relative } from '../lib/format'
import { searchCompanies } from '../lib/lookups'

type Scope = 'company' | 'super'

const PAGE_SIZE = 50

const COMPANY_ACTIONS: [string, [string, string][]][] = [
  ['Invoices', [
    ['invoice.approved', 'Invoice approved'], ['invoice.rejected', 'Invoice rejected'], ['invoice.returned', 'Invoice returned'],
    ['invoice.edited', 'Invoice edited'], ['invoice.bulk_decision', 'Bulk decision'],
  ]],
  ['Employees', [['employee.created', 'Employee added'], ['employee.updated', 'Employee updated'], ['employee.deactivated', 'Employee deactivated']]],
  ['Company', [
    ['settings.updated', 'Settings updated'], ['announcement.sent', 'Announcement sent'],
    ['branch.created', 'Branch added'], ['branch.updated', 'Branch updated'], ['branch.deactivated', 'Branch deactivated'],
    ['category.created', 'Category added'], ['category.updated', 'Category updated'], ['category.deactivated', 'Category deactivated'],
  ]],
  ['Billing', [['billing.paid', 'Payment received'], ['subscription.extended', 'Subscription extended'], ['subscription.changed', 'Subscription changed']]],
]

const SUPER_ACTIONS: [string, [string, string][]][] = [
  ['Tenants', [
    ['company.created', 'Company created'], ['company.updated', 'Company updated'], ['company.suspended', 'Company suspended'],
    ['company.reactivated', 'Company reactivated'], ['company.deleted', 'Company deleted'], ['admin.password_reset', 'Admin password reset'],
  ]],
  ['Plans', [['plan.created', 'Plan created'], ['plan.updated', 'Plan updated'], ['plan.deleted', 'Plan deleted']]],
  ...COMPANY_ACTIONS,
]

const LABELS = Object.fromEntries([...SUPER_ACTIONS.flatMap(([, items]) => items)])

const ICONS: Record<string, ReactNode> = {
  invoice: <FileText size={16} />,
  employee: <Users size={16} />,
  settings: <Settings size={16} />,
  branch: <Building2 size={16} />,
  category: <Tags size={16} />,
  announcement: <Megaphone size={16} />,
  billing: <CreditCard size={16} />,
  subscription: <CreditCard size={16} />,
  company: <Building2 size={16} />,
  admin: <UserCog size={16} />,
  plan: <Tags size={16} />,
}

function actionLabel(action: string) {
  return LABELS[action] ?? action.replace(/[._]/g, ' ').replace(/^\w/, (c) => c.toUpperCase())
}

export default function AuditLog({ scope }: { scope: Scope }) {
  const [params, setParams] = useSearchParams()
  const action = params.get('action') ?? ''
  const companyId = scope === 'super' ? params.get('companyId') ?? '' : ''
  const [page, setPage] = usePaged(`${action}|${companyId}`)
  const { data, error, loading, reload } = useAsync(
    () => api<Page<AuditEntry>>(scope === 'super' ? '/super/audit' : '/admin/audit', {
      query: { page, pageSize: PAGE_SIZE, action: action || undefined, companyId: companyId || undefined },
    }),
    [scope, action, companyId, page],
  )
  const groups = scope === 'super' ? SUPER_ACTIONS : COMPANY_ACTIONS
  const filtered = Boolean(action || companyId)

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

  function target(e: AuditEntry) {
    if (scope === 'company' && e.targetType === 'invoice' && e.targetId) {
      return <Link className="linkish" to={`/invoices/${e.targetId}`}>Open invoice</Link>
    }
    if (scope === 'super' && e.targetType === 'company' && e.targetId && e.action !== 'company.deleted') {
      return <Link className="linkish" to={`/super/companies/${e.targetId}`}>Open company</Link>
    }
    return null
  }

  return (
    <>
      <PageHeader
        title="Activity log"
        subtitle={scope === 'super'
          ? 'Every administrative change across tenants and the platform, newest first.'
          : 'Who changed what in your company: invoice decisions, employees, settings and billing.'}
      />
      <Card>
        <div className="filters" style={{ marginBottom: 16 }}>
          <select className="select" aria-label="Action" value={action} onChange={(e) => update({ action: e.target.value })}>
            <option value="">All actions</option>
            {groups.map(([group, items]) => (
              <optgroup key={group} label={group}>
                {items.map(([value, label]) => <option key={value} value={value}>{label}</option>)}
              </optgroup>
            ))}
          </select>
          {scope === 'super' && (
            <AsyncPicker
              value={companyId}
              valueLabel={params.get('companyName')}
              onChange={(id, label) => update({ companyId: id, companyName: id ? label : '' })}
              search={searchCompanies}
              allLabel="All companies"
              ariaLabel="Company"
              width={240}
            />
          )}
          {filtered && <button className="btn sm ghost" onClick={() => setParams({}, { replace: true })}>Clear filters</button>}
        </div>

        {loading && !data ? <Loading /> : error ? <ErrorState message={error} onRetry={reload} /> : !data?.items.length ? (
          <Empty
            icon={<History size={24} />}
            title={filtered ? 'No matching activity' : 'No activity yet'}
            message={filtered ? 'Try a different action or company.' : 'Changes made by admins will be recorded here.'}
          />
        ) : (
          data.items.map((e) => (
            <div key={e.id} className="list-item">
              <div className="dot-icon">{ICONS[e.action.split('.')[0]] ?? <History size={16} />}</div>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div className="row between" style={{ alignItems: 'flex-start' }}>
                  <div className="cell-title">{e.summary || actionLabel(e.action)}</div>
                  <span className="faint nowrap" style={{ fontSize: 12.5 }} title={date(e.createdAt, true)}>{relative(e.createdAt)}</span>
                </div>
                <div className="cell-sub row wrap" style={{ gap: 6, marginTop: 2 }}>
                  <span className="badge gray" style={{ textTransform: 'none' }}>{actionLabel(e.action)}</span>
                  <span>
                    by {e.actorEmail ?? 'system'}{e.actorRole ? ` (${e.actorRole.replace(/_/g, ' ')})` : ''}
                  </span>
                  {scope === 'super' && e.companyName && (
                    <>
                      <span aria-hidden>·</span>
                      {e.companyId
                        ? <Link className="linkish" to={`/super/companies/${e.companyId}`}>{e.companyName}</Link>
                        : <span>{e.companyName}</span>}
                    </>
                  )}
                  {target(e) && <><span aria-hidden>·</span>{target(e)}</>}
                </div>
              </div>
            </div>
          ))
        )}
        {data && <Pagination page={page} pageSize={PAGE_SIZE} total={data.total} onPage={setPage} />}
      </Card>
    </>
  )
}
