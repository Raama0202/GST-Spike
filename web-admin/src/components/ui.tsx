import {
  Component,
  createContext,
  useCallback,
  useContext,
  useEffect,
  useId,
  useRef,
  useState,
  type ErrorInfo,
  type ReactNode,
} from 'react'
import { Link } from 'react-router-dom'
import { AlertTriangle, Check, CheckCircle2, ChevronLeft, ChevronRight, Copy, Info, Inbox, RefreshCw, X, XCircle } from 'lucide-react'
import { reportError } from '../lib/monitoring'

const APP_NAME = 'GST Expense Console'

/* ---------- Error boundary ---------- */
export class ErrorBoundary extends Component<{ children: ReactNode; resetKey?: string }, { error: Error | null }> {
  state = { error: null as Error | null }

  static getDerivedStateFromError(error: Error) {
    return { error }
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    console.error('UI crashed', error, info.componentStack)
    reportError(error, { componentStack: info.componentStack })
  }

  componentDidUpdate(prev: { resetKey?: string }) {
    if (prev.resetKey !== this.props.resetKey && this.state.error) this.setState({ error: null })
  }

  render() {
    if (!this.state.error) return this.props.children
    const chunkFailed = /Loading chunk|dynamically imported module|Failed to fetch/i.test(this.state.error.message)
    return (
      <section className="glass card" style={{ maxWidth: 560, margin: '48px auto' }}>
        <Empty
          icon={<AlertTriangle size={24} color="#fca5a5" />}
          title={chunkFailed ? 'A new version is available' : 'Something went wrong on this page'}
          message={chunkFailed ? 'Reload to get the latest console.' : 'The rest of the console still works. Reloading usually fixes this.'}
          action={<button className="btn primary" onClick={() => window.location.reload()}><RefreshCw size={15} /> Reload</button>}
        />
      </section>
    )
  }
}

/* ---------- Pagination ---------- */
export function Pagination({ page, pageSize, total, onPage }: { page: number; pageSize: number; total: number; onPage: (page: number) => void }) {
  const pages = Math.max(1, Math.ceil(total / pageSize))
  if (total <= pageSize && page === 1) return null
  const from = total === 0 ? 0 : (page - 1) * pageSize + 1
  const to = Math.min(total, page * pageSize)
  return (
    <nav className="row between wrap" style={{ marginTop: 14 }} aria-label="Pagination">
      <span className="faint">{from.toLocaleString('en-IN')}–{to.toLocaleString('en-IN')} of {total.toLocaleString('en-IN')}</span>
      <div className="actions">
        <button className="btn sm" disabled={page <= 1} onClick={() => onPage(page - 1)}><ChevronLeft size={14} /> Previous</button>
        <span className="faint" style={{ minWidth: 72, textAlign: 'center' }}>Page {page} / {pages}</span>
        <button className="btn sm" disabled={page >= pages} onClick={() => onPage(page + 1)}>Next <ChevronRight size={14} /></button>
      </div>
    </nav>
  )
}

/** Debounced copy of a value (for search boxes that hit the API). */
export function useDebounced<T>(value: T, delay = 300): T {
  const [debounced, setDebounced] = useState(value)
  useEffect(() => {
    const id = setTimeout(() => setDebounced(value), delay)
    return () => clearTimeout(id)
  }, [value, delay])
  return debounced
}

/** Page number that falls back to 1 whenever `key` (the serialised filters) changes, without an extra fetch. */
export function usePaged(key: string): [number, (page: number) => void] {
  const [state, setState] = useState({ key, page: 1 })
  const page = state.key === key ? state.page : 1
  const setPage = useCallback((next: number) => setState({ key, page: next }), [key])
  return [page, setPage]
}

export function useDocumentTitle(title: string | null | undefined) {
  useEffect(() => {
    document.title = title ? `${title} · ${APP_NAME}` : APP_NAME
  }, [title])
}

export function Backdrop() {
  return (
    <div className="backdrop" aria-hidden>
      <div className="orb a" />
      <div className="orb b" />
      <div className="orb c" />
    </div>
  )
}

