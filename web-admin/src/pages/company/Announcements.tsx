import { useState } from 'react'
import { Megaphone, Send } from 'lucide-react'
import { api } from '../../api/client'
import type { AnnouncementSummary, Items } from '../../api/types'
import { UnsavedChangesPrompt } from '../../components/UnsavedChangesPrompt'
import { Alert, Card, Confirm, Empty, ErrorState, Field, Loading, PageHeader, useAsync, useToast } from '../../components/ui'
import { date } from '../../lib/format'

export default function Announcements() {
  const toast = useToast()
  const history = useAsync(() => api<Items<AnnouncementSummary>>('/admin/notifications/announcements').then((r) => r.items))
  const [title, setTitle] = useState('')
  const [body, setBody] = useState('')
  const [confirming, setConfirming] = useState(false)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const sent = history.data ?? []
  const ready = Boolean(title.trim() && body.trim())

  async function send() {
    setBusy(true)
    setError(null)
    try {
      const res = await api<{ created: number }>('/admin/notifications/announcements', {
        method: 'POST',
        body: { title: title.trim(), body: body.trim() },
      })
      toast(res.created ? `Sent to ${res.created} employee${res.created === 1 ? '' : 's'}` : 'No active employees to notify', res.created ? 'success' : 'info')
      setTitle('')
      setBody('')
      setConfirming(false)
      await history.reload()
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not send announcement')
      setConfirming(false)
    } finally {
      setBusy(false)
    }
  }

  return (
    <>
      <PageHeader title="Announcements" subtitle="Broadcast a message to every active employee's notification inbox in the mobile apps." />
      <UnsavedChangesPrompt when={Boolean(title.trim() || body.trim()) && !busy} />
      <div className="grid cols-3">
        <Card title="New announcement" subtitle="Delivered to Android and iOS apps on their next sync.">
          <div className="stack">
            {error && <Alert kind="error">{error}</Alert>}
            <Field label="Title"><input className="input" value={title} onChange={(e) => setTitle(e.target.value)} placeholder="Month-end submission deadline" maxLength={120} /></Field>
            <Field label="Message">
              <textarea className="textarea" style={{ minHeight: 150 }} value={body} onChange={(e) => setBody(e.target.value)} maxLength={2000} placeholder="Please upload all bills for this month by the 28th." />
            </Field>
            <button className="btn primary" disabled={!ready || busy} onClick={() => setConfirming(true)}>
              <Send size={16} /> Send to all employees
            </button>
          </div>
        </Card>
        <Card title="Sent announcements" subtitle="Read counts update as employees open them." className="span-2">
          {history.loading && !history.data ? <Loading /> : history.error ? <ErrorState message={history.error} onRetry={history.reload} /> : sent.length === 0 ? (
            <Empty icon={<Megaphone size={24} />} title="No announcements yet" message="Your first broadcast will show up here." />
          ) : (
            sent.map((a) => (
              <div key={`${a.title}${a.createdAt}`} className="list-item">
                <div className="dot-icon"><Megaphone size={16} /></div>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div className="row between">
                    <div className="cell-title">{a.title}</div>
                    <span className="faint nowrap" style={{ fontSize: 12.5 }}>{date(a.createdAt, true)}</span>
                  </div>
                  <div className="muted" style={{ marginTop: 2, whiteSpace: 'pre-wrap' }}>{a.body}</div>
                  <div className="faint" style={{ fontSize: 12.5, marginTop: 6 }}>{a.read} of {a.recipients} read</div>
                </div>
              </div>
            ))
          )}
        </Card>
      </div>
      {confirming && (
        <Confirm
          title="Send to every active employee?"
          message={<>“<b>{title.trim()}</b>” goes to the notification inbox of all active employees on Android and iOS. It can't be recalled once sent.</>}
          confirmLabel={busy ? 'Sending…' : 'Send announcement'}
          busy={busy}
          onConfirm={send}
          onClose={() => setConfirming(false)}
        />
      )}
    </>
  )
}
