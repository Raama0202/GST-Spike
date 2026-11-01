import { Suspense, useEffect, useRef, useState } from 'react'
import { NavLink, Outlet, useLocation, useNavigate } from 'react-router-dom'
import {
  Bell,
  Building,
  Building2,
  CreditCard,
  FileText,
  FolderTree,
  History,
  LayoutDashboard,
  LogOut,
  MapPin,
  Megaphone,
  Menu,
  Receipt,
  Scale,
  Settings,
  Tags,
  UserCircle,
  Users,
  X,
} from 'lucide-react'
import { useAuth } from '../auth/AuthContext'
import { initials } from '../lib/format'
import { api } from '../api/client'
import { Alert, Loading } from './ui'

type NavGroup = { label: string; items: { to: string; icon: typeof Bell; text: string }[] }

const superNav: NavGroup[] = [
  { label: 'Overview', items: [
    { to: '/super/overview', icon: LayoutDashboard, text: 'Overview' },
  ] },
  { label: 'Tenants', items: [
    { to: '/super/companies', icon: Building2, text: 'Companies' },
    { to: '/super/plans', icon: Tags, text: 'Subscription plans' },
    { to: '/super/payments', icon: CreditCard, text: 'Payments' },
    { to: '/super/activity', icon: History, text: 'Activity log' },
  ] },
]

const companyNav: NavGroup[] = [
  { label: 'Overview', items: [
    { to: '/dashboard', icon: LayoutDashboard, text: 'Dashboard' },
  ] },
  { label: 'Expenses', items: [
    { to: '/invoices', icon: Receipt, text: 'Invoices' },
    { to: '/itc', icon: Scale, text: 'ITC reconciliation' },
  ] },
  { label: 'Organisation', items: [
    { to: '/employees', icon: Users, text: 'Employees' },
    { to: '/categories', icon: FolderTree, text: 'Categories' },
    { to: '/branches', icon: MapPin, text: 'Branches' },
    { to: '/announcements', icon: Megaphone, text: 'Announcements' },
    { to: '/notifications', icon: Bell, text: 'Notifications sent' },
    { to: '/activity', icon: History, text: 'Activity log' },
    { to: '/settings', icon: Settings, text: 'Company settings' },
    { to: '/billing', icon: CreditCard, text: 'Billing' },
  ] },
]

const linkClass = ({ isActive }: { isActive: boolean }) => `nav-link ${isActive ? 'active' : ''}`

export function Layout() {
  const { session, logout, updateSession, suspendedMessage } = useAuth()
  const navigate = useNavigate()
  const location = useLocation()
  const [open, setOpen] = useState(false)
  const closeRef = useRef<HTMLButtonElement>(null)
  const isSuper = session?.role === 'super_admin'
  const billingOnly = !isSuper && Boolean(session?.billingRequired)
  const groups = isSuper ? superNav : billingOnly ? [] : companyNav
  const needsName = session?.role === 'company_admin' && !session.billingRequired && !session.companyName

  useEffect(() => setOpen(false), [location.pathname])

  useEffect(() => {
    if (!open) return
    closeRef.current?.focus()
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && setOpen(false)
    document.addEventListener('keydown', onKey)
    return () => document.removeEventListener('keydown', onKey)
  }, [open])

  useEffect(() => {
    if (!needsName) return
    let cancelled = false
    api<{ name: string }>('/admin/company/settings')
      .then((s) => { if (!cancelled) updateSession({ companyName: s.name }) })
      .catch(() => {})
    return () => { cancelled = true }
  }, [needsName, updateSession])

  const workspace = isSuper ? 'Super admin' : session?.companyName || 'Company console'

  async function signOut() {
    await logout()
    navigate('/login', { replace: true })
  }

  return (
    <div className={`shell ${open ? 'nav-open' : ''}`}>
      <a className="skip-link" href="#main" onClick={(e) => { e.preventDefault(); document.getElementById('main')?.focus() }}>Skip to content</a>
      <header className="mobile-bar">
        <button className="btn ghost icon" aria-label="Open menu" aria-expanded={open} aria-controls="sidebar" onClick={() => setOpen(true)}>
          <Menu size={20} />
        </button>
        <div className="brand-mark sm"><FileText size={16} strokeWidth={2.4} /></div>
        <div className="mobile-title" title={workspace}>{workspace}</div>
      </header>
      {open && <div className="drawer-scrim" onClick={() => setOpen(false)} aria-hidden />}
      <aside id="sidebar" className="sidebar" aria-label="Main navigation">
        <div className="brand">
          <div className="brand-mark"><FileText size={20} strokeWidth={2.4} /></div>
          <div style={{ minWidth: 0, flex: 1 }}>
            <div className="brand-name">GST Expense</div>
            <div className="brand-sub">{isSuper ? 'Super admin' : 'Company console'}</div>
          </div>
          <button ref={closeRef} className="btn ghost icon drawer-close" aria-label="Close menu" onClick={() => setOpen(false)}><X size={18} /></button>
        </div>
        {!isSuper && session?.companyName && (
          <div className="workspace-chip" title={session.companyName}>
            <Building size={15} aria-hidden /> <span>{session.companyName}</span>
          </div>
        )}
        <nav className="sidebar-nav">
          {groups.map((group) => (
            <div key={group.label}>
              <div className="nav-label">{group.label}</div>
              {group.items.map(({ to, icon: Icon, text }) => (
                <NavLink key={to} to={to} className={linkClass}>
                  <Icon size={18} aria-hidden /> {text}
                </NavLink>
              ))}
            </div>
          ))}
          <div className="nav-label">Account</div>
          {billingOnly && (
            <NavLink to="/billing" className={linkClass}><CreditCard size={18} aria-hidden /> Billing & renewal</NavLink>
          )}
          <NavLink to="/profile" className={linkClass}><UserCircle size={18} aria-hidden /> Profile</NavLink>
        </nav>
        <div className="sidebar-foot">
          <div className="user-chip">
            <div className="avatar" aria-hidden>{initials(session?.email ?? '')}</div>
            <div className="user-meta">
              <div className="email" title={session?.email}>{session?.email}</div>
              <div className="role">{isSuper ? 'Super admin' : 'Company admin'}</div>
            </div>
            <button className="btn ghost icon sm" title="Sign out" aria-label="Sign out" onClick={signOut}>
              <LogOut size={16} />
            </button>
          </div>
        </div>
      </aside>
      <main className="main" id="main" tabIndex={-1}>
        {suspendedMessage && <div style={{ marginBottom: 18 }}><Alert kind="error">{suspendedMessage}</Alert></div>}
        <Suspense fallback={<Loading />}>
          <Outlet />
        </Suspense>
      </main>
    </div>
  )
}
