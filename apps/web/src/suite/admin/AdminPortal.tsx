import { useMemo, useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { ChatText, FileCsv, MagnifyingGlass, Receipt, Scales, WarningCircle, CreditCard } from 'phosphor-react';
import { toast } from 'sonner';
import { api, Invoice } from '../../lib/api';
import { formatPaise, paySubscription } from '../../lib/payments';
import { Button, DataTable, Metric, Panel, Status } from '../../components/ui';
import { useSession } from '../../store/session';
import { BillReviewDrawer } from './BillReviewDrawer';

const sample2A = `Invoice Number,Invoice Value,GSTIN,Trade Name
SC-9182,139240,27ABCDE1234F1Z5,Shakti Cement
OS-4410,86000,29ABCDE1234F1Z7,Orbit Steel
GST-ONLY-77,12000,27AAAAA0000A1Z5,Portal Only Vendor`;

const sample2B = `Invoice Number,Invoice Value
SC-9182,139240
OS-4410,85550
PL-772,24780`;

type MatchRow = {
  _id?: string;
  invoiceNumber: string;
  invoiceAmount?: number;
  portalAmount?: number;
  vendorName?: string;
  vendorPhone?: string;
  gstin?: string;
  matchStatus?: string;
};

export function AdminPortal() {
  const companyCode = useSession((s) => s.companyCode);
  const queryClient = useQueryClient();
  const [search, setSearch] = useState('');
  const [csv2a, setCsv2a] = useState(sample2A);
  const [csv2b, setCsv2b] = useState(sample2B);
  const [activeTab, setActiveTab] = useState<'2A' | '2B'>('2A');

  const dashboard = useQuery({ queryKey: ['dashboard', companyCode], queryFn: () => api.dashboard(companyCode), enabled: !!companyCode });
  const invoices = useQuery({
    queryKey: ['invoices', companyCode],
    queryFn: () => api.invoices(companyCode),
    enabled: !!companyCode,
    refetchInterval: (q) => (q.state.data?.some((i) => i.status === 'processing') ? 2000 : 20000),
  });
  const gstr = useQuery({ queryKey: ['gstr', companyCode], queryFn: () => api.gstrSummary(companyCode), enabled: !!companyCode });
  const reminders = useQuery({ queryKey: ['reminders', companyCode], queryFn: () => api.reminders(companyCode), enabled: !!companyCode });
  const subscription = useQuery({ queryKey: ['subscription', companyCode], queryFn: () => api.subscription(companyCode), enabled: !!companyCode });
  const payConfig = useQuery({ queryKey: ['pay-config'], queryFn: api.paymentConfig });
  const [paying, setPaying] = useState(false);
  const [reviewId, setReviewId] = useState<string>();

  const import2a = useMutation({
    mutationFn: () => api.reconcile(companyCode, '2A', csv2a),
    onSuccess: (data) => {
      toast.success(`2A matched: ${data.form2A.counts.matched} · missing in 2A: ${data.form2A.counts.inBooksNotInForm}`);
      invalidate();
    },
    onError: (e: Error) => toast.error(e.message),
  });

  const import2b = useMutation({
    mutationFn: () => api.reconcile(companyCode, '2B', csv2b),
    onSuccess: (data) => {
      toast.success(`2B matched: ${data.form2B.counts.matched} · missing in 2B: ${data.form2B.counts.inBooksNotInForm}`);
      invalidate();
    },
    onError: (e: Error) => toast.error(e.message),
  });

  const smsMissing = useMutation({
    mutationFn: () => api.smsMissing(companyCode, '2A'),
    onSuccess: (data) => {
      toast.success(`SMS: ${data.sent} sent${data.results.some((r) => r.simulated) ? ' (simulated — add FAST2SMS_API_KEY for live)' : ''}, ${data.failed} failed`);
      queryClient.invalidateQueries({ queryKey: ['reminders', companyCode] });
    },
    onError: (e: Error) => toast.error(e.message),
  });

  const remindOne = useMutation({
    mutationFn: (invoice: Invoice) => api.sendReminder({
      companyCode,
      vendor: invoice.vendorName,
      channel: 'sms',
      amount: invoice.invoiceAmount,
      phone: invoice.vendorPhone,
      invoiceNumber: invoice.invoiceNumber,
      invoiceId: invoice._id,
    }),
    onSuccess: (r) => {
      toast.success(r.simulated ? 'SMS simulated (no API key)' : `SMS ${r.status}`);
      queryClient.invalidateQueries({ queryKey: ['reminders', companyCode] });
    },
    onError: (e: Error) => toast.error(e.message),
  });

  function invalidate() {
    queryClient.invalidateQueries({ queryKey: ['invoices', companyCode] });
    queryClient.invalidateQueries({ queryKey: ['gstr', companyCode] });
    queryClient.invalidateQueries({ queryKey: ['dashboard', companyCode] });
  }

  async function onCsvFile(file: File | undefined, form: '2A' | '2B') {
    if (!file) return;
    const text = await file.text();
    if (form === '2A') setCsv2a(text);
    else setCsv2b(text);
    toast.message(`${form} CSV loaded (${file.name})`);
  }

  const filtered = useMemo(
    () => invoices.data?.filter((invoice) => `${invoice.vendorName} ${invoice.invoiceNumber} ${invoice.status} ${invoice.status2a} ${invoice.status2b}`.toLowerCase().includes(search.toLowerCase())) ?? [],
    [invoices.data, search],
  );

  const form = activeTab === '2A' ? gstr.data?.form2A : gstr.data?.form2B;

  if (!companyCode) {
    return <Panel><p className="muted">No company linked to this account.</p></Panel>;
  }

  return (
    <div className="page-grid">
      <section className="context-band">
        <Receipt size={24} />
        <div>
          <b>{companyCode}</b>
          <span>Import GSTR-2A / 2B CSV, align with captured bills, SMS vendors missing from 2A.</span>
        </div>
      </section>

      <Panel className="span-12">
        <div className="panel-head">
          <div><CreditCard size={22} /><h2>Subscription</h2></div>
          <Status tone={subscription.data && new Date(subscription.data.subscriptionExpiresAt) > new Date() ? 'good' : 'bad'}>
            {subscription.data?.plan ?? '—'} · expires {subscription.data ? new Date(subscription.data.subscriptionExpiresAt).toLocaleDateString() : '—'}
          </Status>
        </div>
        <p className="muted">
          Renew with Razorpay. {payConfig.data?.enabled ? 'Live checkout enabled.' : 'Test mode (no Razorpay keys) — payment simulates success and extends the plan.'}
        </p>
        <div className="row-actions">
          <Button
            disabled={paying}
            onClick={async () => {
              setPaying(true);
              try {
                await paySubscription(companyCode, 'monthly');
                queryClient.invalidateQueries({ queryKey: ['subscription', companyCode] });
              } catch (e) {
                toast.error(e instanceof Error ? e.message : 'Payment failed');
              } finally {
                setPaying(false);
              }
            }}
          >
            Pay monthly {payConfig.data ? formatPaise(payConfig.data.plans.monthly.amountPaise) : ''}
          </Button>
          <Button
            variant="secondary"
            disabled={paying}
            onClick={async () => {
              setPaying(true);
              try {
                await paySubscription(companyCode, 'yearly');
                queryClient.invalidateQueries({ queryKey: ['subscription', companyCode] });
              } catch (e) {
                toast.error(e instanceof Error ? e.message : 'Payment failed');
              } finally {
                setPaying(false);
              }
            }}
          >
            Pay yearly {payConfig.data ? formatPaise(payConfig.data.plans.yearly.amountPaise) : ''}
          </Button>
        </div>
      </Panel>

      <section className="metrics-row">
        <Metric label="Today's uploads" value={dashboard.data?.todaysUploads ?? '…'} />
        <Metric label="Missing in 2A" value={dashboard.data?.missingIn2A ?? '…'} tone="warn" />
        <Metric label="Missing in 2B" value={dashboard.data?.missingIn2B ?? '…'} tone="info" />
        <Metric label="Amount mismatches" value={dashboard.data?.amountMismatches ?? '…'} tone="warn" />
      </section>

      <Panel className="span-6">
        <div className="panel-head">
          <div><Scales size={22} /><h2>GSTR-2A CSV</h2></div>
          <Status tone="warn">{gstr.data?.form2A.counts.inBooksNotInForm ?? 0} not in 2A</Status>
        </div>
        <p className="muted">Paste portal export or upload CSV. Headers optional: Invoice Number, Invoice Value, GSTIN, Trade Name.</p>
        <input type="file" accept=".csv,text/csv,text/plain" onChange={(e) => void onCsvFile(e.target.files?.[0], '2A')} />
        <textarea value={csv2a} onChange={(e) => setCsv2a(e.target.value)} className="gst-csv" />
        <div className="row-actions">
          <Button onClick={() => import2a.mutate()} disabled={import2a.isPending}>
            <FileCsv size={16} /> {import2a.isPending ? 'Matching…' : 'Match with bills'}
          </Button>
          <Button variant="secondary" onClick={() => smsMissing.mutate()} disabled={smsMissing.isPending || !(gstr.data?.smsReadyMissing2A)}>
            <ChatText size={16} /> SMS missing in 2A ({gstr.data?.smsReadyMissing2A ?? 0})
          </Button>
        </div>
      </Panel>

      <Panel className="span-6">
        <div className="panel-head">
          <div><Scales size={22} /><h2>GSTR-2B CSV</h2></div>
          <Status tone="info">{gstr.data?.form2B.counts.inBooksNotInForm ?? 0} not in 2B</Status>
        </div>
        <p className="muted">Same format as 2A. 2B match is stored separately so both returns stay visible.</p>
        <input type="file" accept=".csv,text/csv,text/plain" onChange={(e) => void onCsvFile(e.target.files?.[0], '2B')} />
        <textarea value={csv2b} onChange={(e) => setCsv2b(e.target.value)} className="gst-csv" />
        <Button onClick={() => import2b.mutate()} disabled={import2b.isPending}>
          <FileCsv size={16} /> {import2b.isPending ? 'Matching…' : 'Match with bills'}
        </Button>
      </Panel>

      <Panel className="span-12">
        <div className="panel-head">
          <div><WarningCircle size={22} /><h2>Reconciliation results</h2></div>
          <div className="auth-tabs compact-tabs">
            <button type="button" className={activeTab === '2A' ? 'active' : ''} onClick={() => setActiveTab('2A')}>2A</button>
            <button type="button" className={activeTab === '2B' ? 'active' : ''} onClick={() => setActiveTab('2B')}>2B</button>
          </div>
        </div>
        <div className="reconcile-grid">
          <MatchBlock title="Matched" tone="good" rows={form?.matched ?? []} />
          <MatchBlock title="Amount mismatch" tone="bad" rows={form?.amountMismatch ?? []} showPortal />
          <MatchBlock title="In books, not in form" tone="warn" rows={form?.inBooksNotInForm ?? []} />
          <MatchBlock title="In form, not in books" tone="info" rows={form?.inFormNotInBooks ?? []} portalOnly />
        </div>
        <p className="muted tiny">Free SMS: create an account at fast2sms.com (₹50 free credit), set FAST2SMS_API_KEY in API .env. Without a key, SMS is simulated and logged.</p>
      </Panel>

      <Panel className="span-8">
        <div className="panel-head">
          <div><MagnifyingGlass size={22} /><h2>Bills</h2></div>
          <input className="search" value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Vendor, invoice, 2A/2B status" />
        </div>
        <DataTable>
          <thead>
            <tr><th>Vendor</th><th>Invoice</th><th>AI</th><th>2A</th><th>2B</th><th>Invoice amount</th><th /></tr>
          </thead>
          <tbody>
            {filtered.map((invoice) => (
              <tr key={invoice._id}>
                <td><b>{invoice.vendorName}</b><small>{invoice.vendorPhone}</small></td>
                <td>{invoice.invoiceNumber}<small>{invoice.invoiceDate}</small></td>
                <td>
                  <Status tone={invoice.status === 'processing' ? 'warn' : invoice.status === 'pending_review' ? 'info' : 'good'}>
                    {invoice.status === 'processing' ? 'processing' : invoice.status === 'pending_review' ? 'review' : 'ok'}
                  </Status>
                </td>
                <td><Status tone={toneFor(invoice.status2a)}>{labelStatus(invoice.status2a)}</Status></td>
                <td><Status tone={toneFor(invoice.status2b)}>{labelStatus(invoice.status2b)}</Status></td>
                <td>₹{Number(invoice.invoiceAmount || 0).toLocaleString()}</td>
                <td className="row-actions">
                  <Button variant="secondary" onClick={() => setReviewId(invoice._id)}>Open bill</Button>
                  {invoice.status2a === 'not_in_portal' && invoice.status !== 'processing' && (
                    <Button variant="ghost" onClick={() => remindOne.mutate(invoice)}>SMS</Button>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </DataTable>
      </Panel>

      <Panel className="span-4">
        <div className="panel-head">
          <div><ChatText size={22} /><h2>SMS / reminders</h2></div>
          <Status tone="warn">{reminders.data?.length ?? 0}</Status>
        </div>
        <div className="audit-list">
          {reminders.data?.slice(0, 12).map((item) => (
            <div key={item._id}>
              <span>{item.vendor}{item.invoiceNumber ? ` · ${item.invoiceNumber}` : ''}</span>
              <small>
                {item.channel} · {item.phone || '—'} · ₹{item.amount.toLocaleString()} · {item.status}
                {item.simulated ? ' · simulated' : ''}
              </small>
            </div>
          ))}
          {!reminders.data?.length && <p className="muted">No SMS yet.</p>}
        </div>
      </Panel>

      {reviewId && (
        <BillReviewDrawer
          invoiceId={reviewId}
          onClose={() => setReviewId(undefined)}
          onSaved={() => {
            queryClient.invalidateQueries({ queryKey: ['invoices', companyCode] });
            queryClient.invalidateQueries({ queryKey: ['dashboard', companyCode] });
          }}
        />
      )}
    </div>
  );
}

function MatchBlock({ title, tone, rows, showPortal, portalOnly }: { title: string; tone: 'good' | 'bad' | 'warn' | 'info'; rows: MatchRow[]; showPortal?: boolean; portalOnly?: boolean }) {
  return (
    <div className={`match-block match-${tone}`}>
      <div className="panel-head"><h2>{title}</h2><Status tone={tone}>{rows.length}</Status></div>
      <div className="match-list">
        {rows.slice(0, 8).map((row) => (
          <div key={`${row.invoiceNumber}-${row._id || row.gstin || 'p'}`}>
            <b>{row.invoiceNumber}</b>
            <small>
              {row.vendorName || '—'}
              {portalOnly ? ` · portal ₹${Number(row.invoiceAmount || 0).toLocaleString()}` : ` · bill ₹${Number(row.invoiceAmount || 0).toLocaleString()}`}
              {showPortal && row.portalAmount != null ? ` · 2A/2B ₹${Number(row.portalAmount).toLocaleString()}` : ''}
              {row.vendorPhone ? ` · ${row.vendorPhone}` : ''}
            </small>
          </div>
        ))}
        {!rows.length && <p className="muted">None</p>}
        {rows.length > 8 && <p className="muted">+{rows.length - 8} more</p>}
      </div>
    </div>
  );
}

function toneFor(status?: string) {
  if (status === 'matched') return 'good';
  if (status === 'amount_mismatch') return 'bad';
  if (status === 'not_in_portal' || status === 'processing') return 'warn';
  if (status === 'portal_only') return 'info';
  return 'neutral';
}

function labelStatus(status?: string) {
  if (!status || status === 'unchecked') return '—';
  return status.replaceAll('_', ' ');
}
