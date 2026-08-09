import { FormEvent, useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { Buildings, Ticket, UsersThree, WarningCircle, CreditCard } from 'phosphor-react';
import { toast } from 'sonner';
import { api, Company } from '../../lib/api';
import { paySubscription } from '../../lib/payments';
import { Button, DataTable, Field, Metric, Panel, SelectField, Status } from '../../components/ui';
import { useSession } from '../../store/session';

export function SuperAdmin() {
  const queryClient = useQueryClient();
  const setCompanyCode = useSession((s) => s.setCompanyCode);
  const overview = useQuery({ queryKey: ['overview'], queryFn: api.overview });
  const companies = useQuery({ queryKey: ['companies'], queryFn: api.companies });
  const users = useQuery({ queryKey: ['users'], queryFn: () => api.users() });
  const audit = useQuery({ queryKey: ['audit'], queryFn: api.audit });

  const [form, setForm] = useState({
    name: '',
    code: '',
    subscriptionExpiresAt: defaultExpiry(30),
    plan: 'monthly',
    ownerName: '',
    ownerEmail: '',
    ownerPassword: '',
    phone: '',
  });

  const createCompany = useMutation({
    mutationFn: api.createCompany,
    onSuccess: () => {
      toast.success('Account & subscription created');
      queryClient.invalidateQueries({ queryKey: ['companies'] });
      queryClient.invalidateQueries({ queryKey: ['users'] });
      queryClient.invalidateQueries({ queryKey: ['overview'] });
      setForm({ name: '', code: '', subscriptionExpiresAt: defaultExpiry(30), plan: 'monthly', ownerName: '', ownerEmail: '', ownerPassword: '', phone: '' });
    },
    onError: (e: Error) => toast.error(e.message),
  });

  const setStatus = useMutation({
    mutationFn: ({ code, status }: { code: string; status: 'active' | 'suspended' }) => api.setCompanyStatus(code, status),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['companies'] });
      queryClient.invalidateQueries({ queryKey: ['overview'] });
    },
  });

  const extend = useMutation({
    mutationFn: ({ code, subscriptionExpiresAt, plan }: { code: string; subscriptionExpiresAt: string; plan?: string }) =>
      api.extendSubscription(code, { subscriptionExpiresAt, plan }),
    onSuccess: () => {
      toast.success('Subscription updated');
      queryClient.invalidateQueries({ queryKey: ['companies'] });
      queryClient.invalidateQueries({ queryKey: ['overview'] });
    },
    onError: (e: Error) => toast.error(e.message),
  });

  const userStatus = useMutation({
    mutationFn: ({ id, status }: { id: string; status: 'active' | 'locked' }) => api.setUserStatus(id, status),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['users'] }),
  });

  function submit(event: FormEvent) {
    event.preventDefault();
    createCompany.mutate({
      name: form.name,
      code: form.code || undefined,
      subscriptionExpiresAt: form.subscriptionExpiresAt,
      plan: form.plan,
      ownerName: form.ownerName || undefined,
      ownerEmail: form.ownerEmail || undefined,
      ownerPassword: form.ownerPassword || undefined,
      phone: form.phone || undefined,
    });
  }

  return (
    <div className="page-grid">
      <section className="metrics-row">
      <Metric label="Active companies" value={String(overview.data?.activeCompanies ?? '…')} tone="good" />
      <Metric label="Expiring soon" value={String(overview.data?.expiringSubscriptions ?? '…')} tone="warn" />
      <Metric label="Missing in 2A (platform)" value={String(overview.data?.missingIn2A ?? '…')} tone="info" />
      <Metric label="User accounts" value={String(overview.data?.accounts ?? '…')} />
      </section>

      <Panel className="span-8">
        <div className="panel-head">
          <div><Buildings size={22} /><h2>Subscriptions & companies</h2></div>
          <Status tone="info">License control</Status>
        </div>
        <DataTable>
          <thead>
            <tr><th>Company</th><th>License</th><th>Plan</th><th>Status</th><th>Expiry</th><th /></tr>
          </thead>
          <tbody>
            {companies.data?.map((item) => (
              <CompanyRow
                key={item.code}
                item={item}
                onUse={() => { setCompanyCode(item.code); toast.message(`Context: ${item.code}`); }}
                onToggle={() => setStatus.mutate({ code: item.code, status: item.status === 'active' ? 'suspended' : 'active' })}
                onExtend={(subscriptionExpiresAt, plan) => extend.mutate({ code: item.code, subscriptionExpiresAt, plan })}
              />
            ))}
          </tbody>
        </DataTable>
      </Panel>

      <Panel className="span-4">
        <form onSubmit={submit} className="stack">
          <h2>Create account</h2>
          <Field label="Business name" value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} required />
          <Field label="License code (optional)" value={form.code} onChange={(e) => setForm({ ...form, code: e.target.value.toUpperCase() })} placeholder="Auto if blank" />
          <SelectField label="Plan" value={form.plan} onChange={(e) => setForm({ ...form, plan: e.target.value })}>
            <option value="trial">Trial</option>
            <option value="monthly">Monthly</option>
            <option value="yearly">Yearly</option>
          </SelectField>
          <Field label="Subscription expiry" type="date" value={form.subscriptionExpiresAt} onChange={(e) => setForm({ ...form, subscriptionExpiresAt: e.target.value })} />
          <Field label="Owner name" value={form.ownerName} onChange={(e) => setForm({ ...form, ownerName: e.target.value })} />
          <Field label="Owner email" type="email" value={form.ownerEmail} onChange={(e) => setForm({ ...form, ownerEmail: e.target.value })} />
          <Field label="Owner password" type="password" value={form.ownerPassword} onChange={(e) => setForm({ ...form, ownerPassword: e.target.value })} minLength={6} />
          <Field label="Phone" value={form.phone} onChange={(e) => setForm({ ...form, phone: e.target.value })} />
          <Button type="submit" disabled={createCompany.isPending}>{createCompany.isPending ? 'Creating…' : 'Create company + owner'}</Button>
        </form>
      </Panel>

      <Panel className="span-7">
        <div className="panel-head"><div><UsersThree size={22} /><h2>Accounts</h2></div></div>
        <DataTable>
          <thead><tr><th>User</th><th>Role</th><th>Company</th><th>Status</th><th /></tr></thead>
          <tbody>
            {users.data?.map((u) => (
              <tr key={u._id}>
                <td><b>{u.name}</b><small>{u.email}</small></td>
                <td>{u.role.replaceAll('_', ' ')}</td>
                <td>{u.companyCode ?? '—'}</td>
                <td><Status tone={u.status === 'active' ? 'good' : 'bad'}>{u.status}</Status></td>
                <td>
                  <Button variant="secondary" onClick={() => userStatus.mutate({ id: u._id, status: u.status === 'active' ? 'locked' : 'active' })}>
                    {u.status === 'active' ? 'Lock' : 'Unlock'}
                  </Button>
                </td>
              </tr>
            ))}
          </tbody>
        </DataTable>
      </Panel>

      <Panel className="span-5">
        <div className="panel-head"><div><WarningCircle size={22} /><h2>Audit</h2></div></div>
        <div className="audit-list">
          {audit.data?.slice(0, 8).map((row, index) => (
            <div key={index}>
              <Ticket size={16} />
              <span>{String(row.action)}</span>
              <small>{String(row.companyCode ?? 'platform')}</small>
            </div>
          ))}
        </div>
      </Panel>
    </div>
  );
}

