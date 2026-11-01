import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { Trash2 } from 'lucide-react'
import { api } from '../../api/client'
import { useAuth } from '../../auth/AuthContext'
import { Alert, Field, Modal, Spinner, useToast } from '../../components/ui'

const sameName = (a: string, b: string) => a.trim().toLowerCase() === b.trim().toLowerCase()

export function DeleteCompanyDialog({ companyName, onClose }: { companyName: string; onClose: () => void }) {
  const toast = useToast()
  const navigate = useNavigate()
  const { logout } = useAuth()
  const [confirmName, setConfirmName] = useState('')
  const [password, setPassword] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const ready = sameName(confirmName, companyName) && password.length > 0

  async function remove() {
    setBusy(true)
    setError(null)
    try {
      await api('/admin/company/delete', { method: 'POST', body: { password, confirmName: confirmName.trim() } })
      await logout()
      toast(`${companyName} and all its data were deleted.`, 'info')
      navigate('/login', { replace: true })
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not delete the company')
      setBusy(false)
    }
  }

  return (
    <Modal
      title="Delete company account"
      subtitle="This cannot be undone."
      onClose={onClose}
      busy={busy}
      dirty={Boolean(confirmName || password)}
      footer={
        <>
          <button className="btn" onClick={onClose} disabled={busy}>Cancel</button>
          <button className="btn danger" disabled={!ready || busy} onClick={remove}>
            {busy ? <Spinner small /> : <Trash2 size={16} />} Delete everything
          </button>
        </>
      }
    >
      <div className="stack">
        {error && <Alert kind="error">{error}</Alert>}
        <Alert kind="error">
          Permanently deletes <b>{companyName}</b>: every admin and employee account, all invoices and bill images, ITC data,
          branches, categories and settings. Employees are signed out of the mobile apps. Download any exports you need first.
        </Alert>
        <Field label={`Type the company name (${companyName}) to confirm`}>
          <input className="input" value={confirmName} onChange={(e) => setConfirmName(e.target.value)} autoComplete="off" autoFocus />
        </Field>
        <Field label="Your password">
          <input className="input" type="password" value={password} onChange={(e) => setPassword(e.target.value)} autoComplete="current-password" />
        </Field>
      </div>
    </Modal>
  )
}
