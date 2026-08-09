const API_URL = import.meta.env.VITE_API_URL ?? 'http://localhost:4000/api';
const ASSET_URL = import.meta.env.VITE_ASSET_URL ?? 'http://localhost:4000';

let authToken: string | undefined;

export function setAuthToken(token?: string) {
  authToken = token;
}

function getAuthToken() {
  if (authToken) return authToken;
  try {
    const stored = window.localStorage.getItem('gst-suite-session');
    return stored ? JSON.parse(stored).state?.token : undefined;
  } catch {
    return undefined;
  }
}

export type Company = {
  _id: string;
  name: string;
  code: string;
  status: 'active' | 'suspended';
  subscriptionExpiresAt: string;
  plan?: string;
  featureFlags: string[];
  storageMb: number;
  phone?: string;
};

export type Invoice = {
  _id: string;
  vendorName: string;
  gstin: string;
  invoiceNumber: string;
  invoiceDate: string;
  vendorPhone: string;
  taxableAmount: number;
  gstAmount: number;
  invoiceAmount: number;
  ocrConfidence: number;
  status: string;
  status2a?: string;
  status2b?: string;
  amount2a?: number;
  amount2b?: number;
  companyCode: string;
  notes?: string;
  imageUrl?: string;
};

export type Reminder = {
  _id: string;
  vendor: string;
  channel: string;
  status: string;
  amount: number;
  phone?: string;
  invoiceNumber?: string;
  simulated?: boolean;
  providerDetail?: string;
};

export type GstrMatchRow = {
  _id?: string;
  invoiceNumber: string;
  invoiceAmount?: number;
  portalAmount?: number;
  vendorName?: string;
  vendorPhone?: string;
  gstin?: string;
  invoiceDate?: string;
  matchStatus?: string;
};

export type GstrBucket = {
  matched: GstrMatchRow[];
  amountMismatch: GstrMatchRow[];
  inBooksNotInForm: GstrMatchRow[];
  inFormNotInBooks: GstrMatchRow[];
  counts: {
    matched: number;
    amountMismatch: number;
    inBooksNotInForm: number;
    inFormNotInBooks: number;
    unchecked: number;
  };
};

export type GstrSummary = {
  companyCode: string;
  form2A: GstrBucket;
  form2B: GstrBucket;
  smsReadyMissing2A: number;
};

export type AccountUser = { _id: string; name: string; email: string; role: string; companyCode?: string; status: string; phone?: string };

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const headers: Record<string, string> = { ...(init?.headers as Record<string, string> ?? {}) };
  if (!(init?.body instanceof FormData)) headers['Content-Type'] = headers['Content-Type'] ?? 'application/json';
  const token = getAuthToken();
  if (token) headers.Authorization = `Bearer ${token}`;

  const response = await fetch(`${API_URL}${path}`, { ...init, headers });
  if (!response.ok) {
    let message = await response.text();
    try {
      const json = JSON.parse(message) as { message?: string | string[] };
      message = Array.isArray(json.message) ? json.message.join(', ') : (json.message ?? message);
    } catch { /* keep text */ }
    throw new Error(message || `Request failed (${response.status})`);
  }
  if (response.status === 204) return undefined as T;
  return response.json();
}

export function assetUrl(path?: string) {
  if (!path) return '';
  if (path.startsWith('http')) return path;
  return `${ASSET_URL}${path}`;
}

