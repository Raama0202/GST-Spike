import { lazy, Suspense, type ReactNode } from 'react'
import { Link, Navigate, Route, Routes, useLocation } from 'react-router-dom'
import { Compass } from 'lucide-react'
import { useAuth } from './auth/AuthContext'
import { home, returnPath } from './auth/paths'
import type { Role } from './api/client'
import { Layout } from './components/Layout'
import { Card, Empty, ErrorBoundary, Loading, PageHeader } from './components/ui'
import Login from './pages/Login'

const Profile = lazy(() => import('./pages/Profile'))
const AuditLog = lazy(() => import('./pages/AuditLog'))
const SuperOverview = lazy(() => import('./pages/super/Overview'))
const Companies = lazy(() => import('./pages/super/Companies'))
const CompanyDetail = lazy(() => import('./pages/super/CompanyDetail'))
const Plans = lazy(() => import('./pages/super/Plans'))
const Payments = lazy(() => import('./pages/super/Payments'))
const Dashboard = lazy(() => import('./pages/company/Dashboard'))
const Invoices = lazy(() => import('./pages/company/Invoices'))
const InvoiceDetail = lazy(() => import('./pages/company/InvoiceDetail'))
const Employees = lazy(() => import('./pages/company/Employees'))
const Categories = lazy(() => import('./pages/company/Resources').then((m) => ({ default: m.Categories })))
const Branches = lazy(() => import('./pages/company/Resources').then((m) => ({ default: m.Branches })))
const Announcements = lazy(() => import('./pages/company/Announcements'))
const Notifications = lazy(() => import('./pages/company/Notifications'))
const CompanySettings = lazy(() => import('./pages/company/Settings'))
const Itc = lazy(() => import('./pages/company/Itc'))
const Billing = lazy(() => import('./pages/company/Billing'))
const BillingInvoice = lazy(() => import('./pages/BillingInvoice'))
const publicPage = (name: 'Pricing' | 'Contact' | 'Terms' | 'Privacy' | 'RefundPolicy' | 'ShippingPolicy') =>
  lazy(() => import('./pages/public/Public').then((m) => ({ default: m[name] })))
const PUBLIC_ROUTES = [
  ['/pricing', publicPage('Pricing')],
  ['/contact', publicPage('Contact')],
  ['/terms', publicPage('Terms')],
  ['/privacy', publicPage('Privacy')],
  ['/refund-policy', publicPage('RefundPolicy')],
  ['/shipping-policy', publicPage('ShippingPolicy')],
] as const

function RequireRole({ role, children, allowWhileBilling }: { role: Role; children: ReactNode; allowWhileBilling?: boolean }) {
  const { session } = useAuth()
  if (!session) return <Navigate to="/login" replace />
  if (session.role !== role) return <Navigate to={home(session.role, session.billingRequired)} replace />
  if (session.billingRequired && !allowWhileBilling) return <Navigate to="/billing" replace />
  return <>{children}</>
}

function NotFound() {
  const { session } = useAuth()
  const location = useLocation()
  return (
    <>
      <PageHeader title="Page not found" />
      <Card>
        <Empty
          icon={<Compass size={24} />}
          title="This page doesn't exist"
          message={<>There's nothing at <span className="mono">{location.pathname}</span>. The link may be old or mistyped.</>}
          action={<Link className="btn primary" to={session ? home(session.role, session.billingRequired) : '/login'}>Go to the console home</Link>}
        />
      </Card>
    </>
  )
}

const superOnly = (node: ReactNode) => <RequireRole role="super_admin">{node}</RequireRole>
const companyOnly = (node: ReactNode) => <RequireRole role="company_admin">{node}</RequireRole>

export default function App() {
  const { session } = useAuth()
  const location = useLocation()
  const landing = session ? home(session.role, session.billingRequired) : '/login'
  const toLogin = <Navigate to="/login" replace state={{ from: `${location.pathname}${location.search}` }} />
  return (
    <ErrorBoundary resetKey={location.pathname}>
      <Suspense fallback={<Loading />}>
        <Routes>
          <Route path="/login" element={session ? <Navigate to={returnPath(location.state) ?? landing} replace /> : <Login />} />
          {PUBLIC_ROUTES.map(([path, Page]) => <Route key={path} path={path} element={<Page />} />)}
          <Route element={session ? <Layout /> : toLogin}>
            <Route index element={<Navigate to={landing} replace />} />
            <Route path="/super/overview" element={superOnly(<SuperOverview />)} />
            <Route path="/super/companies" element={superOnly(<Companies />)} />
            <Route path="/super/companies/:id" element={superOnly(<CompanyDetail />)} />
            <Route path="/super/plans" element={superOnly(<Plans />)} />
            <Route path="/super/payments" element={superOnly(<Payments />)} />
            <Route path="/super/payments/:id/invoice" element={superOnly(<BillingInvoice scope="super" />)} />
            <Route path="/super/activity" element={superOnly(<AuditLog scope="super" />)} />

            <Route path="/dashboard" element={companyOnly(<Dashboard />)} />
            <Route path="/invoices" element={companyOnly(<Invoices />)} />
            <Route path="/invoices/:id" element={companyOnly(<InvoiceDetail />)} />
            <Route path="/itc" element={companyOnly(<Itc />)} />
            <Route path="/employees" element={companyOnly(<Employees />)} />
            <Route path="/categories" element={companyOnly(<Categories />)} />
            <Route path="/branches" element={companyOnly(<Branches />)} />
            <Route path="/announcements" element={companyOnly(<Announcements />)} />
            <Route path="/notifications" element={companyOnly(<Notifications />)} />
            <Route path="/activity" element={companyOnly(<AuditLog scope="company" />)} />
            <Route path="/settings" element={companyOnly(<CompanySettings />)} />
            <Route path="/billing" element={<RequireRole role="company_admin" allowWhileBilling><Billing /></RequireRole>} />
            <Route path="/billing/invoices/:id" element={<RequireRole role="company_admin" allowWhileBilling><BillingInvoice scope="company" /></RequireRole>} />

            <Route path="/profile" element={<Profile />} />
            <Route path="*" element={<NotFound />} />
          </Route>
        </Routes>
      </Suspense>
    </ErrorBoundary>
  )
}
