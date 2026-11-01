import { useEffect, useState, type FormEvent } from 'react'
import { ArrowLeft, Lock, Mail } from 'lucide-react'
import { api } from '../api/client'
import { useAuth, type LoginResponse } from '../auth/AuthContext'
import { Alert, Field, Spinner } from '../components/ui'
import { GstinVerifier } from '../lib/gstin'
import { cleanMobile, isEmail, isGstin, isMobile, MIN_PASSWORD, PASSWORD_HINT, passwordProblem } from '../lib/validation'

export interface RegistrationOptions {
  enabled: boolean
  verificationRequired: boolean
  available: boolean
  passwordReset: boolean
  trialDays: number
  trialSeats: number
}

interface CodeSent {
  destination: string
  expiresInMinutes: number
}

const RESEND_SECONDS = 30

function message(err: unknown, fallback: string) {
  return err instanceof Error ? err.message : fallback
}

function useCountdown() {
  const [left, setLeft] = useState(0)
  useEffect(() => {
    if (left <= 0) return
    const timer = setTimeout(() => setLeft((n) => n - 1), 1000)
    return () => clearTimeout(timer)
  }, [left])
  return [left, () => setLeft(RESEND_SECONDS)] as const
}

function BackLink({ onClick, label = 'Back to sign in' }: { onClick: () => void; label?: string }) {
  return (
    <button type="button" className="btn ghost auth-back" onClick={onClick}>
      <ArrowLeft size={16} /> {label}
    </button>
  )
}

function CodeInput({ value, onChange }: { value: string; onChange: (code: string) => void }) {
  return (
    <input
      className="input mono code-input"
      inputMode="numeric"
      autoComplete="one-time-code"
      pattern="[0-9]{6}"
      maxLength={6}
      placeholder="000000"
      value={value}
      onChange={(e) => onChange(e.target.value.replace(/\D/g, '').slice(0, 6))}
      required
      autoFocus
    />
  )
}

function ResendButton({ onResend }: { onResend: () => Promise<void> }) {
  const [left, restart] = useCountdown()
  const [busy, setBusy] = useState(false)
  useEffect(restart, [])  // a code was just sent

  async function resend() {
    setBusy(true)
    try {
      await onResend()
      restart()
    } catch {
      /* onResend shows the error */
    } finally {
      setBusy(false)
    }
  }

  return (
    <button type="button" className="btn ghost block" disabled={left > 0 || busy} onClick={resend}>
      {busy ? <Spinner small /> : null}
      {left > 0 ? `Resend code in ${left} s` : 'Resend code'}
    </button>
  )
}

// ── Firm registration ────────────────────────────────────────────────────────

interface FirmForm {
  companyName: string
  legalName: string
  gstin: string
  industry: string
  adminName: string
  adminEmail: string
  mobile: string
  adminPassword: string
  confirmPassword: string
}

const EMPTY_FIRM: FirmForm = {
  companyName: '', legalName: '', gstin: '', industry: '', adminName: '',
  adminEmail: '', mobile: '', adminPassword: '', confirmPassword: '',
}

function firmProblem(form: FirmForm): string | null {
  const gstin = form.gstin.trim().toUpperCase()
  if (gstin && !isGstin(gstin)) return 'GSTIN should be 15 characters, like 36AABCS1429B1Z5.'
  if (!isEmail(form.adminEmail)) return 'Enter a valid work email address.'
  if (form.mobile.trim() && !isMobile(form.mobile)) return 'Enter a valid mobile number (10 digits, optionally with +91).'
  const weak = passwordProblem(form.adminPassword)
  if (weak) return weak
  if (form.adminPassword !== form.confirmPassword) return 'The two passwords do not match.'
  return null
}

function optional(value: string) {
  const trimmed = value.trim()
  return trimmed ? trimmed : null
}

