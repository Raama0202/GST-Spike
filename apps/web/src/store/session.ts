import { create } from 'zustand';
import { persist } from 'zustand/middleware';
import { setAuthToken } from '../lib/api';

type User = { name: string; email: string; role: string; companyCode?: string };

type Session = {
  token?: string;
  user?: User;
  companyCode: string;
  setSession: (session: { token: string; user: User }) => void;
  setCompanyCode: (companyCode: string) => void;
  clearSession: () => void;
};

export const useSession = create<Session>()(persist((set) => ({
  companyCode: '',
  setSession: ({ token, user }) => {
    setAuthToken(token);
    set({ token, user, companyCode: user.companyCode ?? '' });
  },
  setCompanyCode: (companyCode) => set({ companyCode }),
  clearSession: () => {
    setAuthToken(undefined);
    set({ token: undefined, user: undefined, companyCode: '' });
  },
}), {
  name: 'gst-suite-session',
  onRehydrateStorage: () => (state) => {
    if (state?.token) setAuthToken(state.token);
  },
}));

export function homeForRole(role?: string) {
  if (role === 'super_admin') return '/super-admin';
  if (role === 'worker' || role === 'supervisor') return '/client';
  return '/admin';
}

export function canAccess(role: string | undefined, path: string) {
  if (!role) return false;
  if (path.startsWith('/super-admin')) return role === 'super_admin';
  if (path.startsWith('/client')) return ['worker', 'supervisor', 'owner', 'manager', 'accountant', 'chartered_accountant'].includes(role);
  if (path.startsWith('/admin')) return ['owner', 'manager', 'accountant', 'chartered_accountant', 'supervisor'].includes(role);
  return true;
}
