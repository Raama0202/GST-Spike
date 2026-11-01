import { useState } from 'react'
import { Link } from 'react-router-dom'
import { Pencil, Plus, Receipt, Search, UserCheck, UserX, Users } from 'lucide-react'
import { api } from '../../api/client'
import type { Employee, EmployeesPage, NamedResource } from '../../api/types'
import {
  Alert, Badge, Card, Confirm, Empty, ErrorState, Field, Loading, Modal, PageHeader, Pagination, Spinner, Toggle, useAsync, useDebounced, usePaged, useToast,
} from '../../components/ui'
import { initials } from '../../lib/format'
import { loadBranches } from '../../lib/lookups'
import { cleanMobile, isEmail, isMobile } from '../../lib/validation'

const PAGE_SIZE = 50
type ActiveFilter = 'all' | 'active' | 'inactive'

export default function Employees() {
  const toast = useToast()
  const [query, setQuery] = useState('')
  const [active, setActive] = useState<ActiveFilter>('all')
  const [branchId, setBranchId] = useState('')
  const search = useDebounced(query.trim())
  const filterKey = `${search}|${active}|${branchId}`
  const [page, setPage] = usePaged(filterKey)

  const branches = useAsync(loadBranches)
  const { data, error, loading, reload } = useAsync(
    () => api<EmployeesPage>('/admin/employees', {
      query: {
        page,
        pageSize: PAGE_SIZE,
        q: search || undefined,
        active: active === 'all' ? undefined : active === 'active',
        branchId: branchId || undefined,
      },
    }),
    [filterKey, page],
  )
  const [editing, setEditing] = useState<Employee | 'new' | null>(null)
  const [toggling, setToggling] = useState<Employee | null>(null)
  const [busy, setBusy] = useState(false)

  const list = data?.items ?? []
  const seats = data?.seats
  const full = seats?.limit != null && seats.used >= seats.limit

  async function toggleActive() {
    if (!toggling) return
    setBusy(true)
    try {
      if (toggling.isActive) await api(`/admin/employees/${toggling.id}`, { method: 'DELETE' })
      else await api(`/admin/employees/${toggling.id}`, { method: 'PATCH', body: { isActive: true } })
      toast(`${toggling.name} ${toggling.isActive ? 'deactivated' : 'reactivated'}`)
      setToggling(null)
      await reload()
    } catch (e) {
      toast(e instanceof Error ? e.message : 'Action failed', 'error')
    } finally {
      setBusy(false)
    }
  }

  const subtitle = seats
    ? `${seats.used} of ${seats.limit ?? 'unlimited'} seats used · employees sign in with their mobile number; the one-time code goes to their email.`
    : 'Manage who can submit bills. Employees sign in with their mobile number.'

  return (
    <>
      <PageHeader
        title="Employees"
        subtitle={subtitle}
        actions={<button className="btn primary" onClick={() => setEditing('new')} disabled={full} title={full ? 'All seats are in use' : undefined}><Plus size={16} /> Add employee</button>}
      />
      {full && (
        <div style={{ marginBottom: 18 }}>
          <Alert kind="info">All {seats?.limit} seats are in use. <Link to="/billing">Add seats on the Billing page</Link> or deactivate someone to add a new employee.</Alert>
        </div>
      )}
      <Card>
        <div className="filters" style={{ marginBottom: 16 }}>
          <div className="input-icon" style={{ width: 300 }}>
            <Search size={16} />
            <input className="input" placeholder="Search name, mobile, email or code" value={query} onChange={(e) => setQuery(e.target.value)} aria-label="Search employees" />
          </div>
          <div className="segmented" role="group" aria-label="Status">
            {(['all', 'active', 'inactive'] as ActiveFilter[]).map((f) => (
              <button key={f} className={active === f ? 'on' : ''} aria-pressed={active === f} onClick={() => setActive(f)}>
                {f === 'all' ? 'All' : f === 'active' ? 'Active' : 'Inactive'}
              </button>
            ))}
          </div>
          <select className="select" value={branchId} onChange={(e) => setBranchId(e.target.value)} aria-label="Branch">
            <option value="">All branches</option>
            {branches.data?.map((b) => <option key={b.id} value={b.id}>{b.name}{b.isActive ? '' : ' (archived)'}</option>)}
          </select>
        </div>
        {loading && !data ? <Loading /> : error ? <ErrorState message={error} onRetry={reload} /> : list.length === 0 ? (
          <Empty
            icon={<Users size={24} />}
            title={search || active !== 'all' || branchId ? 'No employees match' : 'No employees yet'}
            message={search || active !== 'all' || branchId ? 'Try a different search or filter.' : 'Add employees so they can sign in to the Android and iOS apps.'}
          />
        ) : (
          <div className="table-wrap">
            <table className="table">
              <thead><tr><th>Employee</th><th>Email</th><th>Mobile</th><th>Code</th><th>Branch</th><th>Status</th><th className="right">Actions</th></tr></thead>
              <tbody>
                {list.map((e) => (
                  <tr key={e.id}>
                    <td>
                      <div className="row">
                        <div className="avatar" aria-hidden>{initials(e.name)}</div>
                        <div className="cell-title">{e.name}</div>
                      </div>
                    </td>
                    <td>{e.email || <span style={{ fontSize: 12.5, color: 'var(--warning)' }}>Add an email for login codes</span>}</td>
                    <td className="mono">{e.mobile}</td>
                    <td className="mono">{e.employeeCode}</td>
                    <td>{e.branchName || <span className="faint">—</span>}</td>
                    <td><Badge status={e.isActive ? 'active' : 'inactive'} label={e.isActive ? 'Active' : 'Inactive'} /></td>
                    <td className="right">
                      <div className="actions" style={{ justifyContent: 'flex-end', flexWrap: 'nowrap' }}>
                        <Link className="btn sm icon" title="View invoices" aria-label={`Invoices by ${e.name}`} to={`/invoices?employeeId=${e.id}&employeeName=${encodeURIComponent(e.name)}`}><Receipt size={14} /></Link>
                        <button className="btn sm icon" title="Edit" aria-label={`Edit ${e.name}`} onClick={() => setEditing(e)}><Pencil size={14} /></button>
                        {e.isActive ? (
                          <button className="btn sm danger" onClick={() => setToggling(e)}><UserX size={14} /> Deactivate</button>
                        ) : (
                          <button className="btn sm success" onClick={() => setToggling(e)} disabled={full} title={full ? 'No free seat' : undefined}><UserCheck size={14} /> Reactivate</button>
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

      {editing && (
        <EmployeeEditor employee={editing === 'new' ? null : editing} branches={branches.data ?? []} onClose={() => setEditing(null)} onSaved={reload} />
      )}
      {toggling && (
        <Confirm
          title={toggling.isActive ? `Deactivate ${toggling.name}?` : `Reactivate ${toggling.name}?`}
          message={toggling.isActive
            ? 'They will be signed out of the mobile apps and can no longer submit bills. Their past invoices are kept and the seat is freed.'
            : 'They will be able to sign in again with their mobile number. This uses one seat.'}
          confirmLabel={toggling.isActive ? 'Deactivate' : 'Reactivate'}
          danger={toggling.isActive}
          busy={busy}
          onConfirm={toggleActive}
          onClose={() => setToggling(null)}
        />
      )}
    </>
  )
}

function EmployeeEditor({ employee, branches, onClose, onSaved }: {
  employee: Employee | null
  branches: NamedResource[]
  onClose: () => void
  onSaved: () => void
}) {
  const toast = useToast()
  const initial = {
    name: employee?.name ?? '',
    mobile: employee?.mobile ?? '',
    email: employee?.email ?? '',
    code: employee?.employeeCode ?? '',
    branchId: employee?.branchId ?? '',
    isActive: employee?.isActive ?? true,
  }
  const [form, setForm] = useState(initial)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const set = <K extends keyof typeof form>(key: K, value: (typeof form)[K]) => setForm((f) => ({ ...f, [key]: value }))

  const mobileValid = isMobile(form.mobile)
  const emailValid = !form.email.trim() || isEmail(form.email)
  const valid = form.name.trim() && mobileValid && emailValid && form.code.trim()
  const dirty = JSON.stringify(form) !== JSON.stringify(initial)

  async function save() {
    setBusy(true)
    setError(null)
    const body = {
      name: form.name.trim(),
      mobile: cleanMobile(form.mobile),
      email: form.email.trim().toLowerCase() || null,
      employeeCode: form.code.trim(),
      branchId: form.branchId || null,
      isActive: form.isActive,
    }
    try {
      if (employee) await api(`/admin/employees/${employee.id}`, { method: 'PATCH', body })
      else await api('/admin/employees', { method: 'POST', body })
      toast(employee ? 'Employee updated' : 'Employee added — they can now sign in with OTP')
      onSaved()
      onClose()
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not save employee')
      setBusy(false)
    }
  }

  return (
    <Modal
      title={employee ? `Edit ${employee.name}` : 'Add employee'}
      onClose={onClose}
      busy={busy}
      dirty={dirty}
      footer={
        <>
          <button className="btn" onClick={onClose} disabled={busy}>Cancel</button>
          <button className="btn primary" disabled={!valid || busy || !dirty} onClick={save}>{busy && <Spinner small />} Save</button>
        </>
      }
    >
      <div className="stack">
        {error && <Alert kind="error">{error}</Alert>}
        <div className="form-grid">
          <Field label="Full name" full><input className="input" value={form.name} onChange={(e) => set('name', e.target.value)} autoFocus /></Field>
          <Field label="Mobile number" hint="10 digits, +91 optional">
            <input className="input mono" value={form.mobile} onChange={(e) => set('mobile', e.target.value)} placeholder="98765 43210" inputMode="tel" aria-invalid={Boolean(form.mobile) && !mobileValid} />
          </Field>
          <Field label="Employee code"><input className="input mono" value={form.code} onChange={(e) => set('code', e.target.value)} placeholder="EMP002" /></Field>
          <Field label="Email" hint="login codes are sent here" full>
            <input className="input" type="email" value={form.email} onChange={(e) => set('email', e.target.value)} placeholder="ravi@company.com" aria-invalid={!emailValid} />
          </Field>
          <Field label="Branch" full>
            <select className="select" value={form.branchId} onChange={(e) => set('branchId', e.target.value)}>
              <option value="">No branch</option>
              {branches.filter((b) => b.isActive || b.id === form.branchId).map((b) => <option key={b.id} value={b.id}>{b.name}{b.code ? ` (${b.code})` : ''}</option>)}
            </select>
          </Field>
        </div>
        {form.mobile && !mobileValid && <Alert kind="error">Enter a valid mobile number: 10 digits, optionally starting with +91.</Alert>}
        {!emailValid && <Alert kind="error">Enter a valid email address.</Alert>}
        <Toggle checked={form.isActive} onChange={(v) => set('isActive', v)} label="Active" description="Inactive employees cannot sign in to the apps and don't use a seat" />
      </div>
    </Modal>
  )
}
