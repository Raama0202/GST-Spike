import { ReactNode, useMemo } from 'react';
import { Camera, ChartLineUp, Crown, ShieldCheck, SignOut } from 'phosphor-react';
import { NavLink, Navigate, Route, Routes, useLocation, useNavigate } from 'react-router-dom';
import { Login } from './Login';
import { AdminPortal } from './admin/AdminPortal';
import { ClientApp } from './client/ClientApp';
import { SuperAdmin } from './super/SuperAdmin';
import { canAccess, homeForRole, useSession } from '../store/session';

export function App() {
  const location = useLocation();
  const navigate = useNavigate();
  const token = useSession((s) => s.token);
  const user = useSession((s) => s.user);
  const clearSession = useSession((s) => s.clearSession);

  const nav = useMemo(() => {
    const role = user?.role;
    if (!role) return [];
    if (role === 'super_admin') return [{ to: '/super-admin', label: 'Control', icon: Crown, note: 'Accounts & subscriptions' }];
    if (role === 'worker' || role === 'supervisor') return [{ to: '/client', label: 'Capture', icon: Camera, note: 'Upload bills' }];
    return [
      { to: '/admin', label: 'Operations', icon: ChartLineUp, note: 'Invoices & GST' },
      { to: '/client', label: 'Capture', icon: Camera, note: 'Upload bills' },
    ];
  }, [user?.role]);

  const isAuthPage = location.pathname === '/login';

  return (
    <div className={isAuthPage ? 'app app-auth' : 'app'}>
      {!isAuthPage && (
        <aside className="sidebar">
          <div className="brand-mark"><ShieldCheck size={21} weight="duotone" /><span>GST Suite</span></div>
          <nav>
            {nav.map((item) => {
              const Icon = item.icon;
              return (
                <NavLink key={item.to} to={item.to} className={({ isActive }) => (isActive ? 'product-link active' : 'product-link')}>
                  <Icon size={19} />
                  <span><b>{item.label}</b><small>{item.note}</small></span>
                </NavLink>
              );
            })}
          </nav>
          {user && (
            <div className="cross-link session-card">
              <div>
                <b>{user.name}</b>
                <p>{user.email}{user.companyCode ? ` · ${user.companyCode}` : ''}</p>
              </div>
              <button
                type="button"
                className="text-link"
                onClick={() => {
                  clearSession();
                  navigate('/login');
                }}
              >
                <SignOut size={16} /> Sign out
              </button>
            </div>
          )}
        </aside>
      )}
      <main>
        {!isAuthPage && (
          <header className="topbar compact">
            <div>
              <span className="system-pill">{user?.role?.replaceAll('_', ' ') ?? 'Guest'}</span>
              <h1>{titleFor(location.pathname)}</h1>
            </div>
          </header>
        )}
        <Routes>
          <Route path="/" element={<Navigate to={token ? homeForRole(user?.role) : '/login'} replace />} />
          <Route path="/login" element={<Login />} />
          <Route path="/super-admin" element={<ProtectedRoute path="/super-admin"><SuperAdmin /></ProtectedRoute>} />
          <Route path="/admin" element={<ProtectedRoute path="/admin"><AdminPortal /></ProtectedRoute>} />
          <Route path="/client" element={<ProtectedRoute path="/client"><ClientApp /></ProtectedRoute>} />
        </Routes>
      </main>
    </div>
  );
}

function ProtectedRoute({ children, path }: { children: ReactNode; path: string }) {
  const token = useSession((s) => s.token);
  const user = useSession((s) => s.user);
  if (!token || !user) return <Navigate to="/login" replace />;
  if (!canAccess(user.role, path)) return <Navigate to={homeForRole(user.role)} replace />;
  return children;
}

function titleFor(path: string) {
  if (path.includes('admin') && !path.includes('super')) return 'GST Operations';
  if (path.includes('client')) return 'Bill Capture';
  if (path.includes('login')) return 'Access';
  return 'Platform Control';
}
