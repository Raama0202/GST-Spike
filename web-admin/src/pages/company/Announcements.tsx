import { useState } from 'react'
import { Megaphone, Send } from 'lucide-react'
import { api } from '../../api/client'
import type { AnnouncementSummary, Items } from '../../api/types'
import { Alert, Card, Empty, ErrorState, Field, Loading, PageHeader, Spinner, useAsync, useToast } from '../../components/ui'
import { date } from '../../lib/format'

export default function Announcements() {
  const toast = useToast()
  const history = useAsync(() => api<Items<AnnouncementSummary>>('/admin/notifications/announcements').then((r) => r.items))
  const [title, setTitle] = useState('')
  const [body, setBody] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const sent = history.data ?? []

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
      await history.reload()
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not send announcement')
    } finally {
      setBusy(false)
    }
  }

  return (
    <>
      <PageHeader title="Announcements" subtitle="Broadcast a message to every active employee's notification inbox in the mobile apps." />
      <div className="grid cols-3">
        <Card title="New announcement" subtitle="Delivered to Android and iOS apps on their next sync.">
          <div className="stack">
            {error && <Alert kind="error">{error}</Alert>}
            <Field label="Title"><input className="input" value={title} onChange={(e) => setTitle(e.target.value)} placeholder="Month-end submission deadline" maxLength={120} /></Field>
            <Field label="Message">
              <textarea className="textarea" style={{ minHeight: 150 }} value={body} onChange={(e) => setBody(e.target.value)} placeholder="Please upload all bills for this month by the 28th." />
            </Field>
            <button className="btn primary" disabled={!title.trim() || !body.trim() || busy} onClick={send}>
              {busy ? <Spinner small /> : <Send size={16} />} Send to all employees
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
    </>
  )
}