export const api = {
  login: (email: string, password: string) => request<{ token: string; user: { name: string; email: string; role: string; companyCode?: string } }>('/auth/login', { method: 'POST', body: JSON.stringify({ email, password }) }),
  register: (body: { businessName: string; name: string; email: string; password: string; phone?: string }) =>
    request<{ token: string; user: { name: string; email: string; role: string; companyCode?: string } }>('/auth/register', { method: 'POST', body: JSON.stringify(body) }),
  overview: () => request<Record<string, unknown>>('/overview'),
  companies: () => request<Company[]>('/companies'),
  createCompany: (body: { name: string; code?: string; subscriptionExpiresAt?: string; plan?: string; ownerEmail?: string; ownerName?: string; ownerPassword?: string; phone?: string }) =>
    request<Company>('/companies', { method: 'POST', body: JSON.stringify(body) }),
  setCompanyStatus: (code: string, status: 'active' | 'suspended') => request<Company>(`/companies/${code}/status`, { method: 'PATCH', body: JSON.stringify({ status }) }),
  extendSubscription: (code: string, body: { subscriptionExpiresAt: string; plan?: string }) =>
    request<Company>(`/companies/${code}/subscription`, { method: 'PATCH', body: JSON.stringify(body) }),
  setFeatures: (code: string, featureFlags: string[]) => request<Company>(`/companies/${code}/features`, { method: 'PATCH', body: JSON.stringify({ featureFlags }) }),
  users: (companyCode?: string) => request<AccountUser[]>(`/users${companyCode ? `?companyCode=${companyCode}` : ''}`),
  setUserStatus: (id: string, status: 'active' | 'locked') => request<AccountUser>(`/users/${id}/status`, { method: 'PATCH', body: JSON.stringify({ status }) }),
  dashboard: (companyCode: string) => request<Record<string, number>>(`/dashboard?companyCode=${encodeURIComponent(companyCode)}`),
  invoices: (companyCode: string) => request<Invoice[]>(`/invoices?companyCode=${encodeURIComponent(companyCode)}`),
  invoice: (id: string) => request<Invoice>(`/invoice/${id}`),
  captureInvoice: async (companyCode: string, file: File) => {
    const form = new FormData();
    form.append('image', file);
    form.append('companyCode', companyCode);
    return request<Invoice>('/invoice/capture', { method: 'POST', body: form });
  },
  updateInvoice: (id: string, invoice: Partial<Invoice> & { status?: string }) =>
    request<Invoice>(`/invoice/${id}`, { method: 'PATCH', body: JSON.stringify(invoice) }),
  reconcile: (companyCode: string, formType: '2A' | '2B', csv: string) =>
    request<GstrSummary>('/gst/import', { method: 'POST', body: JSON.stringify({ companyCode, formType, csv }) }),
  gstrSummary: (companyCode: string) => request<GstrSummary>(`/gst/summary?companyCode=${encodeURIComponent(companyCode)}`),
  smsMissing: (companyCode: string, formType: '2A' | '2B' = '2A') =>
    request<{ sent: number; failed: number; results: Array<{ simulated?: boolean; ok: boolean }> }>('/gst/sms-missing', {
      method: 'POST',
      body: JSON.stringify({ companyCode, formType }),
    }),
  reminders: (companyCode: string) => request<Reminder[]>(`/reminders?companyCode=${encodeURIComponent(companyCode)}`),
  sendReminder: (body: { companyCode: string; vendor: string; channel: string; amount: number; phone?: string; invoiceNumber?: string; invoiceId?: string; message?: string }) =>
    request<Reminder>('/reminders/send', { method: 'POST', body: JSON.stringify(body) }),
  subscription: (companyCode: string) => request<Company>(`/subscription?companyCode=${encodeURIComponent(companyCode)}`),
  audit: () => request<Array<Record<string, unknown>>>('/audit'),
  paymentConfig: () => request<{
    keyId: string;
    enabled: boolean;
    currency: string;
    plans: { monthly: { amountPaise: number; label: string; days: number }; yearly: { amountPaise: number; label: string; days: number } };
  }>('/payments/config'),
  createPaymentOrder: (companyCode: string, plan: 'monthly' | 'yearly') =>
    request<{ orderId: string; amount: number; currency: string; keyId: string; simulated: boolean; companyName: string; plan: string }>('/payments/create-order', {
      method: 'POST',
      body: JSON.stringify({ companyCode, plan }),
    }),
  verifyPayment: (body: { companyCode: string; plan: 'monthly' | 'yearly'; orderId: string; paymentId: string; signature?: string }) =>
    request<{ ok: boolean; subscriptionExpiresAt: string; simulated?: boolean }>('/payments/verify', { method: 'POST', body: JSON.stringify(body) }),
  paymentHistory: (companyCode?: string) =>
    request<Array<Record<string, unknown>>>(`/payments/history${companyCode ? `?companyCode=${encodeURIComponent(companyCode)}` : ''}`),
};
