import { Suspense } from 'react'
import { NavLink, Outlet, useNavigate } from 'react-router-dom'
import {
  Bell,
  Building2,
  CreditCard,
  FileText,
  FolderTree,
  LayoutDashboard,
  LogOut,
  MapPin,
  Megaphone,
  Receipt,
  Scale,
  Settings,
  Tags,
  UserCircle,
  Users,
} from 'lucide-react'
import { useAuth } from '../auth/AuthContext'
import { initials } from '../lib/format'
import { API_ORIGIN } from '../api/client'
import { Loading } from './ui'

const superNav = [
  { label: 'Overview', items: [
    { to: '/super/overview', icon: LayoutDashboard, text: 'Overview' },
  ] },
  { label: 'Tenants', items: [
    { to: '/super/companies', icon: Building2, text: 'Companies' },
    { to: '/super/plans', icon: Tags, text: 'Subscription plans' },
    { to: '/super/payments', icon: CreditCard, text: 'Payments' },
  ] },
]

const billingOnlyNav = [
  { label: 'Account', items: [
    { to: '/billing', icon: CreditCard, text: 'Billing & renewal' },
  ] },
]

const companyNav = [
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
    { to: '/notifications', icon: Bell, text: 'Activity' },
    { to: '/settings', icon: Settings, text: 'Company settings' },
    { to: '/billing', icon: CreditCard, text: 'Billing' },
  ] },
]

export function Layout() {
  const { session, logout } = useAuth()
  const navigate = useNavigate()
  const isSuper = session?.role === 'super_admin'
  const groups = isSuper ? superNav : session?.billingRequired ? billingOnlyNav : companyNav

  return (
    <div className="shell">
      <aside className="sidebar">
        <div className="brand">
          <div className="brand-mark"><FileText size={20} strokeWidth={2.4} /></div>
          <div>
            <div className="brand-name">GST Expense</div>
            <div className="brand-sub">{isSuper ? 'Super admin' : 'Company console'}</div>
          </div>
        </div>
        {groups.map((group) => (
          <div key={group.label}>
            <div className="nav-label">{group.label}</div>
            {group.items.map(({ to, icon: Icon, text }) => (
              <NavLink key={to} to={to} className={({ isActive }) => `nav-link ${isActive ? 'active' : ''}`}>
                <Icon size={18} /> {text}
              </NavLink>
            ))}
          </div>
        ))}
        <div className="nav-label">Account</div>
        <NavLink to="/profile" className={({ isActive }) => `nav-link ${isActive ? 'active' : ''}`}>
          <UserCircle size={18} /> Profile
        </NavLink>
        <div className="sidebar-foot">
          <div className="user-chip">
            <div className="avatar">{initials(session?.email ?? '')}</div>
            <div className="user-meta">
              <div className="email" title={session?.email}>{session?.email}</div>
              <div className="role">{new URL(API_ORIGIN).host}</div>
            </div>
            <button
              className="btn ghost icon sm"
              title="Sign out"
              aria-label="Sign out"
              onClick={async () => { await logout(); navigate('/login', { replace: true }) }}
            >
              <LogOut size={16} />
            </button>
          </div>
        </div>
      </aside>
      <main className="main">
        <Suspense fallback={<Loading />}>
          <Outlet />
        </Suspense>
      </main>
    </div>
  )
}
