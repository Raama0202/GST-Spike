import { useState } from 'react'
import { Eye, EyeOff, Wand2 } from 'lucide-react'
import { api } from '../../api/client'
import type { Company, Items, Plan } from '../../api/types'
import { Alert, Confirm, CopyButton, Field, Modal, Spinner, useAsync, useToast } from '../../components/ui'
import { date, daysUntil, money } from '../../lib/format'
import { GstinVerifier } from '../../lib/gstin'
import { isEmail, isGstin, PASSWORD_HINT, passwordProblem } from '../../lib/validation'

export type StatusAction = 'suspend' | 'reactivate'

export function statusAction(status: Company['status']): StatusAction | null {
  if (status === 'active') return 'suspend'
  if (status === 'suspended') return 'reactivate'
  return null
}

export function StatusConfirm({ company, action, busy, onConfirm, onClose }: {
  company: { name: string }
  action: StatusAction
  busy: boolean
  onConfirm: () => void
  onClose: () => void
}) {
  return (
    <Confirm
      title={action === 'suspend' ? `Suspend ${company.name}?` : `Reactivate ${company.name}?`}
      message={action === 'suspend'
        ? 'All admins and employees of this company will lose access on web, Android and iOS until it is reactivated.'
        : 'Admins and employees of this company will regain access immediately.'}
      confirmLabel={action === 'suspend' ? 'Suspend' : 'Reactivate'}
      danger={action === 'suspend'}
      busy={busy}
      onConfirm={onConfirm}
      onClose={onClose}
    />
  )
}

export function EndsCell({ endsAt }: { endsAt?: string | null }) {
  const left = daysUntil(endsAt)
  if (!endsAt || left === null) return <span className="faint">—</span>
  return (
    <>
      <div className="nowrap">{date(endsAt)}</div>
      <div className="cell-sub" style={left < 0 ? { color: '#fca5a5' } : left <= 14 ? { color: '#fcd34d' } : undefined}>
        {left < 0 ? `expired ${-left}d ago` : left === 0 ? 'ends today' : `${left}d left`}
      </div>
    </>
  )
}

export function CopyCode({ code }: { code: string }) {
  return (
    <span className="code-pill">
      <span className="mono">{code}</span>
      <CopyButton text={code} label="Copy activation code" compact />
    </span>
  )
}

function generatePassword() {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789'
  const bytes = crypto.getRandomValues(new Uint32Array(14))
  return Array.from(bytes, (b) => alphabet[b % alphabet.length]).join('')
}

const EMPTY_COMPANY = {
  name: '', legalName: '', gstin: '', industry: '', adminEmail: '', adminPassword: '', planCode: '', seats: '10', subscriptionDays: '30',
}

