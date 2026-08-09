/**
 * End-to-end workflow check for GST Suite (API).
 * Run with: node apps/api/scripts/e2e-workflow.cjs
 */
const API = process.env.API_URL || 'http://localhost:4000/api';

async function req(path, { method = 'GET', token, body } = {}) {
  const res = await fetch(`${API}${path}`, {
    method,
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  let data;
  try { data = JSON.parse(text); } catch { data = text; }
  if (!res.ok) throw new Error(`${method} ${path} → ${res.status}: ${typeof data === 'string' ? data : JSON.stringify(data)}`);
  return data;
}

function assert(cond, msg) {
  if (!cond) throw new Error(msg);
}

async function main() {
  console.log('1) Health');
  const health = await req('/health');
  assert(health.ok, 'health not ok');

  console.log('2) Super admin login');
  const superLogin = await req('/auth/login', { method: 'POST', body: { email: 'super@gst.local', password: 'demo123' } });
  assert(superLogin.token && superLogin.user.role === 'super_admin', 'super login failed');

  console.log('3) Owner login + invoices');
  const owner = await req('/auth/login', { method: 'POST', body: { email: 'owner@gst.local', password: 'demo123' } });
  assert(owner.user.companyCode === 'ACME-2026-GST', 'owner company missing');
  const before = await req(`/invoices?companyCode=${owner.user.companyCode}`, { token: owner.token });
  assert(before.length >= 3, 'expected seeded invoices');

  console.log('4) Worker captures bill via JSON upload (simulates post-OCR save)');
  const worker = await req('/auth/login', { method: 'POST', body: { email: 'worker@gst.local', password: 'demo123' } });
  const created = await req('/invoice/upload', {
    method: 'POST',
    token: worker.token,
    body: {
      companyCode: 'ACME-2026-GST',
      vendorName: 'Test Vendor SMS',
      gstin: '24ABCDE1234F1Z9',
      invoiceNumber: 'TV-9001',
      invoiceDate: '2026-08-01',
      vendorPhone: '9876512345',
      taxableAmount: 10000,
      gstAmount: 1800,
      invoiceAmount: 11800,
      ocrConfidence: 0.91,
    },
  });
  assert(created._id && created.vendorName === 'Test Vendor SMS', 'bill create failed');

  console.log('5) Import GSTR-2A CSV and match');
  const csv2a = `Invoice Number,Invoice Value,GSTIN,Trade Name
SC-9182,139240,27ABCDE1234F1Z5,Shakti Cement
OS-4410,86000,29ABCDE1234F1Z7,Orbit Steel
GST-ONLY-77,12000,27AAAAA0000A1Z5,Portal Only Vendor`;
  const sum2a = await req('/gst/import', {
    method: 'POST',
    token: owner.token,
    body: { companyCode: 'ACME-2026-GST', formType: '2A', csv: csv2a },
  });
  assert(sum2a.form2A.counts.matched >= 1, '2A matched expected');
  assert(sum2a.form2A.counts.amountMismatch >= 1, '2A amount mismatch expected (OS-4410)');
  assert(sum2a.form2A.counts.inBooksNotInForm >= 1, '2A in-books-not-in-form expected (PL-772 / TV-9001)');
  assert(sum2a.form2A.counts.inFormNotInBooks >= 1, '2A portal-only expected (GST-ONLY-77)');
  assert(sum2a.smsReadyMissing2A >= 1, 'SMS-ready missing phones expected');

  console.log('6) Import GSTR-2B CSV');
  const csv2b = `Invoice Number,Invoice Value
SC-9182,139240
OS-4410,85550
PL-772,24780`;
  const sum2b = await req('/gst/import', {
    method: 'POST',
    token: owner.token,
    body: { companyCode: 'ACME-2026-GST', formType: '2B', csv: csv2b },
  });
  assert(sum2b.form2B.counts.matched >= 2, '2B matched expected');
  // 2A results must still be present after 2B import
  assert(sum2b.form2A.counts.matched >= 1, '2A state must persist after 2B');

  console.log('7) SMS vendors missing from 2A (simulated without API key)');
  const sms = await req('/gst/sms-missing', {
    method: 'POST',
    token: owner.token,
    body: { companyCode: 'ACME-2026-GST', formType: '2A' },
  });
  assert(sms.sent >= 1, 'expected at least one SMS send/simulation');
  assert(sms.results.every((r) => r.ok === false || r.simulated === true || r.ok === true), 'sms result shape');

  console.log('8) Dashboard + reminders + super overview');
  const dash = await req(`/dashboard?companyCode=ACME-2026-GST`, { token: owner.token });
  assert(typeof dash.missingIn2A === 'number', 'dashboard missingIn2A');
  const reminders = await req(`/reminders?companyCode=ACME-2026-GST`, { token: owner.token });
  assert(reminders.length >= 1, 'reminders after SMS');
  const overview = await req('/overview', { token: superLogin.token });
  assert(overview.activeCompanies >= 1, 'super overview');

  console.log('9) Register new business');
  const email = `biz${Date.now()}@test.local`;
  const reg = await req('/auth/register', {
    method: 'POST',
    body: { businessName: 'Raama Traders', name: 'Raama', email, password: 'demo123', phone: '9876500001' },
  });
  assert(reg.user.role === 'owner' && reg.user.companyCode, 'register failed');

  console.log('\n✅ E2E workflow passed');
  console.log(JSON.stringify({
    matched2A: sum2a.form2A.counts,
    matched2B: sum2b.form2B.counts,
    smsSent: sms.sent,
    smsSimulated: sms.results.filter((r) => r.simulated).length,
    newCompany: reg.user.companyCode,
  }, null, 2));
}

main().catch((err) => {
  console.error('\n❌ E2E failed:', err.message);
  process.exit(1);
});