export function PageHeader({ title, subtitle, actions }: { title: string; subtitle?: ReactNode; actions?: ReactNode }) {
  useDocumentTitle(title)
  return (
    <div className="topbar">
      <div style={{ minWidth: 0 }}>
        <h1 className="page-title">{title}</h1>
        {subtitle && <div className="page-sub">{subtitle}</div>}
      </div>
      {actions && <div className="actions">{actions}</div>}
    </div>
  )
}

export function Card({ title, subtitle, actions, children, className = '' }: {
  title?: ReactNode
  subtitle?: ReactNode
  actions?: ReactNode
  children: ReactNode
  className?: string
}) {
  return (
    <section className={`glass card ${className}`}>
      {(title || actions) && (
        <div className="card-head">
          <div>
            {title && <h2 className="card-title">{title}</h2>}
            {subtitle && <div className="card-sub">{subtitle}</div>}
          </div>
          {actions && <div className="actions">{actions}</div>}
        </div>
      )}
      {children}
    </section>
  )
}

export function Stat({ icon, label, value, tone, to }: { icon: ReactNode; label: ReactNode; value: ReactNode; tone?: string; to?: string }) {
  const style = tone ? ({ '--tone': tone } as React.CSSProperties) : undefined
  const body = (
    <>
      <div className="stat-icon">{icon}</div>
      <div className="stat-value">{value}</div>
      <div className="stat-label">{label}</div>
    </>
  )
  return to
    ? <Link to={to} className="glass stat stat-link" style={style}>{body}</Link>
    : <div className="glass stat" style={style}>{body}</div>
}

const BADGE_TONES: Record<string, string> = {
  active: 'green', approved: 'green', matched: 'green', ready: 'green', resolved: 'green', paid: 'green', sent_link: 'blue',
  authorized: 'blue', pending: 'amber', created: 'amber', partial: 'amber', processing: 'amber', manual_followup: 'amber',
  returned: 'violet', suspended: 'red', rejected: 'red', failed: 'red', mismatch: 'red', missing_in_2b: 'red', expired: 'red',
  missing_in_books: 'violet', refunded: 'violet', inactive: 'gray',
}

export function Badge({ status, label }: { status: string; label?: string }) {
  const tone = BADGE_TONES[status] ?? 'gray'
  return <span className={`badge ${tone}`}>{label ?? status.replace(/_/g, ' ')}</span>
}

export function Spinner({ small }: { small?: boolean }) {
  return <span className={`spinner ${small ? 'sm' : ''}`} aria-hidden />
}

export function Loading({ label = 'Loading…' }: { label?: string }) {
  return (
    <div className="loading-block" role="status">
      <Spinner />
      <span>{label}</span>
    </div>
  )
}

export function Empty({ icon, title, message, action }: { icon?: ReactNode; title: string; message?: ReactNode; action?: ReactNode }) {
  return (
    <div className="empty">
      <div className="empty-icon">{icon ?? <Inbox size={24} />}</div>
      <h4>{title}</h4>
      {message && <div>{message}</div>}
      {action && <div style={{ marginTop: 16 }}>{action}</div>}
    </div>
  )
}

export function ErrorState({ message, onRetry }: { message: string; onRetry?: () => void }) {
  return (
    <div role="alert">
      <Empty
        icon={<AlertTriangle size={24} color="#fca5a5" />}
        title="Couldn't load this"
        message={message}
        action={onRetry && (
          <button className="btn" onClick={onRetry}><RefreshCw size={15} /> Try again</button>
        )}
      />
    </div>
  )
}

export function Alert({ kind = 'info', children }: { kind?: 'info' | 'error' | 'success'; children: ReactNode }) {
  const Icon = kind === 'error' ? XCircle : kind === 'success' ? CheckCircle2 : Info
  return (
    <div className={`alert ${kind}`} role={kind === 'error' ? 'alert' : kind === 'success' ? 'status' : undefined}>
      <Icon size={16} aria-hidden /><div>{children}</div>
    </div>
  )
}

/* ---------- Modal ---------- */
const FOCUSABLE = 'a[href], button:not([disabled]), input:not([disabled]):not([type="hidden"]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])'
const modalStack: number[] = []
let modalSeq = 0

