import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { KeyRound, Trash2 } from 'lucide-react'
import { api } from '../../api/client'
import type { Company, CompanySubscription, Items, Plan } from '../../api/types'
import { Alert, CopyButton, Field, Modal, Spinner, useAsync, useToast } from '../../components/ui'
import { date, money } from '../../lib/format'
import { isGstin } from '../../lib/validation'

export function EditCompanyDialog({ company, onClose, onSaved }: { company: Company; onClose: () => void; onSaved: (c: Company) => void }) {
  const toast = useToast()
  const initial = { name: company.name, legalName: company.legalName ?? '', gstin: company.gstin ?? '', industry: company.industry ?? '' }
  const [form, setForm] = useState(initial)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const set = (key: keyof typeof form) => (e: React.ChangeEvent<HTMLInputElement>) => setForm((f) => ({ ...f, [key]: e.target.value }))
  const dirty = (Object.keys(initial) as (keyof typeof initial)[]).some((k) => form[k] !== initial[k])

  async function save() {
    const gstin = form.gstin.trim().toUpperCase()
    if (!form.name.trim()) return setError('Company name is required.')
    if (gstin && !isGstin(gstin)) return setError('GSTIN should be 15 characters, like 29ABCDE1234F1Z5.')
    setBusy(true)
    setError(null)
    try {
      const updated = await api<Company>(`/super/companies/${company.id}`, {
        method: 'PATCH',
        body: { name: form.name.trim(), legalName: form.legalName.trim() || null, gstin: gstin || null, industry: form.industry.trim() || null },
      })
      toast('Company details saved')
      onSaved(updated)
      onClose()
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not save company')
      setBusy(false)
    }
  }

  return (
    <Modal
      title="Edit company details"
      onClose={onClose}
      busy={busy}
      dirty={dirty}
      footer={
        <>
          <button className="btn" onClick={onClose} disabled={busy}>Cancel</button>
          <button className="btn primary" disabled={!dirty || busy} onClick={save}>{busy && <Spinner small />} Save</button>
        </>
      }
    >
      <div className="stack">
        {error && <Alert kind="error">{error}</Alert>}
        <div className="form-grid">
          <Field label="Display name"><input className="input" value={form.name} onChange={set('name')} autoFocus /></Field>
          <Field label="Legal name" hint="optional"><input className="input" value={form.legalName} onChange={set('legalName')} /></Field>
          <Field label="GSTIN" hint="optional">
            <input className="input mono" value={form.gstin} onChange={set('gstin')} maxLength={15} style={{ textTransform: 'uppercase' }} />
          </Field>
          <Field label="Industry" hint="optional"><input className="input" value={form.industry} onChange={set('industry')} /></Field>
        </div>
      </div>
    </Modal>
  )
}

function toDateInput(iso: string | null | undefined): string {
  if (!iso) return ''
  const d = new Date(iso)
  if (Number.isNaN(d.getTime())) return ''
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
}