export function RegisterCard({ options, onBack, onRegistered }: {
  options: RegistrationOptions | null
  onBack: () => void
  onRegistered: () => void
}) {
  const { adoptSession } = useAuth()
  const [form, setForm] = useState<FirmForm>(EMPTY_FIRM)
  const [sent, setSent] = useState<CodeSent | null>(null)
  const [code, setCode] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [notice, setNotice] = useState<string | null>(null)

  const set = (key: keyof FirmForm) => (e: { target: { value: string } }) =>
    setForm((f) => ({ ...f, [key]: e.target.value }))
  const email = form.adminEmail.trim().toLowerCase()
  const unavailable = options !== null && !options.available

  async function register(e: FormEvent) {
    e.preventDefault()
    const problem = firmProblem(form)
    if (problem) return setError(problem)
    setBusy(true)
    setError(null)
    try {
      const data = await api<({ verificationRequired: true } & CodeSent) | ({ verificationRequired: false } & LoginResponse)>(
        '/admin/auth/register',
        {
          method: 'POST',
          auth: false,
          body: {
            companyName: form.companyName.trim(),
            legalName: optional(form.legalName),
            gstin: optional(form.gstin.toUpperCase()),
            industry: optional(form.industry),
            adminName: form.adminName.trim(),
            adminEmail: email,
            mobile: optional(cleanMobile(form.mobile)),
            adminPassword: form.adminPassword,
          },
        },
      )
      if (data.verificationRequired) {
        setSent({ destination: data.destination, expiresInMinutes: data.expiresInMinutes })
      } else {
        adoptSession(data)
        onRegistered()
      }
    } catch (err) {
      setError(message(err, 'Registration failed'))
    } finally {
      setBusy(false)
    }
  }

  async function verify(e: FormEvent) {
    e.preventDefault()
    setBusy(true)
    setError(null)
    try {
      const data = await api<LoginResponse>('/admin/auth/register/verify', {
        method: 'POST',
        auth: false,
        // The API re-checks the password from step one so a changed form can't hijack the pending sign-up.
        body: { email, code, password: form.adminPassword },
      })
      adoptSession(data)
      onRegistered()
    } catch (err) {
      setError(message(err, 'Verification failed'))
      setBusy(false)
    }
  }

  async function resend() {
    setError(null)
    setNotice(null)
    try {
      const data = await api<CodeSent>('/admin/auth/register/resend', { method: 'POST', auth: false, body: { email } })
      setSent(data)
      setNotice(`A new code was sent to ${data.destination}.`)
    } catch (err) {
      setError(message(err, 'Could not resend the code'))
      throw err
    }
  }

  if (sent) {
    return (
      <form className="glass auth-card stack" onSubmit={verify}>
        <BackLink onClick={() => { setSent(null); setCode(''); setError(null); setNotice(null) }} label="Edit details" />
        <div>
          <h2>Check your email</h2>
          <div className="muted" style={{ marginTop: 4 }}>
            We sent a 6-digit code to <b>{sent.destination}</b>. It expires in {sent.expiresInMinutes} minutes.
          </div>
        </div>
        {error && <Alert kind="error">{error}</Alert>}
        {notice && <Alert kind="success">{notice}</Alert>}
        <Field label="Verification code">
          <CodeInput value={code} onChange={setCode} />
        </Field>
        <button className="btn primary block" style={{ height: 44 }} disabled={busy || code.length !== 6}>
          {busy ? <><Spinner small /> Creating your account…</> : 'Verify and create account'}
        </button>
        <ResendButton onResend={resend} />
        <div className="faint" style={{ fontSize: 12, textAlign: 'center' }}>No email? Check your spam folder.</div>
      </form>
    )
  }

  return (
    <form className="glass auth-card wide stack" onSubmit={register}>
      <BackLink onClick={onBack} />
      <div>
        <h2>Register your firm</h2>
        <div className="muted" style={{ marginTop: 4 }}>
          {options
            ? `Free ${options.trialDays}-day trial with up to ${options.trialSeats} employees. No card needed.`
            : 'Create your company and its administrator account.'}
        </div>
      </div>
      {unavailable && (
        <Alert kind="error">Registration is temporarily unavailable. Please try again later or contact support.</Alert>
      )}
      {error && <Alert kind="error">{error}</Alert>}
      <div className="form-grid">
        <Field label="Company name" full>
          <input className="input" value={form.companyName} onChange={set('companyName')} placeholder="Sri Lakshmi Traders" required minLength={2} autoFocus />
        </Field>
        <Field label="GSTIN" hint="recommended">
          <input
            className="input mono"
            value={form.gstin}
            onChange={(e) => setForm((f) => ({ ...f, gstin: e.target.value.toUpperCase().replace(/\s/g, '') }))}
            placeholder="36AABCS1429B1Z5"
            maxLength={15}
          />
        </Field>
        <Field label="Legal name" hint="as on GST certificate">
          <input className="input" value={form.legalName} onChange={set('legalName')} placeholder="Sri Lakshmi Traders Pvt Ltd" />
        </Field>
        <GstinVerifier
          gstin={form.gstin}
          publicCheck
          legalName={form.legalName}
          onUseLegalName={(legalName) => setForm((f) => ({ ...f, legalName }))}
        />
        <div className="full faint" style={{ fontSize: 12, marginTop: -6 }}>
          Your GSTIN and names let the scanner tell your firm apart from the supplier on every bill.
        </div>
        <Field label="Industry" hint="optional" full>
          <input className="input" value={form.industry} onChange={set('industry')} placeholder="Construction, retail, pharma…" />
        </Field>
        <Field label="Your name">
          <input className="input" value={form.adminName} onChange={set('adminName')} autoComplete="name" required minLength={2} />
        </Field>
        <Field label="Mobile" hint="optional">
          <input className="input" value={form.mobile} onChange={set('mobile')} inputMode="tel" autoComplete="tel" placeholder="98765 43210" />
        </Field>
        <Field label="Work email" full>
          <div className="input-icon">
            <Mail size={16} />
            <input className="input" type="email" value={form.adminEmail} onChange={set('adminEmail')} autoComplete="email" placeholder="you@company.com" required />
          </div>
        </Field>
        <Field label="Password" hint={PASSWORD_HINT}>
          <div className="input-icon">
            <Lock size={16} />
            <input className="input" type="password" value={form.adminPassword} onChange={set('adminPassword')} autoComplete="new-password" required minLength={MIN_PASSWORD} />
          </div>
        </Field>
        <Field label="Confirm password">
          <div className="input-icon">
            <Lock size={16} />
            <input className="input" type="password" value={form.confirmPassword} onChange={set('confirmPassword')} autoComplete="new-password" required />
          </div>
        </Field>
      </div>
      <button className="btn primary block" style={{ height: 44 }} disabled={busy || unavailable}>
        {busy
          ? <><Spinner small /> Sending code…</>
          : options?.verificationRequired === false ? 'Create account' : 'Continue'}
      </button>
      {busy && <div className="faint" style={{ fontSize: 12, textAlign: 'center' }}>The server may take up to a minute to wake up.</div>}
    </form>
  )
}

