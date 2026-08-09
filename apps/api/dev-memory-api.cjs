const http = require('http');
const { randomUUID } = require('crypto');

const port = Number(process.env.PORT || 4000);
const origin = process.env.WEB_ORIGIN || '*';

const companies = [
  { _id: randomUUID(), name: 'Acme Infrastructure', code: 'ACME-2026-GST', status: 'active', plan: 'yearly', subscriptionExpiresAt: '2027-03-31', storageMb: 842, featureFlags: ['OCR', 'GST_RECONCILIATION'], createdAt: new Date().toISOString() },
];

const users = [
  { _id: 'super-demo', name: 'Platform Admin', email: 'super@gst.local', role: 'super_admin', status: 'active' },
  { _id: 'owner-demo', name: 'Company Owner', email: 'owner@gst.local', role: 'owner', companyCode: 'ACME-2026-GST', status: 'active' },
  { _id: 'worker-demo', name: 'Field Worker', email: 'worker@gst.local', role: 'worker', companyCode: 'ACME-2026-GST', status: 'active' },
];

const invoices = [
  { _id: randomUUID(), companyCode: 'ACME-2026-GST', vendorName: 'Shakti Cement', gstin: '27ABCDE1234F1Z5', invoiceNumber: 'SC-9182', invoiceDate: '2026-07-12', vendorPhone: '9876543210', taxableAmount: 118000, gstAmount: 21240, invoiceAmount: 139240, ocrConfidence: 0.94, status: 'matched', status2a: 'unchecked', status2b: 'unchecked', capturedBy: 'Field Worker', createdAt: new Date().toISOString() },
  { _id: randomUUID(), companyCode: 'ACME-2026-GST', vendorName: 'Orbit Steel', gstin: '29ABCDE1234F1Z7', invoiceNumber: 'OS-4410', invoiceDate: '2026-07-17', vendorPhone: '9876500012', taxableAmount: 72500, gstAmount: 13050, invoiceAmount: 85550, ocrConfidence: 0.71, status: 'pending_review', status2a: 'unchecked', status2b: 'unchecked', capturedBy: 'Field Worker', createdAt: new Date().toISOString() },
  { _id: randomUUID(), companyCode: 'ACME-2026-GST', vendorName: 'Prime Logistics', gstin: '07ABCDE1234F1Z1', invoiceNumber: 'PL-772', invoiceDate: '2026-07-19', vendorPhone: '9876500044', taxableAmount: 21000, gstAmount: 3780, invoiceAmount: 24780, ocrConfidence: 0.89, status: 'client_only', status2a: 'unchecked', status2b: 'unchecked', capturedBy: 'Supervisor', createdAt: new Date().toISOString() },
];

const portalRows = [];
const reminders = [];
const auditLogs = [{ _id: randomUUID(), actor: 'dev-memory-api', action: 'server.started', companyCode: 'platform', createdAt: new Date().toISOString() }];

function send(res, status, body) {
  res.writeHead(status, {
    'Access-Control-Allow-Origin': origin === '*' ? '*' : origin,
    'Access-Control-Allow-Credentials': 'true',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    'Access-Control-Allow-Methods': 'GET,POST,PATCH,OPTIONS',
    'Content-Type': 'application/json',
  });
  res.end(JSON.stringify(body));
}

function readJson(req) {
  return new Promise((resolve, reject) => {
    let body = '';
    req.on('data', (chunk) => { body += chunk; });
    req.on('end', () => {
      if (!body) return resolve({});
      try { resolve(JSON.parse(body)); } catch (error) { reject(error); }
    });
  });
}

function withCompany(url) {
  return url.searchParams.get('companyCode') || 'ACME-2026-GST';
}

function normalizeInvoiceNo(value) {
  return String(value || '').replace(/\s+/g, '').toUpperCase();
}

