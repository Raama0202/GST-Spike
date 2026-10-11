import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { Pencil, Plus, Receipt, Search, UserCheck, UserX, Users } from 'lucide-react'
import { api } from '../../api/client'
import type { Employee, Items, NamedResource, Page } from '../../api/types'
import {
  Alert, Badge, Card, Confirm, Empty, ErrorState, Field, Loading, Modal, PageHeader, Pagination, Spinner, Toggle, useAsync, useDebounced, useToast,
} from '../../components/ui'
import { initials } from '../../lib/format'

const PAGE_SIZE = 50

export default function Employees() {
  const toast = useToast()
  const [query, setQuery] = useState('')
  const [page, setPage] = useState(1)
  const search = useDebounced(query.trim())
  const { data, error, loading, reload } = useAsync(async () => {
    const [employees, branches, activeCount] = await Promise.all([
      api<Page<Employee>>('/admin/employees', { query: { page, pageSize: PAGE_SIZE, q: search || undefined } }),
      api<Items<NamedResource>>('/admin/company/branches'),
      api<Page<Employee>>('/admin/employees', { query: { active: true, pageSize: 1 } }),
    ])
    return { employees: employees.items, total: employees.total, branches: branches.items, active: activeCount.total }
  }, [page, search])
  const [editing, setEditing] = useState<Employee | 'new' | null>(null)
  const [toggling, setToggling] = useState<Employee | null>(null)
  const [busy, setBusy] = useState(false)

  useEffect(() => setPage(1), [search])

  const list = data?.employees ?? []

  async function toggleActive() {
    if (!toggling) return
    setBusy(true)
    try {
      if (toggling.isActive) await api(`/admin/employees/${toggling.id}`, { method: 'DELETE' })
      else await api(`/admin/employees/${toggling.id}`, { method: 'PATCH', body: { isActive: true } })
      toast(`${toggling.name} ${toggling.isActive ? 'disabled' : 'enabled'}`)
      setToggling(null)
      await reload()
    } catch (e) {
      toast(e instanceof Error ? e.message : 'Action failed', 'error')
    } finally {
      setBusy(false)
    }
  }

  const active = data?.active ?? 0

  return (
    <>
      <PageHeader
        title="Employees"
        subtitle={data ? `${active} active of ${search ? 'all' : data.total} · employees sign in to the mobile apps with their mobile number and OTP.` : 'Manage who can submit bills.'}
        actions={<button className="btn primary" onClick={() => setEditing('new')}><Plus size={16} /> Add employee</button>}
      />
      <Card>
        <div className="row between" style={{ marginBottom: 16 }}>
          <div className="input-icon" style={{ width: 320 }}>
            <Search size={16} />
            <input className="input" placeholder="Search name, mobile or code" value={query} onChange={(e) => setQuery(e.target.value)} />
          </div>
        </div>
        {loading && !data ? <Loading /> : error ? <ErrorState message={error} onRetry={reload} /> : list.length === 0 ? (
          <Empty icon={<Users size={24} />} title={search ? 'No employees match' : 'No employees yet'} message="Add employees so they can sign in to the Android and iOS apps." />
        ) : (
          <div className="table-wrap">
            <table className="table">
              <thead><tr><th>Employee</th><th>Mobile</th><th>Code</th><th>Branch</th><th>Status</th><th className="right">Actions</th></tr></thead>
              <tbody>
                {list.map((e) => (
                  <tr key={e.id}>
                    <td>
                      <div className="row">
                        <div className="avatar">{initials(e.name)}</div>
                        <div className="cell-title">{e.name}</div>
                      </div>
                    </td>
                    <td className="mono">{e.mobile}</td>
                    <td className="mono">{e.employeeCode}</td>
                    <td>{e.branchName || <span className="faint">—</span>}</td>
                    <td><Badge status={e.isActive ? 'active' : 'inactive'} label={e.isActive ? 'Active' : 'Disabled'} /></td>
                    <td className="right">
                      <div className="actions" style={{ justifyContent: 'flex-end' }}>
                        <Link className="btn sm icon" title="View invoices" aria-label={`Invoices by ${e.name}`} to={`/invoices?employeeId=${e.id}`}><Receipt size={14} /></Link>
                        <button className="btn sm icon" title="Edit" aria-label={`Edit ${e.name}`} onClick={() => setEditing(e)}><Pencil size={14} /></button>
                        {e.isActive ? (
                          <button className="btn sm danger" onClick={() => setToggling(e)}><UserX size={14} /> Disable</button>
                        ) : (
                          <button className="btn sm success" onClick={() => setToggling(e)}><UserCheck size={14} /> Enable</button>
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

      {editing && data && (
        <EmployeeEditor employee={editing === 'new' ? null : editing} branches={data.branches} onClose={() => setEditing(null)} onSaved={reload} />
      )}
      {toggling && (
        <Confirm
          title={toggling.isActive ? `Disable ${toggling.name}?` : `Enable ${toggling.name}?`}
          message={toggling.isActive
            ? 'They will be signed out of the mobile apps and can no longer submit bills. Their past invoices are kept.'
            : 'They will be able to sign in again with their mobile number.'}
          confirmLabel={toggling.isActive ? 'Disable' : 'Enable'}
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
  const [name, setName] = useState(employee?.name ?? '')
  const [mobile, setMobile] = useState(employee?.mobile ?? '')
  const [code, setCode] = useState(employee?.employeeCode ?? '')
  const [branchId, setBranchId] = useState(employee?.branchId ?? '')
  const [isActive, setIsActive] = useState(employee?.isActive ?? true)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const mobileValid = /^\+?[0-9]{10,15}$/.test(mobile.trim())
  const valid = name.trim() && mobileValid && code.trim()

  async function save() {
    setBusy(true)
    setError(null)
    const body = { name: name.trim(), mobile: mobile.trim(), employeeCode: code.trim(), branchId: branchId || null, isActive }
    try {
      if (employee) await api(`/admin/employees/${employee.id}`, { method: 'PATCH', body })
      else await api('/admin/employees', { method: 'POST', body })
      toast(employee ? 'Employee updated' : 'Employee added — they can now sign in with OTP')
      onSaved()
      onClose()
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not save employee')
    } finally {
      setBusy(false)
    }
  }

  return (
    <Modal
      title={employee ? `Edit ${employee.name}` : 'Add employee'}
      onClose={onClose}
      footer={
        <>
          <button className="btn" onClick={onClose}>Cancel</button>
          <button className="btn primary" disabled={!valid || busy} onClick={save}>{busy && <Spinner small />} Save</button>
        </>
      }
    >
      <div className="stack">
        {error && <Alert kind="error">{error}</Alert>}
        <div className="form-grid">
          <Field label="Full name" full><input className="input" value={name} onChange={(e) => setName(e.target.value)} autoFocus /></Field>
          <Field label="Mobile number" hint="10–15 digits">
            <input className="input mono" value={mobile} onChange={(e) => setMobile(e.target.value)} placeholder="9876543210" />
          </Field>
          <Field label="Employee code"><input className="input mono" value={code} onChange={(e) => setCode(e.target.value)} placeholder="EMP002" /></Field>
          <Field label="Branch" full>
            <select className="select" value={branchId} onChange={(e) => setBranchId(e.target.value)}>
              <option value="">No branch</option>
              {branches.filter((b) => b.isActive || b.id === branchId).map((b) => <option key={b.id} value={b.id}>{b.name}{b.code ? ` (${b.code})` : ''}</option>)}
            </select>
          </Field>
        </div>
        {mobile && !mobileValid && <Alert kind="error">Enter a valid mobile number (digits only, optional leading +).</Alert>}
        <Toggle checked={isActive} onChange={setIsActive} label="Active" description="Inactive employees cannot sign in to the apps" />
      </div>
    </Modal>
  )
}