// ── Password reset ───────────────────────────────────────────────────────────

export function ForgotPasswordCard({ initialEmail, onDone }: { initialEmail: string; onDone: (email: string, reset: boolean) => void }) {
  const [email, setEmail] = useState(initialEmail)
  const [sent, setSent] = useState<CodeSent | null>(null)
  const [code, setCode] = useState('')
  const [password, setPassword] = useState('')
  const [confirm, setConfirm] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [notice, setNotice] = useState<string | null>(null)
  const normalized = email.trim().toLowerCase()

  async function requestCode() {
    const data = await api<CodeSent>('/admin/auth/password/forgot', { method: 'POST', auth: false, body: { email: normalized } })
    setSent(data)
    return data
  }

  async function send(e: FormEvent) {
    e.preventDefault()
    setBusy(true)
    setError(null)
    try {
      await requestCode()
    } catch (err) {
      setError(message(err, 'Could not send the code'))
    } finally {
      setBusy(false)
    }
  }

  async function resend() {
    setError(null)
    setNotice(null)
    try {
      const data = await requestCode()
      setNotice(`A new code was sent to ${data.destination}.`)
    } catch (err) {
      setError(message(err, 'Could not resend the code'))
      throw err
    }
  }

  async function reset(e: FormEvent) {
    e.preventDefault()
    const weak = passwordProblem(password)
    if (weak) return setError(weak)
    if (password !== confirm) return setError('The two passwords do not match.')
    setBusy(true)
    setError(null)
    try {
      await api('/admin/auth/password/reset', {
        method: 'POST',
        auth: false,
        body: { email: normalized, code, newPassword: password },
      })
      onDone(normalized, true)
    } catch (err) {
      setError(message(err, 'Could not reset the password'))
      setBusy(false)
    }
  }

  if (!sent) {
    return (
      <form className="glass auth-card stack" onSubmit={send}>
        <BackLink onClick={() => onDone(normalized, false)} />
        <div>
          <h2>Reset password</h2>
          <div className="muted" style={{ marginTop: 4 }}>Enter your admin email and we'll send you a 6-digit code.</div>
        </div>
        {error && <Alert kind="error">{error}</Alert>}
        <Field label="Work email">
          <div className="input-icon">
            <Mail size={16} />
            <input className="input" type="email" autoComplete="username" value={email} onChange={(e) => setEmail(e.target.value)} required autoFocus />
          </div>
        </Field>
        <button className="btn primary block" style={{ height: 44 }} disabled={busy}>
          {busy ? <><Spinner small /> Sending…</> : 'Send code'}
        </button>
      </form>
    )
  }

  return (
    <form className="glass auth-card stack" onSubmit={reset}>
      <BackLink onClick={() => { setSent(null); setCode(''); setError(null); setNotice(null) }} label="Use a different email" />
      <div>
        <h2>Choose a new password</h2>
        <div className="muted" style={{ marginTop: 4 }}>
          If <b>{sent.destination}</b> has an admin account, a code is on its way. It expires in {sent.expiresInMinutes} minutes.
        </div>
      </div>
      {error && <Alert kind="error">{error}</Alert>}
      {notice && <Alert kind="success">{notice}</Alert>}
      <Field label="Code from the email">
        <CodeInput value={code} onChange={setCode} />
      </Field>
      <Field label="New password" hint={PASSWORD_HINT}>
        <div className="input-icon">
          <Lock size={16} />
          <input className="input" type="password" autoComplete="new-password" value={password} onChange={(e) => setPassword(e.target.value)} required minLength={MIN_PASSWORD} />
        </div>
      </Field>
      <Field label="Confirm new password">
        <div className="input-icon">
          <Lock size={16} />
          <input className="input" type="password" autoComplete="new-password" value={confirm} onChange={(e) => setConfirm(e.target.value)} required />
        </div>
      </Field>
      <button className="btn primary block" style={{ height: 44 }} disabled={busy || code.length !== 6}>
        {busy ? <><Spinner small /> Saving…</> : 'Reset password'}
      </button>
      <ResendButton onResend={resend} />
    </form>
  )
}
