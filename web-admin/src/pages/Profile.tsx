import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { KeyRound, LogOut, Monitor, ShieldCheck, Smartphone } from 'lucide-react'
import { useAuth } from '../auth/AuthContext'
import { api } from '../api/client'
import { initials } from '../lib/format'
import { PASSWORD_HINT, passwordProblem } from '../lib/validation'
import { Alert, Card, Field, PageHeader, Spinner, useToast } from '../components/ui'

export default function Profile() {
  const { session, logout } = useAuth()
  const navigate = useNavigate()
  if (!session) return null
  const isSuper = session.role === 'super_admin'

  return (
    <>
      <PageHeader title="Profile" subtitle="Your account and sign-in security." />
      <div className="grid cols-2">
        <Card>
          <div className="row" style={{ gap: 16 }}>
            <div className="avatar" style={{ width: 64, height: 64, fontSize: 22 }} aria-hidden>{initials(session.email)}</div>
            <div style={{ minWidth: 0 }}>
              <div style={{ fontSize: 18, fontWeight: 700, wordBreak: 'break-all' }}>{session.email}</div>
              <div className="row" style={{ marginTop: 6 }}>
                <span className={`badge ${isSuper ? 'violet' : 'blue'}`}>{isSuper ? 'Super admin' : 'Company admin'}</span>
              </div>
            </div>
          </div>
          <dl className="kv" style={{ marginTop: 22 }}>
            <dt>Access</dt><dd>{isSuper ? 'Platform-wide access to tenants, plans and payments' : 'Manages one company workspace'}</dd>
            {!isSuper && session.companyName && <><dt>Company</dt><dd>{session.companyName}</dd></>}
          </dl>
          <button
            className="btn danger"
            style={{ marginTop: 22 }}
            onClick={async () => { await logout(); navigate('/login', { replace: true }) }}
          >
            <LogOut size={16} /> Sign out
          </button>
        </Card>
        <Card title="Where this account works" subtitle="The same email and password sign you in everywhere.">
          <div className="list-item">
            <div className="dot-icon"><Monitor size={16} /></div>
            <div><div className="cell-title">Web console</div><div className="cell-sub">This site, on any desktop or mobile browser</div></div>
          </div>
          <div className="list-item">
            <div className="dot-icon"><ShieldCheck size={16} /></div>
            <div><div className="cell-title">Admin apps</div><div className="cell-sub">Android and iOS admin apps use the same accounts as this console</div></div>
          </div>
          <div className="list-item">
            <div className="dot-icon"><Smartphone size={16} /></div>
            <div><div className="cell-title">Employee apps</div><div className="cell-sub">Employees sign in with their mobile number, not this account</div></div>
          </div>
        </Card>
        <ChangePassword />
      </div>
    </>
  )
}

function ChangePassword() {
  const toast = useToast()
  const { updateSession } = useAuth()
  const [current, setCurrent] = useState('')
  const [next, setNext] = useState('')
  const [confirm, setConfirm] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const weak = next ? passwordProblem(next) : null
  const valid = current && next && !weak && next === confirm && next !== current

  async function submit(e: React.FormEvent) {
    e.preventDefault()
    if (!valid) return
    setBusy(true)
    setError(null)
    try {
      const tokens = await api<{ accessToken: string; refreshToken: string }>('/admin/auth/password', {
        method: 'POST',
        body: { currentPassword: current, newPassword: next },
      })
      updateSession({ accessToken: tokens.accessToken, refreshToken: tokens.refreshToken })
      setCurrent(''); setNext(''); setConfirm('')
      toast('Password changed. Other devices have been signed out.')
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not change password')
    } finally {
      setBusy(false)
    }
  }

  return (
    <Card title="Change password" subtitle="Signs you out everywhere else, including the mobile admin apps.">
      <form className="stack" onSubmit={submit}>
        {error && <Alert kind="error">{error}</Alert>}
        <Field label="Current password">
          <input className="input" type="password" autoComplete="current-password" value={current} onChange={(e) => setCurrent(e.target.value)} />
        </Field>
        <Field label="New password" hint={PASSWORD_HINT}>
          <input className="input" type="password" autoComplete="new-password" value={next} onChange={(e) => setNext(e.target.value)} />
        </Field>
        <Field label="Confirm new password">
          <input className="input" type="password" autoComplete="new-password" value={confirm} onChange={(e) => setConfirm(e.target.value)} />
        </Field>
        {weak && <div className="faint" style={{ fontSize: 12.5 }}>{weak}</div>}
        {confirm && next !== confirm && <div style={{ fontSize: 12.5, color: '#fca5a5' }}>Passwords don't match.</div>}
        {next && current && next === current && <div style={{ fontSize: 12.5, color: '#fca5a5' }}>Choose a password different from the current one.</div>}
        <button className="btn primary" type="submit" disabled={!valid || busy} style={{ alignSelf: 'flex-start' }}>
          {busy ? <Spinner small /> : <KeyRound size={16} />} Update password
        </button>
      </form>
    </Card>
  )
}
