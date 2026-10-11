import { lazy, Suspense, type ReactNode } from 'react'
import { Navigate, Route, Routes, useLocation } from 'react-router-dom'
import { useAuth } from './auth/AuthContext'
import type { Role } from './api/client'
import { Layout } from './components/Layout'
import { ErrorBoundary, Loading } from './components/ui'
import Login from './pages/Login'

const Profile = lazy(() => import('./pages/Profile'))
const SuperOverview = lazy(() => import('./pages/super/Overview'))
const Companies = lazy(() => import('./pages/super/Companies'))
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

function home(role: Role, billingRequired?: boolean) {
  if (role === 'super_admin') return '/super/overview'
  return billingRequired ? '/billing' : '/dashboard'
}

function RequireRole({ role, children, allowWhileBilling }: { role: Role; children: ReactNode; allowWhileBilling?: boolean }) {
  const { session } = useAuth()
  if (!session) return <Navigate to="/login" replace />
  if (session.role !== role) return <Navigate to={home(session.role, session.billingRequired)} replace />
  if (session.billingRequired && !allowWhileBilling) return <Navigate to="/billing" replace />
  return <>{children}</>
}

export default function App() {
  const { session } = useAuth()
  const location = useLocation()
  const landing = session ? home(session.role, session.billingRequired) : '/login'
  return (
    <ErrorBoundary resetKey={location.pathname}>
      <Suspense fallback={<Loading />}>
        <Routes>
          <Route path="/login" element={session ? <Navigate to={landing} replace /> : <Login />} />
          <Route element={session ? <Layout /> : <Navigate to="/login" replace />}>
            <Route path="/super/overview" element={<RequireRole role="super_admin"><SuperOverview /></RequireRole>} />
            <Route path="/super/companies" element={<RequireRole role="super_admin"><Companies /></RequireRole>} />
            <Route path="/super/plans" element={<RequireRole role="super_admin"><Plans /></RequireRole>} />
            <Route path="/super/payments" element={<RequireRole role="super_admin"><Payments /></RequireRole>} />

            <Route path="/dashboard" element={<RequireRole role="company_admin"><Dashboard /></RequireRole>} />
            <Route path="/invoices" element={<RequireRole role="company_admin"><Invoices /></RequireRole>} />
            <Route path="/invoices/:id" element={<RequireRole role="company_admin"><InvoiceDetail /></RequireRole>} />
            <Route path="/itc" element={<RequireRole role="company_admin"><Itc /></RequireRole>} />
            <Route path="/employees" element={<RequireRole role="company_admin"><Employees /></RequireRole>} />
            <Route path="/categories" element={<RequireRole role="company_admin"><Categories /></RequireRole>} />
            <Route path="/branches" element={<RequireRole role="company_admin"><Branches /></RequireRole>} />
            <Route path="/announcements" element={<RequireRole role="company_admin"><Announcements /></RequireRole>} />
            <Route path="/notifications" element={<RequireRole role="company_admin"><Notifications /></RequireRole>} />
            <Route path="/settings" element={<RequireRole role="company_admin"><CompanySettings /></RequireRole>} />
            <Route path="/billing" element={<RequireRole role="company_admin" allowWhileBilling><Billing /></RequireRole>} />

            <Route path="/profile" element={<Profile />} />
          </Route>
          <Route path="*" element={<Navigate to={landing} replace />} />
        </Routes>
      </Suspense>
    </ErrorBoundary>
  )
}
