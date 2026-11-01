import { useEffect, useState, type FormEvent } from 'react'
import { Link, useLocation, useNavigate } from 'react-router-dom'
import { Building2, FileText, KeyRound, Lock, Mail, Scale, ShieldCheck, Smartphone, UserPlus } from 'lucide-react'
import { useAuth } from '../auth/AuthContext'
import { home, returnPath } from '../auth/paths'
import { api } from '../api/client'
import { Alert, Field, Modal, Spinner, useDocumentTitle, useToast } from '../components/ui'
import { ForgotPasswordCard, RegisterCard, type RegistrationOptions } from './AuthFlows'
import { PublicFooterLinks } from './public/links'

type Mode = 'signin' | 'register' | 'forgot'

const TITLES: Record<Mode, string> = { signin: 'Sign in', register: 'Register your firm', forgot: 'Reset password' }

export default function Login() {
  const { login } = useAuth()
  const navigate = useNavigate()
  const location = useLocation()
  const toast = useToast()
  const [mode, setMode] = useState<Mode>('signin')
  useDocumentTitle(TITLES[mode])
  const [options, setOptions] = useState<RegistrationOptions | null>(null)
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [notice, setNotice] = useState<string | null>(null)
  const [activating, setActivating] = useState(false)

  useEffect(() => {
    api<RegistrationOptions>('/admin/auth/register/options', { auth: false })
      .then(setOptions)
      .catch(() => setOptions(null))
  }, [])

  function registered() {
    toast('Welcome! Your firm is set up. Next, add your GSTINs and employees.')
    navigate('/settings', { replace: true })
  }

  function passwordFlowDone(nextEmail: string, reset: boolean) {
    if (nextEmail) setEmail(nextEmail)
    setPassword('')
    setError(null)
    setNotice(reset ? 'Password updated. Sign in with your new password.' : null)
    setMode('signin')
  }

  async function submit(e: FormEvent) {
    e.preventDefault()
    setBusy(true)
    setError(null)
    setNotice(null)
    try {
      const session = await login(email, password)
      const from = session.billingRequired ? null : returnPath(location.state)
      navigate(from ?? home(session.role, session.billingRequired), { replace: true })
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
        <div className="stack" style={{ gap: 8 }}>
          <div className="faint" style={{ fontSize: 12.5 }}>Need help? <Link to="/contact">Contact us</Link> · <Link to="/pricing">See pricing</Link></div>
          <PublicFooterLinks />
        </div>
      </section>

      <section className="auth-panel">
        {mode === 'register' && (
          <RegisterCard options={options} onBack={() => setMode('signin')} onRegistered={registered} />
        )}
        {mode === 'forgot' && <ForgotPasswordCard initialEmail={email} onDone={passwordFlowDone} />}
        {mode === 'signin' && (
          <form className="glass auth-card stack" onSubmit={submit}>
            <div>
              <h2>Sign in</h2>
              <div className="muted" style={{ marginTop: 4 }}>Super admins and company admins use the same sign-in.</div>
            </div>
            {notice && <Alert kind="success">{notice}</Alert>}
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
            {options?.passwordReset !== false && (
              <button type="button" className="btn ghost auth-forgot" onClick={() => { setError(null); setNotice(null); setMode('forgot') }}>
                Forgot password?
              </button>
            )}
            <button className="btn primary block" style={{ height: 44 }} disabled={busy}>
              {busy ? <><Spinner small /> Signing in…</> : 'Sign in'}
            </button>
            {busy && <div className="faint" style={{ fontSize: 12, textAlign: 'center' }}>The server may take up to a minute to wake up.</div>}
            <div className="divider">New company?</div>
            {options?.enabled !== false && (
              <button type="button" className="btn block" onClick={() => { setError(null); setNotice(null); setMode('register') }}>
                <UserPlus size={16} /> Register your firm
              </button>
            )}
            <button type="button" className="btn ghost block" onClick={() => setActivating(true)}>
              <KeyRound size={16} /> Activate with a code
            </button>
          </form>
        )}
        <div className="auth-panel-links"><PublicFooterLinks /></div>
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
      busy={busy}
      dirty={Boolean(code.trim())}
      footer={
        <>
          <button className="btn" onClick={onClose} disabled={busy}>Cancel</button>
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