function parseGstCsv(raw) {
  const lines = String(raw || '').replace(/^\uFEFF/, '').split(/\r?\n/).map((l) => l.trim()).filter(Boolean);
  if (!lines.length) return [];
  const first = lines[0].split(',').map((c) => c.trim().toLowerCase());
  const hasHeader = first.some((c) => /invoice|gstin|value|amount|trade/.test(c));
  const data = hasHeader ? lines.slice(1) : lines;
  const header = hasHeader ? first : null;
  return data.map((line) => {
    const cells = line.split(',').map((c) => c.trim());
    if (header) {
      const idx = (...aliases) => header.findIndex((h) => aliases.some((a) => h.includes(a)));
      const n = cells[idx('invoice number', 'invoice no', 'inum')] ?? cells[0];
      const a = Number(String(cells[idx('invoice value', 'invoice amount', 'value', 'amount')] ?? cells[1]).replace(/[^\d.]/g, ''));
      const g = cells[idx('gstin')];
      const v = cells[idx('trade', 'vendor', 'supplier')];
      return { invoiceNumber: n, invoiceAmount: a, gstin: g, vendorName: v };
    }
    return { invoiceNumber: cells[0], invoiceAmount: Number(cells[1]) };
  }).filter((r) => r.invoiceNumber && Number.isFinite(r.invoiceAmount));
}

function bucket(type, companyCode) {
  const statusKey = type === '2A' ? 'status2a' : 'status2b';
  const amountKey = type === '2A' ? 'amount2a' : 'amount2b';
  const bills = invoices.filter((i) => i.companyCode === companyCode).map((inv) => ({
    _id: inv._id,
    vendorName: inv.vendorName,
    vendorPhone: inv.vendorPhone,
    gstin: inv.gstin,
    invoiceNumber: inv.invoiceNumber,
    invoiceDate: inv.invoiceDate,
    invoiceAmount: inv.invoiceAmount,
    matchStatus: inv[statusKey],
    portalAmount: inv[amountKey],
  }));
  const portal = portalRows.filter((p) => p.companyCode === companyCode && p.formType === type);
  return {
    matched: bills.filter((b) => b.matchStatus === 'matched'),
    amountMismatch: bills.filter((b) => b.matchStatus === 'amount_mismatch'),
    inBooksNotInForm: bills.filter((b) => b.matchStatus === 'not_in_portal'),
    inFormNotInBooks: portal.filter((p) => p.matchStatus === 'books_missing').map((p) => ({
      invoiceNumber: p.invoiceNumber,
      invoiceAmount: p.invoiceAmount,
      gstin: p.gstin,
      vendorName: p.vendorName,
      matchStatus: 'portal_only',
    })),
    counts: {
      matched: bills.filter((b) => b.matchStatus === 'matched').length,
      amountMismatch: bills.filter((b) => b.matchStatus === 'amount_mismatch').length,
      inBooksNotInForm: bills.filter((b) => b.matchStatus === 'not_in_portal').length,
      inFormNotInBooks: portal.filter((p) => p.matchStatus === 'books_missing').length,
      unchecked: bills.filter((b) => b.matchStatus === 'unchecked').length,
    },
  };
}

function gstrSummary(companyCode) {
  const list = invoices.filter((i) => i.companyCode === companyCode);
  return {
    companyCode,
    form2A: bucket('2A', companyCode),
    form2B: bucket('2B', companyCode),
    smsReadyMissing2A: list.filter((i) => i.status2a === 'not_in_portal' && /^[6-9]\d{9}$/.test(String(i.vendorPhone || '').slice(-10))).length,
  };
}

function reconcile(companyCode, formType, csv) {
  const rows = parseGstCsv(csv);
  for (let i = portalRows.length - 1; i >= 0; i--) {
    if (portalRows[i].companyCode === companyCode && portalRows[i].formType === formType) portalRows.splice(i, 1);
  }
  const matched = new Set();
  for (const row of rows) {
    const bill = invoices.find((i) => i.companyCode === companyCode && normalizeInvoiceNo(i.invoiceNumber) === normalizeInvoiceNo(row.invoiceNumber));
    let matchStatus = 'books_missing';
    if (bill) {
      matched.add(bill._id);
      matchStatus = Math.abs(row.invoiceAmount - bill.invoiceAmount) <= 1 ? 'matched' : 'amount_mismatch';
      if (formType === '2A') {
        bill.status2a = matchStatus;
        bill.amount2a = row.invoiceAmount;
      } else {
        bill.status2b = matchStatus;
        bill.amount2b = row.invoiceAmount;
      }
    }
    portalRows.push({
      _id: randomUUID(),
      companyCode,
      formType,
      invoiceNumber: row.invoiceNumber,
      invoiceAmount: row.invoiceAmount,
      gstin: row.gstin,
      vendorName: row.vendorName,
      matchStatus,
      billId: bill?._id,
      billAmount: bill?.invoiceAmount,
    });
  }
  for (const bill of invoices.filter((i) => i.companyCode === companyCode)) {
    if (matched.has(bill._id)) continue;
    if (formType === '2A') bill.status2a = 'not_in_portal';
    else bill.status2b = 'not_in_portal';
  }
  return gstrSummary(companyCode);
}

