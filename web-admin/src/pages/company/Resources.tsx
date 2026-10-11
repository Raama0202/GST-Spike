import { useState } from 'react'
import { Archive, FolderTree, MapPin, Pencil, Plus, RotateCcw } from 'lucide-react'
import { api } from '../../api/client'
import type { Items, NamedResource } from '../../api/types'
import {
  Alert, Badge, Card, Confirm, Empty, ErrorState, Field, Loading, Modal, PageHeader, Spinner, Toggle, useAsync, useToast,
} from '../../components/ui'

interface Config {
  path: string
  title: string
  singular: string
  subtitle: string
  icon: typeof FolderTree
  withCode: boolean
  withOrder: boolean
}

const CATEGORY: Config = {
  path: '/admin/company/categories',
  title: 'Expense categories',
  singular: 'category',
  subtitle: 'Categories employees choose when submitting a bill. Changes reach the mobile apps on next sync.',
  icon: FolderTree,
  withCode: false,
  withOrder: true,
}

const BRANCH: Config = {
  path: '/admin/company/branches',
  title: 'Branches',
  singular: 'branch',
  subtitle: 'Sites and offices employees are assigned to. Used for filtering invoices.',
  icon: MapPin,
  withCode: true,
  withOrder: false,
}

export const Categories = () => <ResourcePage config={CATEGORY} />
export const Branches = () => <ResourcePage config={BRANCH} />