export function Modal({ title, subtitle, onClose, children, footer, wide, busy, dirty }: {
  title: string
  subtitle?: ReactNode
  onClose: () => void
  children: ReactNode
  footer?: ReactNode
  wide?: boolean
  /** A request is running: Escape, backdrop and the close button do nothing. */
  busy?: boolean
  /** Unsaved input: Escape, backdrop and the close button ask before discarding. */
  dirty?: boolean
}) {
  const ref = useRef<HTMLDivElement>(null)
  const titleId = useId()
  const [askDiscard, setAskDiscard] = useState(false)
  const latest = useRef({ busy, dirty, onClose })
  latest.current = { busy, dirty, onClose }

  const requestClose = useCallback(() => {
    const { busy: running, dirty: unsaved, onClose: close } = latest.current
    if (running) return
    if (unsaved) setAskDiscard(true)
    else close()
  }, [])

  useEffect(() => {
    const id = ++modalSeq
    modalStack.push(id)
    const previous = document.activeElement instanceof HTMLElement ? document.activeElement : null
    const node = ref.current
    if (node && !node.contains(document.activeElement)) (node.querySelector<HTMLElement>(FOCUSABLE) ?? node).focus()

    const onKey = (e: KeyboardEvent) => {
      const box = ref.current
      if (modalStack[modalStack.length - 1] !== id || !box) return
      if (e.key === 'Escape') {
        e.preventDefault()
        requestClose()
      } else if (e.key === 'Tab') {
        const items = [...box.querySelectorAll<HTMLElement>(FOCUSABLE)].filter((el) => el.offsetParent !== null)
        if (!items.length) return e.preventDefault()
        const first = items[0]
        const last = items[items.length - 1]
        if (e.shiftKey && (document.activeElement === first || !box.contains(document.activeElement))) {
          e.preventDefault()
          last.focus()
        } else if (!e.shiftKey && (document.activeElement === last || !box.contains(document.activeElement))) {
          e.preventDefault()
          first.focus()
        }
      }
    }
    document.addEventListener('keydown', onKey)
    document.body.classList.add('modal-open')
    return () => {
      document.removeEventListener('keydown', onKey)
      modalStack.splice(modalStack.indexOf(id), 1)
      if (!modalStack.length) document.body.classList.remove('modal-open')
      if (previous?.isConnected) previous.focus()
    }
  }, [requestClose])

  return (
    <div className="modal-backdrop" onMouseDown={(e) => e.target === e.currentTarget && requestClose()}>
      <div ref={ref} tabIndex={-1} className={`modal ${wide ? 'wide' : ''}`} role="dialog" aria-modal="true" aria-labelledby={titleId}>
        <div className="modal-head">
          <div>
            <div className="modal-title" id={titleId}>{title}</div>
            {subtitle && <div className="card-sub" style={{ marginTop: 4 }}>{subtitle}</div>}
          </div>
          <button className="btn ghost icon" onClick={requestClose} disabled={busy} aria-label="Close"><X size={18} /></button>
        </div>
        <div className="modal-body">{children}</div>
        {askDiscard ? (
          <div className="modal-foot discard" role="alertdialog" aria-label="Discard changes?">
            <span className="muted" style={{ marginRight: 'auto' }}>Discard your unsaved changes?</span>
            <button className="btn" onClick={() => setAskDiscard(false)} autoFocus>Keep editing</button>
            <button className="btn danger" onClick={onClose}>Discard</button>
          </div>
        ) : footer && <div className="modal-foot">{footer}</div>}
      </div>
    </div>
  )
}

export function Field({ label, hint, children, full, group }: {
  label: string
  hint?: string
  children: ReactNode
  full?: boolean
  /** Render as a labelled group (for segmented controls), so clicking the label doesn't trigger the first button. */
  group?: boolean
}) {
  const id = useId()
  const text = <>{label} {hint && <span className="hint">· {hint}</span>}</>
  if (group) {
    return (
      <div className={`field ${full ? 'full' : ''}`} role="group" aria-labelledby={id}>
        <span id={id}>{text}</span>
        {children}
      </div>
    )
  }
  return (
    <label className={`field ${full ? 'full' : ''}`}>
      <span>{text}</span>
      {children}
    </label>
  )
}

