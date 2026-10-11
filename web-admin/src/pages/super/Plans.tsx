import { useState } from 'react'
import { Pencil, Plus, Tags, Trash2, Users } from 'lucide-react'
import { api } from '../../api/client'
import type { Items, Plan } from '../../api/types'
import {
  Alert, Card, Confirm, Empty, ErrorState, Field, Loading, Modal, PageHeader, Spinner, Toggle, useAsync, useToast,
} from '../../components/ui'
import { money } from '../../lib/format'

const KNOWN_FEATURES: { key: string; label: string; description: string }[] = [
  { key: 'galleryImport', label: 'Gallery import', description: 'Employees can pick bills from the photo gallery' },
  { key: 'analytics', label: 'Analytics', description: 'Spend analytics on the company dashboard' },
  { key: 'allFeatures', label: 'All features', description: 'Unlock every current and future feature' },
]

export default function Plans() {
  const toast = useToast()
  const { data, error, loading, reload } = useAsync(() => api<Items<Plan>>('/super/plans').then((r) => r.items))
  const [editing, setEditing] = useState<Plan | 'new' | null>(null)
  const [deleting, setDeleting] = useState<Plan | null>(null)
  const [busy, setBusy] = useState(false)

  async function remove() {
    if (!deleting) return
    setBusy(true)
    try {
      await api(`/super/plans/${deleting.id}`, { method: 'DELETE' })
      toast(`${deleting.name} deleted`)
      setDeleting(null)
      await reload()
    } catch (e) {
      toast(e instanceof Error ? e.message : 'Could not delete plan', 'error')
    } finally {
      setBusy(false)
    }
  }

  return (
    <>
      <PageHeader
        title="Subscription plans"
        subtitle="Pricing, seat limits and feature flags offered to tenants."
        actions={<button className="btn primary" onClick={() => setEditing('new')}><Plus size={16} /> New plan</button>}
      />
      {loading && !data ? <Card><Loading /></Card> : error ? <Card><ErrorState message={error} onRetry={reload} /></Card> : !data?.length ? (
        <Card><Empty icon={<Tags size={24} />} title="No plans yet" message="Create a plan before provisioning companies." /></Card>
      ) : (
        <div className="grid cols-3">
          {data.map((p) => (
            <div key={p.id} className="glass card stack" style={{ gap: 14 }}>
              <div className="row between">
                <div>
                  <div className="card-title" style={{ fontSize: 17 }}>{p.name}</div>
                  <div className="faint mono">{p.code}</div>
                </div>
                <div className="actions">
                  <button className="btn sm icon" title="Edit" aria-label={`Edit ${p.name}`} onClick={() => setEditing(p)}><Pencil size={14} /></button>
                  <button className="btn sm icon danger" title="Delete" aria-label={`Delete ${p.name}`} onClick={() => setDeleting(p)}><Trash2 size={14} /></button>
                </div>
              </div>
              <div>
                <span className="stat-value" style={{ marginTop: 0 }}>{money(p.monthlyPriceInr)}</span>
                <span className="faint"> / month</span>
              </div>
              <div className="row muted"><Users size={15} /> {p.maxEmployees ? `Up to ${p.maxEmployees} employees` : 'Unlimited employees'}</div>
              <div className="row wrap" style={{ gap: 6 }}>
                {Object.entries(p.features ?? {}).filter(([, v]) => v).map(([k]) => (
                  <span key={k} className="badge blue" style={{ textTransform: 'none' }}>{KNOWN_FEATURES.find((f) => f.key === k)?.label ?? k}</span>
                ))}
                {!Object.values(p.features ?? {}).some(Boolean) && <span className="faint">No feature flags</span>}
              </div>
            </div>
          ))}
        </div>
      )}

      {editing && <PlanEditor plan={editing === 'new' ? null : editing} onClose={() => setEditing(null)} onSaved={reload} />}
      {deleting && (
        <Confirm
          title={`Delete ${deleting.name}?`}
          message="Plans already assigned to a company subscription cannot be deleted."
          confirmLabel="Delete plan"
          danger
          busy={busy}
          onConfirm={remove}
          onClose={() => setDeleting(null)}
        />
      )}
    </>
  )
}

function PlanEditor({ plan, onClose, onSaved }: { plan: Plan | null; onClose: () => void; onSaved: () => void }) {
  const toast = useToast()
  const [code, setCode] = useState(plan?.code ?? '')
  const [name, setName] = useState(plan?.name ?? '')
  const [price, setPrice] = useState(plan ? String(plan.monthlyPriceInr) : '')
  const [unlimited, setUnlimited] = useState(plan ? plan.maxEmployees === null : false)
  const [seats, setSeats] = useState(plan?.maxEmployees ? String(plan.maxEmployees) : '10')
  const [features, setFeatures] = useState<Record<string, unknown>>(plan?.features ?? {})
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function save() {
    setBusy(true)
    setError(null)
    const body = {
      code: code.trim().toLowerCase(),
      name: name.trim(),
      monthlyPriceInr: Number(price),
      maxEmployees: unlimited ? null : Number(seats),
      features,
    }
    try {
      if (plan) await api(`/super/plans/${plan.id}`, { method: 'PUT', body })
      else await api('/super/plans', { method: 'POST', body })
      toast(plan ? 'Plan updated' : 'Plan created')
      onSaved()
      onClose()
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not save plan')
    } finally {
      setBusy(false)
    }
  }

  const valid = code.trim() && name.trim() && price !== '' && Number(price) >= 0 && (unlimited || Number(seats) > 0)

  return (
    <Modal
      title={plan ? `Edit ${plan.name}` : 'New plan'}
      onClose={onClose}
      footer={
        <>
          <button className="btn" onClick={onClose}>Cancel</button>
          <button className="btn primary" disabled={!valid || busy} onClick={save}>{busy && <Spinner small />} Save plan</button>
        </>
      }
    >
      <div className="stack">
        {error && <Alert kind="error">{error}</Alert>}
        <div className="form-grid">
          <Field label="Plan name"><input className="input" value={name} onChange={(e) => setName(e.target.value)} placeholder="Growth" autoFocus /></Field>
          <Field label="Code" hint="unique, lowercase"><input className="input mono" value={code} onChange={(e) => setCode(e.target.value)} placeholder="growth" /></Field>
          <Field label="Monthly price (₹)"><input className="input" type="number" min={0} value={price} onChange={(e) => setPrice(e.target.value)} /></Field>
          <Field label="Seat limit">
            <input className="input" type="number" min={1} value={unlimited ? '' : seats} disabled={unlimited} placeholder={unlimited ? 'Unlimited' : ''} onChange={(e) => setSeats(e.target.value)} />
          </Field>
        </div>
        <div>
          <Toggle checked={unlimited} onChange={setUnlimited} label="Unlimited employees" description="No seat cap for companies on this plan" />
          {KNOWN_FEATURES.map((f) => (
            <Toggle
              key={f.key}
              checked={Boolean(features[f.key])}
              onChange={(v) => setFeatures((cur) => ({ ...cur, [f.key]: v }))}
              label={f.label}
              description={f.description}
            />
          ))}
        </div>
      </div>
    </Modal>
  )
}