function CompanyRow({
  item,
  onUse,
  onToggle,
  onExtend,
}: {
  item: Company;
  onUse: () => void;
  onToggle: () => void;
  onExtend: (expiry: string, plan?: string) => void;
}) {
  const [expiry, setExpiry] = useState(item.subscriptionExpiresAt.slice(0, 10));
  const [paying, setPaying] = useState(false);
  const expired = new Date(item.subscriptionExpiresAt) < new Date();
  return (
    <tr>
      <td><b>{item.name}</b><small>{item.storageMb} MB</small></td>
      <td>{item.code}</td>
      <td>{item.plan ?? '—'}</td>
      <td><Status tone={item.status === 'active' && !expired ? 'good' : 'bad'}>{expired ? 'expired' : item.status}</Status></td>
      <td>
        <input type="date" className="inline-date" value={expiry} onChange={(e) => setExpiry(e.target.value)} />
      </td>
      <td className="row-actions">
        <Button variant="ghost" onClick={onUse}>Select</Button>
        <Button variant="secondary" onClick={() => onExtend(expiry, item.plan)}>Extend</Button>
        <Button
          variant="secondary"
          disabled={paying}
          onClick={async () => {
            setPaying(true);
            try {
              await paySubscription(item.code, (item.plan === 'yearly' ? 'yearly' : 'monthly'));
            } catch (e) {
              toast.error(e instanceof Error ? e.message : 'Payment failed');
            } finally {
              setPaying(false);
            }
          }}
        >
          <CreditCard size={14} /> Collect pay
        </Button>
        <Button variant="secondary" onClick={onToggle}>{item.status === 'active' ? 'Suspend' : 'Activate'}</Button>
      </td>
    </tr>
  );
}

function defaultExpiry(days: number) {
  const d = new Date();
  d.setDate(d.getDate() + days);
  return d.toISOString().slice(0, 10);
}