export function Toggle({ checked, onChange, label, description, disabled }: {
  checked: boolean
  onChange: (value: boolean) => void
  label: string
  description?: string
  disabled?: boolean
}) {
  return (
    <div className="switch">
      <div>
        <div className="label">{label}</div>
        {description && <div className="desc">{description}</div>}
      </div>
      <label className="toggle">
        <input type="checkbox" checked={checked} disabled={disabled} onChange={(e) => onChange(e.target.checked)} aria-label={label} />
        <span className="track" />
      </label>
    </div>
  )
}

/* ---------- Toasts ---------- */
type ToastKind = 'success' | 'error' | 'info'
interface ToastItem { id: number; kind: ToastKind; message: string }
const ToastContext = createContext<(message: string, kind?: ToastKind) => void>(() => {})

export function ToastProvider({ children }: { children: ReactNode }) {
  const [items, setItems] = useState<ToastItem[]>([])
  const nextId = useRef(1)
  const push = useCallback((message: string, kind: ToastKind = 'success') => {
    const id = nextId.current++
    setItems((list) => [...list, { id, kind, message }])
    setTimeout(() => setItems((list) => list.filter((t) => t.id !== id)), kind === 'error' ? 6500 : 4200)
  }, [])
  return (
    <ToastContext.Provider value={push}>
      {children}
      <div className="toasts" role="status" aria-live="polite">
        {items.map((t) => {
          const Icon = t.kind === 'error' ? XCircle : t.kind === 'info' ? Info : CheckCircle2
          return <div key={t.id} className={`toast ${t.kind}`}><Icon size={18} aria-hidden /><span>{t.message}</span></div>
        })}
      </div>
    </ToastContext.Provider>
  )
}

export const useToast = () => useContext(ToastContext)

/* ---------- Copy to clipboard ---------- */
export function CopyButton({ text, label = 'Copy', compact }: { text: string; label?: string; compact?: boolean }) {
  const toast = useToast()
  const [copied, setCopied] = useState(false)
  async function copy() {
    try {
      await navigator.clipboard.writeText(text)
      setCopied(true)
      setTimeout(() => setCopied(false), 1500)
    } catch {
      toast('Could not copy automatically. Select the text and copy it.', 'error')
    }
  }
  const icon = copied ? <Check size={14} color="#34d399" /> : <Copy size={14} />
  return compact ? (
    <button className="btn ghost icon sm" style={{ width: 26, height: 26 }} title={label} aria-label={label} onClick={copy}>{icon}</button>
  ) : (
    <button className="btn sm" onClick={copy}>{icon} {copied ? 'Copied' : label}</button>
  )
}

/* ---------- Confirm dialog ---------- */
export function Confirm({ title, message, confirmLabel = 'Confirm', danger, busy, onConfirm, onClose }: {
  title: string
  message: ReactNode
  confirmLabel?: string
  danger?: boolean
  busy?: boolean
  onConfirm: () => void
  onClose: () => void
}) {
  return (
    <Modal
      title={title}
      onClose={onClose}
      busy={busy}
      footer={
        <>
          <button className="btn" onClick={onClose} disabled={busy}>Cancel</button>
          <button className={`btn ${danger ? 'danger' : 'primary'}`} onClick={onConfirm} disabled={busy}>
            {busy && <Spinner small />} {confirmLabel}
          </button>
        </>
      }
    >
      <div className="muted">{message}</div>
    </Modal>
  )
}

/* ---------- Data hook ---------- */
export function useAsync<T>(loader: () => Promise<T>, deps: unknown[] = []) {
  const [data, setData] = useState<T | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)
  const loaderRef = useRef(loader)
  loaderRef.current = loader
  const latest = useRef(0)

  const reload = useCallback(async () => {
    const id = ++latest.current
    setLoading(true)
    setError(null)
    try {
      const result = await loaderRef.current()
      if (id === latest.current) setData(result)
    } catch (e) {
      if (id === latest.current) setError(e instanceof Error ? e.message : 'Request failed')
    } finally {
      if (id === latest.current) setLoading(false)
    }
  }, [])

  useEffect(() => {
    void reload()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, deps)

  return { data, error, loading, reload, setData }
}