export function SubscriptionDialog({ companyId, subscription, activeEmployees, onClose, onSaved }: {
  companyId: string
  subscription: CompanySubscription | null
  activeEmployees: number
  onClose: () => void
  onSaved: () => void
}) {
  const toast = useToast()
  const plans = useAsync(() => api<Items<Plan>>('/super/plans').then((r) => r.items))
  const initialEnd = toDateInput(subscription?.endsAt)
  const [planCode, setPlanCode] = useState(subscription?.planCode ?? '')
  const [seats, setSeats] = useState(String(subscription?.seats ?? Math.max(activeEmployees, 10)))
  const [endsOn, setEndsOn] = useState(initialEnd)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const plan = plans.data?.find((p) => p.code === planCode)
  const seatCount = Number(seats)
  const minSeats = Math.max(1, activeEmployees)
  const dirty = planCode !== (subscription?.planCode ?? '') || seats !== String(subscription?.seats ?? Math.max(activeEmployees, 10)) || endsOn !== initialEnd

  const problem = !planCode
    ? 'Select a plan.'
    : !Number.isInteger(seatCount) || seatCount < minSeats
      ? `Seats must be at least ${minSeats} (the company has ${activeEmployees} active employees).`
      : plan?.maxEmployees && seatCount > plan.maxEmployees
        ? `${plan.name} allows at most ${plan.maxEmployees} seats.`
        : !subscription && !endsOn ? 'Pick an end date for the new subscription.' : null

  async function save() {
    if (problem) return setError(problem)
    setBusy(true)
    setError(null)
    try {
      const body: Record<string, unknown> = { planCode, seats: seatCount }
      if (endsOn && endsOn !== initialEnd) body.endsAt = new Date(`${endsOn}T23:59:59`).toISOString()
      await api(`/super/companies/${companyId}/subscription`, { method: 'PUT', body })
      toast('Subscription updated')
      onSaved()
      onClose()
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not update subscription')
      setBusy(false)
    }
  }

  return (
    <Modal
      title="Change subscription"
      subtitle="Applies immediately. No payment is collected; use this for manual deals and corrections."
      onClose={onClose}
      busy={busy}
      dirty={dirty}
      footer={
        <>
          <button className="btn" onClick={onClose} disabled={busy}>Cancel</button>
          <button className="btn primary" disabled={!dirty || busy} onClick={save}>{busy && <Spinner small />} Save subscription</button>
        </>
      }
    >
      <div className="stack">
        {error && <Alert kind="error">{error}</Alert>}
        {plans.error && <Alert kind="error">Couldn't load plans: {plans.error}</Alert>}
        <div className="form-grid">
          <Field label="Plan">
            <select className="select" value={planCode} onChange={(e) => setPlanCode(e.target.value)}>
              <option value="">{plans.loading ? 'Loading plans…' : 'Select a plan'}</option>
              {plans.data?.map((p) => (
                <option key={p.id} value={p.code}>{p.name} — {money(p.monthlyPriceInr)}/mo · {p.maxEmployees ? `${p.maxEmployees} seats max` : 'unlimited'}</option>
              ))}
            </select>
          </Field>
          <Field label="Seats" hint={[`min ${minSeats}`, plan?.maxEmployees ? `max ${plan.maxEmployees}` : null].filter(Boolean).join(' · ')}>
            <input className="input" type="number" min={minSeats} max={plan?.maxEmployees ?? undefined} value={seats} onChange={(e) => setSeats(e.target.value)} />
          </Field>
          <Field label="Ends on" hint={subscription ? `currently ${date(subscription.endsAt)}` : 'required'}>
            <input className="input" type="date" value={endsOn} onChange={(e) => setEndsOn(e.target.value)} />
          </Field>
        </div>
      </div>
    </Modal>
  )
}

export function ResetPasswordDialog({ companyId, admin, onClose }: {
  companyId: string
  admin: { id: string; email: string }
  onClose: () => void
}) {
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [password, setPassword] = useState<string | null>(null)

  async function reset() {
    setBusy(true)
    setError(null)
    try {
      const res = await api<{ temporaryPassword: string }>(`/super/companies/${companyId}/admins/${admin.id}/reset-password`, { method: 'POST' })
      setPassword(res.temporaryPassword)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not reset password')
    } finally {
      setBusy(false)
    }
  }

  if (password) {
    return (
      <Modal title="Temporary password" subtitle={admin.email} onClose={onClose} footer={<button className="btn primary" onClick={onClose}>I've saved it</button>}>
        <div className="stack">
          <Alert kind="info">This password is shown only once. Share it with the admin over a secure channel and ask them to change it after signing in.</Alert>
          <div className="secret-box">
            <span className="mono">{password}</span>
            <CopyButton text={password} />
          </div>
        </div>
      </Modal>
    )
  }

  return (
    <Modal
      title="Reset admin password?"
      onClose={onClose}
      busy={busy}
      footer={
        <>
          <button className="btn" onClick={onClose} disabled={busy}>Cancel</button>
          <button className="btn danger" onClick={reset} disabled={busy}>{busy ? <Spinner small /> : <KeyRound size={16} />} Reset password</button>
        </>
      }
    >
      <div className="stack">
        {error && <Alert kind="error">{error}</Alert>}
        <div className="muted">
          <b>{admin.email}</b> gets a new temporary password and is signed out everywhere. Their current password stops working immediately.
        </div>
      </div>
    </Modal>
  )
}

export function DeleteTenantDialog({ company, onClose }: { company: { id: string; name: string }; onClose: () => void }) {
  const toast = useToast()
  const navigate = useNavigate()
  const [confirmName, setConfirmName] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const ready = confirmName.trim().toLowerCase() === company.name.trim().toLowerCase()

  async function remove() {
    setBusy(true)
    setError(null)
    try {
      await api(`/super/companies/${company.id}/delete`, { method: 'POST', body: { confirmName: confirmName.trim() } })
      toast(`${company.name} was permanently deleted`, 'info')
      navigate('/super/companies', { replace: true })
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not delete company')
      setBusy(false)
    }
  }

  return (
    <Modal
      title={`Delete ${company.name}?`}
      subtitle="This cannot be undone."
      onClose={onClose}
      busy={busy}
      dirty={Boolean(confirmName)}
      footer={
        <>
          <button className="btn" onClick={onClose} disabled={busy}>Cancel</button>
          <button className="btn danger" disabled={!ready || busy} onClick={remove}>{busy ? <Spinner small /> : <Trash2 size={16} />} Delete permanently</button>
        </>
      }
    >
      <div className="stack">
        {error && <Alert kind="error">{error}</Alert>}
        <Alert kind="error">
          Permanently deletes every admin and employee account, all invoices and bill images, ITC data, settings and payment records for <b>{company.name}</b>.
          Consider suspending instead if the customer may return.
        </Alert>
        <Field label={`Type the company name (${company.name}) to confirm`}>
          <input className="input" value={confirmName} onChange={(e) => setConfirmName(e.target.value)} autoComplete="off" autoFocus />
        </Field>
      </div>
    </Modal>
  )
}
