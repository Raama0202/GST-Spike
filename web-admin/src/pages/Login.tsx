import { useState, type FormEvent } from 'react'
import { useNavigate } from 'react-router-dom'
import { Building2, FileText, KeyRound, Lock, Mail, Scale, ShieldCheck, Smartphone } from 'lucide-react'
import { useAuth } from '../auth/AuthContext'
import { API_ORIGIN, api } from '../api/client'
import { Alert, Field, Modal, Spinner, useToast } from '../components/ui'

export default function Login() {
  const { login } = useAuth()
  const navigate = useNavigate()
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [activating, setActivating] = useState(false)

  async function submit(e: FormEvent) {
    e.preventDefault()
    setBusy(true)
    setError(null)
    try {
      const session = await login(email, password)
      navigate(session.role === 'super_admin' ? '/super/overview' : '/dashboard', { replace: true })
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Sign in failed')
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="auth-page">
      <section className="auth-hero">
        <div className="brand" style={{ padding: 0 }}>
          <div className="brand-mark"><FileText size={20} strokeWidth={2.4} /></div>
          <div>
            <div className="brand-name">GST Expense</div>
            <div className="brand-sub">Administration console</div>
          </div>
        </div>
        <div>
          <h1>
            Every bill, every branch, <span className="gradient-text">one console.</span>
          </h1>
          <p>
            Review invoices captured by your field teams on Android and iOS, reconcile ITC against
            GSTR-2A/2B, and manage tenants and subscriptions from a single secure workspace.
          </p>
          <div className="feature-list">
            {[
              { icon: Smartphone, title: 'Mobile capture', text: 'Android & iOS scanners sync here' },
              { icon: ShieldCheck, title: 'Approval workflow', text: 'Approve, reject or return bills' },
              { icon: Scale, title: 'ITC matching', text: 'Import GSTR and chase suppliers' },
              { icon: Building2, title: 'Multi-tenant', text: 'Plans, seats and activation' },
            ].map(({ icon: Icon, title, text }) => (
              <div key={title} className="glass feature">
                <div className="stat-icon"><Icon size={18} /></div>
                <div><b>{title}</b><span>{text}</span></div>
              </div>
            ))}
          </div>
        </div>
        <div className="faint" style={{ fontSize: 12.5 }}>Connected to {new URL(API_ORIGIN).host}</div>
      </section>

      <section className="auth-panel">
        <form className="glass auth-card stack" onSubmit={submit}>
          <div>
            <h2>Sign in</h2>
            <div className="muted" style={{ marginTop: 4 }}>Super admins and company admins use the same sign-in.</div>
          </div>
          {error && <Alert kind="error">{error}</Alert>}
          <Field label="Work email">
            <div className="input-icon">
              <Mail size={16} />
              <input
                className="input"
                type="email"
                autoComplete="username"
                placeholder="you@company.com"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                required
                autoFocus
              />
            </div>
          </Field>
          <Field label="Password">
            <div className="input-icon">
              <Lock size={16} />
              <input
                className="input"
                type="password"
                autoComplete="current-password"
                placeholder="••••••••"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                required
              />
            </div>
          </Field>
          <button className="btn primary block" style={{ height: 44 }} disabled={busy}>
            {busy ? <><Spinner small /> Signing in…</> : 'Sign in'}
          </button>
          {busy && <div className="faint" style={{ fontSize: 12, textAlign: 'center' }}>The server may take up to a minute to wake up.</div>}
          <div className="divider">New company?</div>
          <button type="button" className="btn block" onClick={() => setActivating(true)}>
            <KeyRound size={16} /> Activate with a code
          </button>
        </form>
      </section>

      {activating && <ActivateDialog onClose={() => setActivating(false)} />}
    </div>
  )
}

function ActivateDialog({ onClose }: { onClose: () => void }) {
  const toast = useToast()
  const [code, setCode] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function activate() {
    setBusy(true)
    setError(null)
    try {
      await api('/super/companies/activate', { method: 'POST', auth: false, body: { activationCode: code.trim() } })
      toast('Company activated. You can now sign in with your admin email.')
      onClose()
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Activation failed')
    } finally {
      setBusy(false)
    }
  }

  return (
    <Modal
      title="Activate company"
      subtitle="Enter the activation code provided by your GST Expense administrator."
      onClose={onClose}
      footer={
        <>
          <button className="btn" onClick={onClose}>Cancel</button>
          <button className="btn primary" disabled={!code.trim() || busy} onClick={activate}>
            {busy && <Spinner small />} Activate
          </button>
        </>
      }
    >
      <div className="stack">
        {error && <Alert kind="error">{error}</Alert>}
        <Field label="Activation code">
          <input className="input mono" value={code} onChange={(e) => setCode(e.target.value)} placeholder="ACME-DEMO-2026" autoFocus />
        </Field>
      </div>
    </Modal>
  )
}