const server = http.createServer(async (req, res) => {
  if (req.method === 'OPTIONS') return send(res, 204, {});
  const url = new URL(req.url, `http://${req.headers.host}`);
  const path = url.pathname.replace(/^\/api/, '');

  try {
    if (req.method === 'GET' && path === '/health') return send(res, 200, { ok: true, service: 'gst-suite-dev-memory-api' });

    if (req.method === 'POST' && path === '/auth/login') {
      const body = await readJson(req);
      const user = users.find((item) => item.email === body.email);
      if (!user || body.password !== 'demo123') return send(res, 401, { message: 'Invalid email or password' });
      return send(res, 201, { token: `dev-token-${user._id}`, user });
    }

    if (req.method === 'POST' && path === '/auth/register') {
      const body = await readJson(req);
      const code = `${String(body.businessName || 'CO').replace(/[^a-zA-Z0-9]/g, '').slice(0, 8).toUpperCase()}-2026-GST`;
      const company = { _id: randomUUID(), name: body.businessName, code, status: 'active', plan: 'trial', subscriptionExpiresAt: new Date(Date.now() + 14 * 864e5).toISOString().slice(0, 10), storageMb: 0, featureFlags: ['OCR'], createdAt: new Date().toISOString() };
      companies.unshift(company);
      const user = { _id: randomUUID(), name: body.name, email: body.email, role: 'owner', companyCode: code, status: 'active' };
      users.push(user);
      return send(res, 201, { token: `dev-token-${user._id}`, user });
    }

    if (req.method === 'GET' && path === '/overview') {
      return send(res, 200, {
        companies: companies.length,
        activeCompanies: companies.filter((c) => c.status === 'active').length,
        expiringSubscriptions: 0,
        expiredSubscriptions: 0,
        invoiceVolume: invoices.length,
        accounts: users.filter((u) => u.role !== 'super_admin').length,
        ocrSuccessRate: 80,
        missingIn2A: invoices.filter((i) => i.status2a === 'not_in_portal').length,
        systemHealth: 'operational',
      });
    }

    if (req.method === 'GET' && path === '/companies') return send(res, 200, companies);
    if (req.method === 'GET' && path === '/users') return send(res, 200, users.filter((u) => u.role !== 'super_admin'));

    if (req.method === 'POST' && path === '/companies') {
      const body = await readJson(req);
      const company = { _id: randomUUID(), status: 'active', storageMb: 0, featureFlags: ['OCR'], plan: body.plan || 'monthly', createdAt: new Date().toISOString(), ...body };
      companies.unshift(company);
      return send(res, 201, company);
    }

    const statusMatch = path.match(/^\/companies\/([^/]+)\/status$/);
    if (req.method === 'PATCH' && statusMatch) {
      const body = await readJson(req);
      const company = companies.find((item) => item.code === statusMatch[1]);
      if (!company) return send(res, 404, { message: 'Company not found' });
      company.status = body.status;
      return send(res, 200, company);
    }

    const subMatch = path.match(/^\/companies\/([^/]+)\/subscription$/);
    if (req.method === 'PATCH' && subMatch) {
      const body = await readJson(req);
      const company = companies.find((item) => item.code === subMatch[1]);
      if (!company) return send(res, 404, { message: 'Company not found' });
      company.subscriptionExpiresAt = body.subscriptionExpiresAt;
      if (body.plan) company.plan = body.plan;
      company.status = 'active';
      return send(res, 200, company);
    }

    if (req.method === 'GET' && path === '/dashboard') {
      const code = withCompany(url);
      const companyInvoices = invoices.filter((invoice) => invoice.companyCode === code);
      return send(res, 200, {
        todaysUploads: companyInvoices.filter((invoice) => invoice.createdAt.slice(0, 10) === new Date().toISOString().slice(0, 10)).length,
        pendingOcrReviews: companyInvoices.filter((invoice) => invoice.status === 'pending_review').length,
        gstRecovered: companyInvoices.filter((invoice) => invoice.status2a === 'matched').reduce((sum, invoice) => sum + invoice.gstAmount, 0),
        missingIn2A: companyInvoices.filter((invoice) => invoice.status2a === 'not_in_portal').length,
        missingIn2B: companyInvoices.filter((invoice) => invoice.status2b === 'not_in_portal').length,
        amountMismatches: companyInvoices.filter((invoice) => invoice.status2a === 'amount_mismatch' || invoice.status2b === 'amount_mismatch').length,
      });
    }

    if (req.method === 'GET' && path === '/invoices') return send(res, 200, invoices.filter((invoice) => invoice.companyCode === withCompany(url)));

    const getInvoice = path.match(/^\/invoice\/([^/]+)$/);
    if (req.method === 'GET' && getInvoice) {
      const invoice = invoices.find((item) => item._id === getInvoice[1]);
      if (!invoice) return send(res, 404, { message: 'Not found' });
      return send(res, 200, invoice);
    }

    if (req.method === 'POST' && path === '/invoice/upload') {
      const body = await readJson(req);
      const invoice = { _id: randomUUID(), createdAt: new Date().toISOString(), status: 'pending_review', status2a: 'unchecked', status2b: 'unchecked', ...body };
      invoices.unshift(invoice);
      return send(res, 201, invoice);
    }

    if (req.method === 'PATCH' && getInvoice) {
      const body = await readJson(req);
      const invoice = invoices.find((item) => item._id === getInvoice[1]);
      if (!invoice) return send(res, 404, { message: 'Invoice not found' });
      Object.assign(invoice, body);
      return send(res, 200, invoice);
    }

    if (req.method === 'POST' && path === '/gst/import') {
      const body = await readJson(req);
      return send(res, 201, reconcile(body.companyCode, body.formType || '2A', body.csv || ''));
    }

    if (req.method === 'GET' && path === '/gst/summary') return send(res, 200, gstrSummary(withCompany(url)));

    if (req.method === 'POST' && path === '/gst/sms-missing') {
      const body = await readJson(req);
      const formType = body.formType || '2A';
      const statusKey = formType === '2A' ? 'status2a' : 'status2b';
      const targets = invoices.filter((i) => i.companyCode === body.companyCode && i[statusKey] === 'not_in_portal');
      const results = targets.map((invoice) => {
        const phone = String(invoice.vendorPhone || '').slice(-10);
        const ok = /^[6-9]\d{9}$/.test(phone);
        const reminder = {
          _id: randomUUID(),
          companyCode: body.companyCode,
          vendor: invoice.vendorName,
          channel: 'sms',
          amount: invoice.invoiceAmount,
          phone,
          invoiceNumber: invoice.invoiceNumber,
          status: ok ? 'sent' : 'failed',
          simulated: true,
          providerDetail: ok ? 'No API key — simulated send' : 'Invalid phone',
          createdAt: new Date().toISOString(),
        };
        if (ok) reminders.unshift(reminder);
        return { invoiceNumber: invoice.invoiceNumber, vendor: invoice.vendorName, phone, ok, simulated: true, detail: reminder.providerDetail };
      });
      return send(res, 201, { formType, sent: results.filter((r) => r.ok).length, failed: results.filter((r) => !r.ok).length, results });
    }

    if (req.method === 'GET' && path === '/reminders') return send(res, 200, reminders.filter((reminder) => reminder.companyCode === withCompany(url)));
    if (req.method === 'POST' && path === '/reminders/send') {
      const body = await readJson(req);
      const reminder = { _id: randomUUID(), status: 'sent', simulated: true, createdAt: new Date().toISOString(), ...body };
      reminders.unshift(reminder);
      return send(res, 201, reminder);
    }

    if (req.method === 'GET' && path === '/subscription') return send(res, 200, companies.find((company) => company.code === withCompany(url)) || null);
    if (req.method === 'GET' && path === '/audit') return send(res, 200, auditLogs.slice(0, 50));

    return send(res, 404, { message: 'Not found' });
  } catch (error) {
    return send(res, 500, { message: error.message });
  }
});

server.listen(port, '0.0.0.0', () => {
  console.log(`GST Suite memory API at http://localhost:${port}/api/health`);
});
