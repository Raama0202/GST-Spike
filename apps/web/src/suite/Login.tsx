import { FormEvent, useState } from 'react';
import { Navigate, useNavigate } from 'react-router-dom';
import { toast } from 'sonner';
import { api, setAuthToken } from '../lib/api';
import { homeForRole, useSession } from '../store/session';
import { Button, Field, Panel } from '../components/ui';

export function Login() {
  const token = useSession((s) => s.token);
  const user = useSession((s) => s.user);
  const setSession = useSession((s) => s.setSession);
  const navigate = useNavigate();
  const [mode, setMode] = useState<'login' | 'register'>('login');
  const [busy, setBusy] = useState(false);
  const [loginForm, setLoginForm] = useState({ email: '', password: '' });
  const [regForm, setRegForm] = useState({ businessName: '', name: '', email: '', password: '', phone: '' });

  if (token && user) return <Navigate to={homeForRole(user.role)} replace />;

  async function submitLogin(event: FormEvent) {
    event.preventDefault();
    setBusy(true);
    try {
      const result = await api.login(loginForm.email.trim(), loginForm.password);
      setAuthToken(result.token);
      setSession(result);
      toast.success(`Welcome, ${result.user.name}`);
      navigate(homeForRole(result.user.role));
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'Login failed');
    } finally {
      setBusy(false);
    }
  }

  async function submitRegister(event: FormEvent) {
    event.preventDefault();
    setBusy(true);
    try {
      const result = await api.register({
        businessName: regForm.businessName.trim(),
        name: regForm.name.trim(),
        email: regForm.email.trim(),
        password: regForm.password,
        phone: regForm.phone.trim() || undefined,
      });
      setAuthToken(result.token);
      setSession(result);
      toast.success('Account created — 14-day trial started');
      navigate(homeForRole(result.user.role));
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'Registration failed');
    } finally {
      setBusy(false);
    }
  }

  return (
    <Panel className="login-panel">
      <div className="auth-tabs">
        <button type="button" className={mode === 'login' ? 'active' : ''} onClick={() => setMode('login')}>Sign in</button>
        <button type="button" className={mode === 'register' ? 'active' : ''} onClick={() => setMode('register')}>Register business</button>
      </div>
      {mode === 'login' ? (
        <form onSubmit={submitLogin} className="stack">
          <h2>Sign in</h2>
          <p className="muted">Use your business account. Field workers go to capture; owners to admin; platform admins to control. Demo: super@gst.local / owner@gst.local / worker@gst.local — password demo123</p>
          <Field label="Email" type="email" value={loginForm.email} onChange={(e) => setLoginForm({ ...loginForm, email: e.target.value })} required autoComplete="username" />
          <Field label="Password" type="password" value={loginForm.password} onChange={(e) => setLoginForm({ ...loginForm, password: e.target.value })} required autoComplete="current-password" />
          <Button type="submit" disabled={busy}>{busy ? 'Signing in…' : 'Sign in'}</Button>
        </form>
      ) : (
        <form onSubmit={submitRegister} className="stack">
          <h2>Register business</h2>
          <p className="muted">Creates your company profile and owner login. Your business name is used to ignore buyer labels on bills so only the vendor is saved.</p>
          <Field label="Business name" value={regForm.businessName} onChange={(e) => setRegForm({ ...regForm, businessName: e.target.value })} required />
          <Field label="Your name" value={regForm.name} onChange={(e) => setRegForm({ ...regForm, name: e.target.value })} required />
          <Field label="Work email" type="email" value={regForm.email} onChange={(e) => setRegForm({ ...regForm, email: e.target.value })} required />
          <Field label="Phone" value={regForm.phone} onChange={(e) => setRegForm({ ...regForm, phone: e.target.value })} />
          <Field label="Password" type="password" value={regForm.password} onChange={(e) => setRegForm({ ...regForm, password: e.target.value })} required minLength={6} />
          <Button type="submit" disabled={busy}>{busy ? 'Creating…' : 'Create account'}</Button>
        </form>
      )}
    </Panel>
  );
}