export function CreateCompany({ onClose, onCreated }: { onClose: () => void; onCreated: () => void }) {
  const toast = useToast()
  const plans = useAsync(() => api<Items<Plan>>('/super/plans').then((r) => r.items))
  const [form, setForm] = useState(EMPTY_COMPANY)
  const [showPassword, setShowPassword] = useState(false)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [created, setCreated] = useState<{ name: string; activationCode: string } | null>(null)

  const plan = plans.data?.find((p) => p.code === form.planCode)
  const set = (key: keyof typeof form) => (e: React.ChangeEvent<HTMLInputElement | HTMLSelectElement>) =>
    setForm((f) => ({ ...f, [key]: e.target.value }))
  const dirty = Object.entries(form).some(([k, v]) => v !== EMPTY_COMPANY[k as keyof typeof form])

  function problem(): string | null {
    if (!form.name.trim()) return 'Enter the company name.'
    const gstin = form.gstin.trim().toUpperCase()
    if (gstin && !isGstin(gstin)) return 'GSTIN should be 15 characters, like 29ABCDE1234F1Z5.'
    if (!isEmail(form.adminEmail)) return 'Enter a valid admin email address.'
    const pw = passwordProblem(form.adminPassword)
    if (pw) return pw.replace(/^Password/, 'Admin password')
    if (!form.planCode) return 'Select a plan.'
    const seats = Number(form.seats)
    if (!Number.isInteger(seats) || seats < 1) return 'Seats must be a whole number of at least 1.'
    if (plan?.maxEmployees && seats > plan.maxEmployees) return `The ${plan.name} plan allows at most ${plan.maxEmployees} seats.`
    const days = Number(form.subscriptionDays)
    if (!Number.isInteger(days) || days < 1) return 'Subscription length must be at least 1 day.'
    return null
  }

  async function submit() {
    const p = problem()
    setError(p)
    if (p) return
    setBusy(true)
    try {
      const res = await api<{ name: string; activationCode: string }>('/super/companies', {
        method: 'POST',
        body: {
          name: form.name.trim(),
          legalName: form.legalName.trim() || null,
          gstin: form.gstin.trim().toUpperCase() || null,
          industry: form.industry.trim() || null,
          adminEmail: form.adminEmail.trim().toLowerCase(),
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

  return (
    <Modal
      title="Create company"
      subtitle="Sets up the tenant, its first company admin and a subscription."
      onClose={onClose}
      wide
      busy={busy}
      dirty={dirty}
      footer={
        <>
          <button className="btn" onClick={onClose} disabled={busy}>Cancel</button>
          <button className="btn primary" disabled={busy} onClick={submit}>{busy && <Spinner small />} Create company</button>
        </>
      }
    >
      <form className="stack" onSubmit={(e) => { e.preventDefault(); void submit() }} noValidate>
        {error && <Alert kind="error">{error}</Alert>}
        <div className="form-grid">
          <Field label="Company name"><input className="input" value={form.name} onChange={set('name')} placeholder="Acme Infra" autoFocus /></Field>
          <Field label="Legal name" hint="optional"><input className="input" value={form.legalName} onChange={set('legalName')} placeholder="Acme Infra Pvt Ltd" /></Field>
          <Field label="GSTIN" hint="optional">
            <input className="input mono" value={form.gstin} onChange={set('gstin')} placeholder="29ABCDE1234F1Z5" maxLength={15} style={{ textTransform: 'uppercase' }} />
          </Field>
          <GstinVerifier gstin={form.gstin} legalName={form.legalName} onUseLegalName={(legalName) => setForm((f) => ({ ...f, legalName }))} />
          <Field label="Industry" hint="optional"><input className="input" value={form.industry} onChange={set('industry')} placeholder="Construction" /></Field>
          <Field label="Admin email"><input className="input" type="email" autoComplete="off" value={form.adminEmail} onChange={set('adminEmail')} placeholder="admin@customer.com" /></Field>
          <Field label="Admin password" hint={PASSWORD_HINT}>
            <div className="row" style={{ gap: 6 }}>
              <input
                className="input"
                type={showPassword ? 'text' : 'password'}
                autoComplete="new-password"
                value={form.adminPassword}
                onChange={set('adminPassword')}
                placeholder="Temporary password"
              />
              <button type="button" className="btn icon" title={showPassword ? 'Hide password' : 'Show password'} aria-label={showPassword ? 'Hide password' : 'Show password'} onClick={() => setShowPassword((s) => !s)}>
                {showPassword ? <EyeOff size={16} /> : <Eye size={16} />}
              </button>
              <button
                type="button"
                className="btn icon"
                title="Generate a strong password"
                aria-label="Generate a strong password"
                onClick={() => { setForm((f) => ({ ...f, adminPassword: generatePassword() })); setShowPassword(true) }}
              >
                <Wand2 size={16} />
              </button>
            </div>
          </Field>
          <Field label="Plan">
            <select className="select" value={form.planCode} onChange={set('planCode')}>
              <option value="">{plans.loading ? 'Loading plans…' : 'Select a plan'}</option>
              {plans.data?.map((p) => (
                <option key={p.id} value={p.code}>{p.name} — {money(p.monthlyPriceInr)}/mo · {p.maxEmployees ? `${p.maxEmployees} seats max` : 'unlimited'}</option>
              ))}
            </select>
          </Field>
          <Field label="Seats" hint={plan?.maxEmployees ? `max ${plan.maxEmployees}` : undefined}>
            <input className="input" type="number" min={1} max={plan?.maxEmployees ?? undefined} value={form.seats} onChange={set('seats')} />
          </Field>
          <Field label="Subscription length" hint="days">
            <input className="input" type="number" min={1} value={form.subscriptionDays} onChange={set('subscriptionDays')} />
          </Field>
        </div>
        {plans.error && <Alert kind="error">Couldn't load plans: {plans.error}</Alert>}
        <button type="submit" hidden />
      </form>
    </Modal>
  )
}

export function ExtendDialog({ company, endsAt, onClose, onDone }: {
  company: { id: string; name: string }
  endsAt?: string | null
  onClose: () => void
  onDone?: (endsAt: string) => void
}) {
  const toast = useToast()
  const [days, setDays] = useState('30')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const count = Number(days)
  const valid = Number.isInteger(count) && count > 0 && count <= 3650
  const base = endsAt && new Date(endsAt).getTime() > Date.now() ? new Date(endsAt) : new Date()
  const preview = valid ? new Date(base.getTime() + count * 86400000).toISOString() : null

  async function submit() {
    setBusy(true)
    setError(null)
    try {
      const res = await api<{ endsAt: string }>(`/super/companies/${company.id}/subscription/extend`, { method: 'POST', body: { days: count } })
      toast(`Subscription extended to ${date(res.endsAt)}`)
      onDone?.(res.endsAt)
      onClose()
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not extend subscription')
      setBusy(false)
    }
  }

  return (
    <Modal
      title={`Extend ${company.name}`}
      subtitle="Adds days to the current subscription end date (or from today if already expired)."
      onClose={onClose}
      busy={busy}
      footer={
        <>
          <button className="btn" onClick={onClose} disabled={busy}>Cancel</button>
          <button className="btn primary" disabled={!valid || busy} onClick={submit}>{busy && <Spinner small />} Extend</button>
        </>
      }
    >
      <div className="stack">
        {error && <Alert kind="error">{error}</Alert>}
        {endsAt !== undefined && (
          <dl className="kv">
            <dt>Currently ends</dt><dd>{endsAt ? date(endsAt) : 'No subscription'}</dd>
            <dt>New end date</dt><dd><b>{preview ? date(preview) : '—'}</b></dd>
          </dl>
        )}
        <div className="row wrap" role="group" aria-label="Quick lengths">
          {[30, 90, 180, 365].map((d) => (
            <button key={d} className={`btn sm ${days === String(d) ? 'primary' : ''}`} aria-pressed={days === String(d)} onClick={() => setDays(String(d))}>{d} days</button>
          ))}
        </div>
        <Field label="Custom days" hint="1–3650"><input className="input" type="number" min={1} max={3650} value={days} onChange={(e) => setDays(e.target.value)} /></Field>
      </div>
    </Modal>
  )
}