function ResourcePage({ config }: { config: Config }) {
  const toast = useToast()
  const { data, error, loading, reload } = useAsync(
    () => api<Items<NamedResource>>(config.path).then((r) => [...r.items].sort((a, b) => a.sortOrder - b.sortOrder || a.name.localeCompare(b.name))),
    [config.path],
  )
  const [editing, setEditing] = useState<NamedResource | 'new' | null>(null)
  const [archiving, setArchiving] = useState<NamedResource | null>(null)
  const [busy, setBusy] = useState(false)
  const Icon = config.icon

  async function archive() {
    if (!archiving) return
    setBusy(true)
    try {
      await api(`${config.path}/${archiving.id}`, { method: 'DELETE' })
      toast(`${archiving.name} archived`)
      setArchiving(null)
      await reload()
    } catch (e) {
      toast(e instanceof Error ? e.message : 'Action failed', 'error')
    } finally {
      setBusy(false)
    }
  }

  async function restore(item: NamedResource) {
    try {
      await api(`${config.path}/${item.id}`, { method: 'PATCH', body: { name: item.name, code: item.code, parentId: item.parentId, sortOrder: item.sortOrder, isActive: true } })
      toast(`${item.name} restored`)
      await reload()
    } catch (e) {
      toast(e instanceof Error ? e.message : 'Action failed', 'error')
    }
  }

  const nameOf = (id: string | null) => data?.find((x) => x.id === id)?.name

  return (
    <>
      <PageHeader
        title={config.title}
        subtitle={config.subtitle}
        actions={<button className="btn primary" onClick={() => setEditing('new')}><Plus size={16} /> Add {config.singular}</button>}
      />
      <Card>
        {loading && !data ? <Loading /> : error ? <ErrorState message={error} onRetry={reload} /> : !data?.length ? (
          <Empty icon={<Icon size={24} />} title={`No ${config.title.toLowerCase()} yet`} />
        ) : (
          <div className="table-wrap">
            <table className="table">
              <thead>
                <tr>
                  <th>Name</th>
                  {config.withCode && <th>Code</th>}
                  {config.withOrder && <th>Parent</th>}
                  {config.withOrder && <th>Order</th>}
                  <th>Status</th>
                  <th className="right">Actions</th>
                </tr>
              </thead>
              <tbody>
                {data.map((item) => (
                  <tr key={item.id}>
                    <td><div className="row"><div className="dot-icon"><Icon size={15} /></div><span className="cell-title">{item.name}</span></div></td>
                    {config.withCode && <td className="mono">{item.code || '—'}</td>}
                    {config.withOrder && <td>{nameOf(item.parentId) ?? <span className="faint">—</span>}</td>}
                    {config.withOrder && <td>{item.sortOrder}</td>}
                    <td><Badge status={item.isActive ? 'active' : 'inactive'} label={item.isActive ? 'Active' : 'Archived'} /></td>
                    <td className="right">
                      <div className="actions" style={{ justifyContent: 'flex-end' }}>
                        <button className="btn sm icon" title="Edit" aria-label={`Edit ${item.name}`} onClick={() => setEditing(item)}><Pencil size={14} /></button>
                        {item.isActive ? (
                          <button className="btn sm danger" onClick={() => setArchiving(item)}><Archive size={14} /> Archive</button>
                        ) : (
                          <button className="btn sm success" onClick={() => restore(item)}><RotateCcw size={14} /> Restore</button>
                        )}
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>

      {editing && (
        <ResourceEditor config={config} item={editing === 'new' ? null : editing} all={data ?? []} onClose={() => setEditing(null)} onSaved={reload} />
      )}
      {archiving && (
        <Confirm
          title={`Archive ${archiving.name}?`}
          message={`Employees will no longer see this ${config.singular} in the apps. Existing invoices keep their reference, and you can restore it later.`}
          confirmLabel="Archive"
          danger
          busy={busy}
          onConfirm={archive}
          onClose={() => setArchiving(null)}
        />
      )}
    </>
  )
}

function ResourceEditor({ config, item, all, onClose, onSaved }: {
  config: Config
  item: NamedResource | null
  all: NamedResource[]
  onClose: () => void
  onSaved: () => void
}) {
  const toast = useToast()
  const [name, setName] = useState(item?.name ?? '')
  const [code, setCode] = useState(item?.code ?? '')
  const [parentId, setParentId] = useState(item?.parentId ?? '')
  const [sortOrder, setSortOrder] = useState(String(item?.sortOrder ?? (all.length + 1)))
  const [isActive, setIsActive] = useState(item?.isActive ?? true)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const valid = name.trim() && (!config.withCode || code.trim())

  async function save() {
    setBusy(true)
    setError(null)
    const body = {
      name: name.trim(),
      code: config.withCode ? code.trim() : null,
      parentId: config.withOrder ? parentId || null : null,
      sortOrder: config.withOrder ? Number(sortOrder) || 0 : 0,
      isActive,
    }
    try {
      if (item) await api(`${config.path}/${item.id}`, { method: 'PATCH', body })
      else await api(config.path, { method: 'POST', body })
      toast(`${config.singular[0].toUpperCase() + config.singular.slice(1)} ${item ? 'updated' : 'added'}`)
      onSaved()
      onClose()
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not save')
    } finally {
      setBusy(false)
    }
  }

  return (
    <Modal
      title={item ? `Edit ${item.name}` : `Add ${config.singular}`}
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
          <Field label="Name" full={!config.withCode}><input className="input" value={name} onChange={(e) => setName(e.target.value)} autoFocus /></Field>
          {config.withCode && <Field label="Code" hint="required"><input className="input mono" value={code} onChange={(e) => setCode(e.target.value)} placeholder="HYD-01" /></Field>}
          {config.withOrder && (
            <>
              <Field label="Parent category" hint="optional">
                <select className="select" value={parentId} onChange={(e) => setParentId(e.target.value)}>
                  <option value="">None (top level)</option>
                  {all.filter((x) => x.id !== item?.id && x.isActive).map((x) => <option key={x.id} value={x.id}>{x.name}</option>)}
                </select>
              </Field>
              <Field label="Display order"><input className="input" type="number" value={sortOrder} onChange={(e) => setSortOrder(e.target.value)} /></Field>
            </>
          )}
        </div>
        <Toggle checked={isActive} onChange={setIsActive} label="Active" description="Inactive items are hidden from employees" />
      </div>
    </Modal>
  )
}
