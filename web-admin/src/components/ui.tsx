import {
  Component,
  createContext,
  useCallback,
  useContext,
  useEffect,
  useRef,
  useState,
  type ErrorInfo,
  type ReactNode,
} from 'react'
import { AlertTriangle, CheckCircle2, ChevronLeft, ChevronRight, Info, Inbox, RefreshCw, X, XCircle } from 'lucide-react'

/* ---------- Error boundary ---------- */
export class ErrorBoundary extends Component<{ children: ReactNode; resetKey?: string }, { error: Error | null }> {
  state = { error: null as Error | null }

  static getDerivedStateFromError(error: Error) {
    return { error }
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    console.error('UI crashed', error, info.componentStack)
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
    <div className="row between" style={{ marginTop: 14 }}>
      <span className="faint">{from.toLocaleString('en-IN')}–{to.toLocaleString('en-IN')} of {total.toLocaleString('en-IN')}</span>
      <div className="actions">
        <button className="btn sm" disabled={page <= 1} onClick={() => onPage(page - 1)}><ChevronLeft size={14} /> Previous</button>
        <span className="faint" style={{ minWidth: 72, textAlign: 'center' }}>Page {page} / {pages}</span>
        <button className="btn sm" disabled={page >= pages} onClick={() => onPage(page + 1)}>Next <ChevronRight size={14} /></button>
      </div>
    </div>
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

export function Backdrop() {
  return (
    <div className="backdrop" aria-hidden>
      <div className="orb a" />
      <div className="orb b" />
      <div className="orb c" />
    </div>
  )
}

export function PageHeader({ title, subtitle, actions }: { title: string; subtitle?: string; actions?: ReactNode }) {
  return (
    <div className="topbar">
      <div>
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
            {title && <div className="card-title">{title}</div>}
            {subtitle && <div className="card-sub">{subtitle}</div>}
          </div>
          {actions && <div className="actions">{actions}</div>}
        </div>
      )}
      {children}
    </section>
  )
}

export function Stat({ icon, label, value, tone }: { icon: ReactNode; label: string; value: ReactNode; tone?: string }) {
  return (
    <div className="glass stat" style={tone ? ({ '--tone': tone } as React.CSSProperties) : undefined}>
      <div className="stat-icon">{icon}</div>
      <div className="stat-value">{value}</div>
      <div className="stat-label">{label}</div>
    </div>
  )
}

const BADGE_TONES: Record<string, string> = {
  active: 'green', approved: 'green', matched: 'green', ready: 'green', resolved: 'green', sent_link: 'blue',
  pending: 'amber', partial: 'amber', processing: 'amber', manual_followup: 'amber', returned: 'violet',
  suspended: 'red', rejected: 'red', failed: 'red', mismatch: 'red', missing_in_2b: 'red',
  missing_in_books: 'violet', inactive: 'gray',
}

export function Badge({ status, label }: { status: string; label?: string }) {
  const tone = BADGE_TONES[status] ?? 'gray'
  return <span className={`badge ${tone}`}>{label ?? status.replace(/_/g, ' ')}</span>
}

export function Spinner({ small }: { small?: boolean }) {
  return <span className={`spinner ${small ? 'sm' : ''}`} />
}

export function Loading({ label = 'Loading…' }: { label?: string }) {
  return (
    <div className="loading-block">
      <Spinner />
      <span>{label}</span>
    </div>
  )
}

export function Empty({ icon, title, message, action }: { icon?: ReactNode; title: string; message?: string; action?: ReactNode }) {
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
    <Empty
      icon={<AlertTriangle size={24} color="#fca5a5" />}
      title="Couldn't load this"
      message={message}
      action={onRetry && (
        <button className="btn" onClick={onRetry}><RefreshCw size={15} /> Try again</button>
      )}
    />
  )
}

export function Alert({ kind = 'info', children }: { kind?: 'info' | 'error' | 'success'; children: ReactNode }) {
  const Icon = kind === 'error' ? XCircle : kind === 'success' ? CheckCircle2 : Info
  return <div className={`alert ${kind}`}><Icon size={16} /><div>{children}</div></div>
}

export function Modal({ title, subtitle, onClose, children, footer, wide }: {
  title: string
  subtitle?: string
  onClose: () => void
  children: ReactNode
  footer?: ReactNode
  wide?: boolean
}) {
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && onClose()
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [onClose])
  return (
    <div className="modal-backdrop" onMouseDown={(e) => e.target === e.currentTarget && onClose()}>
      <div className={`modal ${wide ? 'wide' : ''}`} role="dialog" aria-modal="true" aria-label={title}>
        <div className="modal-head">
          <div>
            <div className="modal-title">{title}</div>
            {subtitle && <div className="card-sub" style={{ marginTop: 4 }}>{subtitle}</div>}
          </div>
          <button className="btn ghost icon" onClick={onClose} aria-label="Close"><X size={18} /></button>
        </div>
        <div className="modal-body">{children}</div>
        {footer && <div className="modal-foot">{footer}</div>}
      </div>
    </div>
  )
}

export function Field({ label, hint, children, full }: { label: string; hint?: string; children: ReactNode; full?: boolean }) {
  return (
    <label className={`field ${full ? 'full' : ''}`}>
      <span>{label} {hint && <span className="hint">· {hint}</span>}</span>
      {children}
    </label>
  )
}

export function Toggle({ checked, onChange, label, description }: {
  checked: boolean
  onChange: (value: boolean) => void
  label: string
  description?: string
}) {
  return (
    <div className="switch">
      <div>
        <div className="label">{label}</div>
        {description && <div className="desc">{description}</div>}
      </div>
      <label className="toggle">
        <input type="checkbox" checked={checked} onChange={(e) => onChange(e.target.checked)} aria-label={label} />
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
    setTimeout(() => setItems((list) => list.filter((t) => t.id !== id)), 4200)
  }, [])
  return (
    <ToastContext.Provider value={push}>
      {children}
      <div className="toasts" role="status">
        {items.map((t) => {
          const Icon = t.kind === 'error' ? XCircle : t.kind === 'info' ? Info : CheckCircle2
          return <div key={t.id} className={`toast ${t.kind}`}><Icon size={18} /><span>{t.message}</span></div>
        })}
      </div>
    </ToastContext.Provider>
  )
}

export const useToast = () => useContext(ToastContext)

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
