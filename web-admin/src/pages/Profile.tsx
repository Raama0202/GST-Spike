import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { KeyRound, LogOut, Server, ShieldCheck, Smartphone } from 'lucide-react'
import { useAuth } from '../auth/AuthContext'
import { api, API_BASE_URL } from '../api/client'
import { initials } from '../lib/format'
import { Alert, Card, Field, PageHeader, Spinner, useToast } from '../components/ui'

export default function Profile() {
  const { session, logout } = useAuth()
  const navigate = useNavigate()
  if (!session) return null
  const isSuper = session.role === 'super_admin'

  return (
    <>
      <PageHeader title="Profile" subtitle="Your account and connection details." />
      <div className="grid cols-2">
        <Card>
          <div className="row" style={{ gap: 16 }}>
            <div className="avatar" style={{ width: 64, height: 64, fontSize: 22 }}>{initials(session.email)}</div>
            <div>
              <div style={{ fontSize: 18, fontWeight: 700 }}>{session.email}</div>
              <div className="row" style={{ marginTop: 6 }}>
                <span className={`badge ${isSuper ? 'violet' : 'blue'}`}>{isSuper ? 'Super admin' : 'Company admin'}</span>
              </div>
            </div>
          </div>
          <dl className="kv" style={{ marginTop: 22 }}>
            <dt>Role</dt><dd>{isSuper ? 'Platform-wide access to tenants and plans' : 'Manages one company workspace'}</dd>
            {session.companyId && <><dt>Company ID</dt><dd className="mono">{session.companyId}</dd></>}
          </dl>
          <button
            className="btn danger"
            style={{ marginTop: 22 }}
            onClick={async () => { await logout(); navigate('/login', { replace: true }) }}
          >
            <LogOut size={16} /> Sign out
          </button>
        </Card>
        <Card title="Connected apps" subtitle="All clients share this backend, so changes here apply everywhere.">
          <div className="list-item">
            <div className="dot-icon"><Server size={16} /></div>
            <div><div className="cell-title">API server</div><div className="cell-sub mono">{API_BASE_URL}</div></div>
          </div>
          <div className="list-item">
            <div className="dot-icon"><Smartphone size={16} /></div>
            <div><div className="cell-title">Employee apps</div><div className="cell-sub">Android and iOS scanners upload invoices for review</div></div>
          </div>
          <div className="list-item">
            <div className="dot-icon"><ShieldCheck size={16} /></div>
            <div><div className="cell-title">Admin apps</div><div className="cell-sub">Android and iOS admin apps use the same accounts as this console</div></div>
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

  const strongEnough = next.length >= 10 && /[A-Za-z]/.test(next) && /[0-9\W]/.test(next)
  const valid = current && strongEnough && next === confirm && next !== current

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
        <Field label="New password" hint="10+ characters, letters and a number or symbol">
          <input className="input" type="password" autoComplete="new-password" value={next} onChange={(e) => setNext(e.target.value)} />
        </Field>
        <Field label="Confirm new password">
          <input className="input" type="password" autoComplete="new-password" value={confirm} onChange={(e) => setConfirm(e.target.value)} />
        </Field>
        {next && !strongEnough && <div className="faint" style={{ fontSize: 12.5 }}>Use at least 10 characters with letters and a number or symbol.</div>}
        {confirm && next !== confirm && <div className="faint" style={{ fontSize: 12.5, color: '#fca5a5' }}>Passwords don't match.</div>}
        <button className="btn primary" type="submit" disabled={!valid || busy} style={{ alignSelf: 'flex-start' }}>
          {busy ? <Spinner small /> : <KeyRound size={16} />} Update password
        </button>
      </form>
    </Card>
  )
}
