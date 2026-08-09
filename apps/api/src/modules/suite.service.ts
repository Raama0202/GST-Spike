import { BadRequestException, ConflictException, Injectable, NotFoundException, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { InjectModel } from '@nestjs/mongoose';
import * as bcrypt from 'bcryptjs';
import { createHash, randomBytes } from 'crypto';
import { mkdir, writeFile } from 'fs/promises';
import { join } from 'path';
import { Model } from 'mongoose';
import { CreateCompanyDto, ExtendSubscriptionDto, PatchInvoiceDto, RegisterDto, UpsertInvoiceDto, ReminderDto } from './dto';
import { normalizeInvoiceNo, parseGstCsv, ParsedGstRow } from './gst-csv';
import { GeminiBillService } from './gemini-bill.service';
import { SmsService } from './sms.service';
import { AuditLog, Company, CompanyDocument, GstPortalRow, GstPortalRowDocument, Invoice, InvoiceDocument, Reminder, User, UserDocument } from './suite.schema';

@Injectable()
export class SuiteService {
  private readonly uploadRoot: string;

  constructor(
    private readonly config: ConfigService,
    private readonly sms: SmsService,
    private readonly gemini: GeminiBillService,
    @InjectModel(Company.name) private companiesModel: Model<CompanyDocument>,
    @InjectModel(User.name) private usersModel: Model<UserDocument>,
    @InjectModel(Invoice.name) private invoicesModel: Model<InvoiceDocument>,
    @InjectModel(GstPortalRow.name) private portalModel: Model<GstPortalRowDocument>,
    @InjectModel(Reminder.name) private remindersModel: Model<Reminder>,
    @InjectModel(AuditLog.name) private auditModel: Model<AuditLog>,
  ) {
    this.uploadRoot = this.config.get<string>('UPLOAD_DIR') || join(process.cwd(), 'uploads');
  }

  async onModuleInit() {
    await mkdir(this.uploadRoot, { recursive: true });
    await this.migrateLegacyFields();
    if (this.config.get<string>('AUTO_SEED_DEMO') === 'true' && (await this.companiesModel.countDocuments()) === 0) await this.seed();
  }

  /** One-time rename: sellerName→vendorName, totalAmount→invoiceAmount, supplier→vendor */
  private async migrateLegacyFields() {
    const legacyInvoices = await this.invoicesModel.collection.find({
      $or: [{ sellerName: { $exists: true } }, { totalAmount: { $exists: true } }],
    }).toArray();
    for (const doc of legacyInvoices) {
      const set: Record<string, unknown> = {};
      if (doc.sellerName && !doc.vendorName) set.vendorName = doc.sellerName;
      if (doc.sellerPhone && !doc.vendorPhone) set.vendorPhone = doc.sellerPhone;
      if (doc.totalAmount != null && doc.invoiceAmount == null) set.invoiceAmount = doc.totalAmount;
      if (Object.keys(set).length) {
        await this.invoicesModel.collection.updateOne({ _id: doc._id }, { $set: set });
      }
    }
    const legacyReminders = await this.remindersModel.collection.find({ supplier: { $exists: true }, vendor: { $exists: false } }).toArray();
    for (const doc of legacyReminders) {
      await this.remindersModel.collection.updateOne({ _id: doc._id }, { $set: { vendor: doc.supplier } });
    }
  }

  async seed() {
    const passwordHash = await bcrypt.hash('demo123', 10);
    await this.companiesModel.create([
      { name: 'Acme Infrastructure', code: 'ACME-2026-GST', subscriptionExpiresAt: new Date('2027-03-31'), storageMb: 842, plan: 'yearly' },
      { name: 'Kaveri Buildmart', code: 'KAVERI-2026-GST', subscriptionExpiresAt: new Date('2026-08-28'), storageMb: 311, plan: 'monthly' },
    ]);
    await this.usersModel.create([
      { name: 'Platform Admin', email: 'super@gst.local', passwordHash, role: 'super_admin' },
      { name: 'Company Owner', email: 'owner@gst.local', passwordHash, role: 'owner', companyCode: 'ACME-2026-GST' },
      { name: 'Field Worker', email: 'worker@gst.local', passwordHash, role: 'worker', companyCode: 'ACME-2026-GST' },
    ]);
    await this.invoicesModel.create([
      { companyCode: 'ACME-2026-GST', vendorName: 'Shakti Cement', gstin: '27ABCDE1234F1Z5', invoiceNumber: 'SC-9182', invoiceDate: '2026-07-12', vendorPhone: '9876543210', taxableAmount: 118000, gstAmount: 21240, invoiceAmount: 139240, ocrConfidence: 0.94, status: 'matched', status2a: 'matched', status2b: 'matched', amount2a: 139240, amount2b: 139240, capturedBy: 'Field Worker' },
      { companyCode: 'ACME-2026-GST', vendorName: 'Orbit Steel', gstin: '29ABCDE1234F1Z7', invoiceNumber: 'OS-4410', invoiceDate: '2026-07-17', vendorPhone: '9876500012', taxableAmount: 72500, gstAmount: 13050, invoiceAmount: 85550, ocrConfidence: 0.71, status: 'pending_review', status2a: 'amount_mismatch', status2b: 'unchecked', amount2a: 86000, capturedBy: 'Field Worker' },
      { companyCode: 'ACME-2026-GST', vendorName: 'Prime Logistics', gstin: '07ABCDE1234F1Z1', invoiceNumber: 'PL-772', invoiceDate: '2026-07-19', vendorPhone: '9876500044', taxableAmount: 21000, gstAmount: 3780, invoiceAmount: 24780, ocrConfidence: 0.89, status: 'client_only', status2a: 'not_in_portal', status2b: 'not_in_portal', capturedBy: 'Supervisor' },
    ]);
    await this.remindersModel.create([{ companyCode: 'ACME-2026-GST', vendor: 'Prime Logistics', channel: 'sms', amount: 24780, phone: '9876500044', invoiceNumber: 'PL-772', status: 'pending' }]);
    console.log('[seed] Demo accounts ready (password: demo123)');
  }

  async validateUser(email: string, password: string) {
    const user = await this.usersModel.findOne({ email: email.toLowerCase().trim() }).lean();
    if (!user || !(await bcrypt.compare(password, user.passwordHash))) throw new UnauthorizedException('Invalid email or password');
    if (user.status === 'locked') throw new UnauthorizedException('Account is locked');
    if (user.companyCode) {
      const company = await this.companiesModel.findOne({ code: user.companyCode }).lean();
      if (company?.status === 'suspended') throw new UnauthorizedException('Company subscription is suspended');
    }
    return { id: String(user._id), name: user.name, email: user.email, role: user.role, companyCode: user.companyCode };
  }

  async register(dto: RegisterDto) {
    const email = dto.email.toLowerCase().trim();
    if (await this.usersModel.exists({ email })) throw new ConflictException('Email already registered');
    const code = this.makeLicenseCode(dto.businessName);
    const expires = new Date();
    expires.setDate(expires.getDate() + 14);
    const company = await this.companiesModel.create({
      name: dto.businessName.trim(),
      code,
      phone: dto.phone,
      plan: 'trial',
      subscriptionExpiresAt: expires,
      status: 'active',
      featureFlags: ['OCR', 'GST_RECONCILIATION'],
    });
    const passwordHash = await bcrypt.hash(dto.password, 10);
    const user = await this.usersModel.create({
      name: dto.name.trim(),
      email,
      passwordHash,
      role: 'owner',
      companyCode: company.code,
      phone: dto.phone,
    });
    await this.audit(email, 'account.registered', company.code, { businessName: company.name });
    return { id: String(user._id), name: user.name, email: user.email, role: user.role, companyCode: user.companyCode };
  }

  companies() {
    return this.companiesModel.find().sort({ createdAt: -1 }).lean();
  }

  async createCompany(dto: CreateCompanyDto) {
    const code = (dto.code || this.makeLicenseCode(dto.name)).toUpperCase();
    if (await this.companiesModel.exists({ code })) throw new ConflictException('License code already exists');
    const expires = dto.subscriptionExpiresAt ? new Date(dto.subscriptionExpiresAt) : (() => {
      const d = new Date();
      d.setMonth(d.getMonth() + 1);
      return d;
    })();
    const company = await this.companiesModel.create({
      name: dto.name.trim(),
      code,
      phone: dto.phone,
      plan: dto.plan ?? 'monthly',
      subscriptionExpiresAt: expires,
      status: 'active',
      featureFlags: ['OCR', 'GST_RECONCILIATION'],
    });
    if (dto.ownerEmail && dto.ownerPassword) {
      const email = dto.ownerEmail.toLowerCase().trim();
      if (await this.usersModel.exists({ email })) throw new ConflictException('Owner email already exists');
      await this.usersModel.create({
        name: dto.ownerName?.trim() || dto.name.trim(),
        email,
        passwordHash: await bcrypt.hash(dto.ownerPassword, 10),
        role: 'owner',
        companyCode: code,
        phone: dto.phone,
      });
    }
    await this.audit('system', 'company.created', company.code, { name: company.name });
    return company;
  }

  async setCompanyStatus(code: string, status: 'active' | 'suspended') {
    const company = await this.companiesModel.findOneAndUpdate({ code }, { status }, { new: true });
    if (!company) throw new NotFoundException('Company not found');
    await this.audit('system', `company.${status}`, code);
    return company;
  }

  async extendSubscription(code: string, dto: ExtendSubscriptionDto) {
    const company = await this.companiesModel.findOneAndUpdate(
      { code },
      { subscriptionExpiresAt: new Date(dto.subscriptionExpiresAt), ...(dto.plan ? { plan: dto.plan } : {}), status: 'active' },
      { new: true },
    );
    if (!company) throw new NotFoundException('Company not found');
    await this.audit('system', 'subscription.extended', code, { expires: dto.subscriptionExpiresAt, plan: dto.plan });
    return company;
  }

  async setFeatures(code: string, featureFlags: string[]) {
    const company = await this.companiesModel.findOneAndUpdate({ code }, { featureFlags }, { new: true });
    if (!company) throw new NotFoundException('Company not found');
    await this.audit('system', 'features.updated', code, { featureFlags });
    return company;
  }

  users(companyCode?: string) {
    const filter = companyCode ? { companyCode } : { role: { $ne: 'super_admin' } };
    return this.usersModel.find(filter).select('-passwordHash').sort({ createdAt: -1 }).lean();
  }

  async setUserStatus(id: string, status: 'active' | 'locked') {
    const user = await this.usersModel.findByIdAndUpdate(id, { status }, { new: true }).select('-passwordHash');
    if (!user) throw new NotFoundException('User not found');
    await this.audit('system', `user.${status}`, user.companyCode, { email: user.email });
    return user;
  }

  invoices(companyCode: string) {
    return this.invoicesModel.find({ companyCode }).sort({ createdAt: -1 }).lean();
  }

  invoice(id: string) {
    return this.invoicesModel.findById(id).lean();
  }

  async assertCompanyCanUpload(companyCode: string) {
    const company = await this.companiesModel.findOne({ code: companyCode }).lean();
    if (!company) throw new NotFoundException('Company not found');
    if (company.status === 'suspended') throw new BadRequestException('Company is suspended');
    if (new Date(company.subscriptionExpiresAt) < new Date()) throw new BadRequestException('Subscription expired');
    return company;
  }

  /** Fast path: save image + draft invoice, OCR runs in background. */
  async captureBillImage(opts: { companyCode: string; file: Express.Multer.File; capturedBy?: string }) {
    const company = await this.assertCompanyCanUpload(opts.companyCode);
    const ext = (opts.file.originalname.split('.').pop() || 'jpg').toLowerCase().replace(/[^a-z0-9]/g, '') || 'jpg';
    const filename = `${Date.now()}-${randomBytes(4).toString('hex')}.${ext}`;
    await writeFile(join(this.uploadRoot, filename), opts.file.buffer);
    const imageUrl = `/uploads/${filename}`;
    const sizeMb = Math.max(0.01, opts.file.size / (1024 * 1024));
    await this.companiesModel.updateOne({ code: opts.companyCode }, { $inc: { storageMb: Number(sizeMb.toFixed(2)) } });

    const invoice = await this.invoicesModel.create({
      companyCode: opts.companyCode,
      vendorName: 'Processing…',
      gstin: '00PENDING0000P0Z0',
      invoiceNumber: `PROC-${Date.now().toString(36).toUpperCase()}`,
      invoiceDate: new Date().toISOString().slice(0, 10),
      vendorPhone: '0000000000',
      taxableAmount: 0,
      gstAmount: 0,
      invoiceAmount: 0,
      ocrConfidence: 0,
      status: 'processing',
      imageUrl,
      notes: 'Image stored; Gemini extraction queued on server',
      capturedBy: opts.capturedBy,
    });

    // Fire-and-forget: client is not blocked on AI
    setImmediate(() => {
      void this.runAiExtractAndFill(String(invoice._id), join(this.uploadRoot, filename), company.name, opts.file.mimetype);
    });
    await this.audit(opts.capturedBy || 'client-app', 'invoice.image_uploaded', opts.companyCode, { invoiceId: String(invoice._id) });
    return invoice.toObject();
  }

  private async runAiExtractAndFill(invoiceId: string, filePath: string, businessName: string, mimeType?: string) {
    try {
      const parsed = await this.gemini.extractFromImage(filePath, businessName, mimeType || 'image/jpeg');
      const existing = await this.invoicesModel.findById(invoiceId).lean();
      const duplicate = await this.invoicesModel.findOne({
        companyCode: existing?.companyCode,
        invoiceNumber: parsed.invoiceNumber,
        _id: { $ne: invoiceId },
      });
      const { engine, ...fields } = parsed;
      await this.invoicesModel.findByIdAndUpdate(invoiceId, {
        ...fields,
        status: duplicate ? 'amount_mismatch' : 'pending_review',
        notes: `${fields.notes} · engine=${engine}`,
      });
    } catch (error) {
      await this.invoicesModel.findByIdAndUpdate(invoiceId, {
        status: 'pending_review',
        notes: `AI extract incomplete: ${error instanceof Error ? error.message : 'unknown error'}. Edit fields manually.`,
        ocrConfidence: 0.35,
        vendorName: 'Unknown vendor',
      });
    }
  }

  async createInvoice(dto: UpsertInvoiceDto, capturedBy?: string) {
    await this.assertCompanyCanUpload(dto.companyCode);
    const company = await this.companiesModel.findOne({ code: dto.companyCode }).lean();
    const vendorName = this.sanitizeVendor(dto.vendorName, company?.name);
    const duplicate = await this.invoicesModel.findOne({ companyCode: dto.companyCode, invoiceNumber: dto.invoiceNumber });
    const invoice = await this.invoicesModel.create({
      ...dto,
      vendorName,
      status: duplicate ? 'amount_mismatch' : 'pending_review',
      capturedBy,
    });
    await this.audit(capturedBy || 'client-app', 'invoice.uploaded', dto.companyCode, { invoiceNumber: dto.invoiceNumber });
    return invoice;
  }

  async updateInvoice(id: string, dto: PatchInvoiceDto) {
    const existing = await this.invoicesModel.findById(id);
    if (!existing) throw new NotFoundException('Invoice not found');
    const company = await this.companiesModel.findOne({ code: existing.companyCode }).lean();
    if (dto.vendorName) dto.vendorName = this.sanitizeVendor(dto.vendorName, company?.name);
    const { status, ...rest } = dto;
    Object.assign(existing, rest);
    if (status) existing.status = status as typeof existing.status;
    else if (existing.status === 'processing') existing.status = 'pending_review';
    await existing.save();
    await this.audit('admin-portal', 'invoice.updated', existing.companyCode, { invoiceNumber: existing.invoiceNumber, status: existing.status });
    return existing;
  }

  private sanitizeVendor(vendorName: string, businessName?: string) {
    if (!businessName) return vendorName;
    const a = vendorName.toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();
    const b = businessName.toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();
    if (a && b && (a === b || a.includes(b) || b.includes(a))) return 'Unknown vendor';
    return vendorName;
  }

  async reconcile(companyCode: string, formType: '2A' | '2B', input: { csv?: string; rows?: ParsedGstRow[] }) {
    const rows = input.rows?.length ? input.rows : parseGstCsv(input.csv || '');
    if (!rows.length) throw new BadRequestException('No valid GSTR rows found. Use CSV with invoice number and amount.');

    const invoices = await this.invoicesModel.find({ companyCode });
    const byNumber = new Map(invoices.map((inv) => [normalizeInvoiceNo(inv.invoiceNumber), inv]));
    const matchedBillIds = new Set<string>();

    await this.portalModel.deleteMany({ companyCode, formType });

    const portalResults: Array<Record<string, unknown>> = [];
    for (const row of rows) {
      const key = normalizeInvoiceNo(row.invoiceNumber);
      const bill = byNumber.get(key);
      let matchStatus: 'matched' | 'amount_mismatch' | 'books_missing' = 'books_missing';
      let billAmount: number | undefined;
      let billId: string | undefined;

      if (bill) {
        billId = String(bill._id);
        billAmount = bill.invoiceAmount;
        matchedBillIds.add(billId);
        const amountOk = Math.abs(row.invoiceAmount - bill.invoiceAmount) <= 1;
        const gstinOk = !row.gstin || !bill.gstin || row.gstin.toUpperCase() === bill.gstin.toUpperCase() || bill.gstin.startsWith('00');
        matchStatus = amountOk && gstinOk ? 'matched' : 'amount_mismatch';

        if (formType === '2A') {
          bill.status2a = matchStatus === 'matched' ? 'matched' : 'amount_mismatch';
          bill.amount2a = row.invoiceAmount;
        } else {
          bill.status2b = matchStatus === 'matched' ? 'matched' : 'amount_mismatch';
          bill.amount2b = row.invoiceAmount;
        }
        this.syncOverallStatus(bill);
        await bill.save();
      }

      const portal = await this.portalModel.create({
        companyCode,
        formType,
        invoiceNumber: row.invoiceNumber,
        invoiceAmount: row.invoiceAmount,
        gstin: row.gstin,
        vendorName: row.vendorName,
        invoiceDate: row.invoiceDate,
        taxableAmount: row.taxableAmount,
        matchStatus,
        billId,
        billAmount,
      });
      portalResults.push({
        invoiceNumber: portal.invoiceNumber,
        matchStatus,
        portalAmount: portal.invoiceAmount,
        billAmount,
        gstin: portal.gstin,
        vendorName: portal.vendorName || bill?.vendorName,
      });
    }

    for (const bill of invoices) {
      if (matchedBillIds.has(String(bill._id))) continue;
      if (formType === '2A') {
        bill.status2a = 'not_in_portal';
        bill.amount2a = undefined;
      } else {
        bill.status2b = 'not_in_portal';
        bill.amount2b = undefined;
      }
      this.syncOverallStatus(bill);
      await bill.save();
    }

    await this.audit('admin-portal', `gstr.${formType}.reconciled`, companyCode, { imported: rows.length });
    return this.gstrSummary(companyCode, formType, portalResults);
  }

  private syncOverallStatus(bill: InvoiceDocument) {
    if (bill.status === 'processing' || bill.status === 'pending_review' || bill.status === 'draft') return;
    if (bill.status2a === 'matched' && bill.status2b === 'matched') bill.status = 'matched';
    else if (bill.status2a === 'amount_mismatch' || bill.status2b === 'amount_mismatch') bill.status = 'amount_mismatch';
    else if (bill.status2a === 'not_in_portal' || bill.status2b === 'not_in_portal') bill.status = 'client_only';
  }

  async gstrSummary(companyCode: string, _formType?: '2A' | '2B', latestPortal?: Array<Record<string, unknown>>) {
    const invoices = await this.invoicesModel.find({ companyCode }).lean();
    const portal = await this.portalModel.find({ companyCode }).lean();

    const bucket = (type: '2A' | '2B') => {
      const statusKey = type === '2A' ? 'status2a' : 'status2b';
      const amountKey = type === '2A' ? 'amount2a' : 'amount2b';
      const bills = invoices.map((inv) => ({
        _id: String(inv._id),
        vendorName: inv.vendorName,
        vendorPhone: inv.vendorPhone,
        gstin: inv.gstin,
        invoiceNumber: inv.invoiceNumber,
        invoiceDate: inv.invoiceDate,
        invoiceAmount: inv.invoiceAmount,
        matchStatus: inv[statusKey],
        portalAmount: inv[amountKey],
      }));
      return {
        matched: bills.filter((b) => b.matchStatus === 'matched'),
        amountMismatch: bills.filter((b) => b.matchStatus === 'amount_mismatch'),
        inBooksNotInForm: bills.filter((b) => b.matchStatus === 'not_in_portal'),
        inFormNotInBooks: portal
          .filter((p) => p.formType === type && p.matchStatus === 'books_missing')
          .map((p) => ({
            invoiceNumber: p.invoiceNumber,
            invoiceAmount: p.invoiceAmount,
            gstin: p.gstin,
            vendorName: p.vendorName,
            invoiceDate: p.invoiceDate,
            matchStatus: 'portal_only',
          })),
        counts: {
          matched: bills.filter((b) => b.matchStatus === 'matched').length,
          amountMismatch: bills.filter((b) => b.matchStatus === 'amount_mismatch').length,
          inBooksNotInForm: bills.filter((b) => b.matchStatus === 'not_in_portal').length,
          inFormNotInBooks: portal.filter((p) => p.formType === type && p.matchStatus === 'books_missing').length,
          unchecked: bills.filter((b) => b.matchStatus === 'unchecked').length,
        },
      };
    };

    return {
      companyCode,
      form2A: bucket('2A'),
      form2B: bucket('2B'),
      latestPortal,
      smsReadyMissing2A: invoices.filter((i) => i.status2a === 'not_in_portal' && /^[6-9]\d{9}$/.test(String(i.vendorPhone || '').replace(/\D/g, '').slice(-10))).length,
    };
  }

  async smsMissingFromForm(companyCode: string, formType: '2A' | '2B' = '2A') {
    const statusKey = formType === '2A' ? 'status2a' : 'status2b';
    const invoices = await this.invoicesModel.find({ companyCode, [statusKey]: 'not_in_portal' });
    const results = [];

    for (const invoice of invoices) {
      const phone = String(invoice.vendorPhone || '').replace(/\D/g, '').slice(-10);
      if (!/^[6-9]\d{9}$/.test(phone)) {
        results.push({ invoiceNumber: invoice.invoiceNumber, vendor: invoice.vendorName, ok: false, detail: 'No valid phone on bill' });
        continue;
      }
      const message = `GST Alert: Invoice ${invoice.invoiceNumber} (Rs ${Math.round(invoice.invoiceAmount)}) is not reflected in our GSTR-${formType}. Please file/upload so we can claim ITC. - ${companyCode}`;
      const sms = await this.sms.sendSms(phone, message);
      const reminder = await this.remindersModel.create({
        companyCode,
        vendor: invoice.vendorName,
        channel: 'sms',
        amount: invoice.invoiceAmount,
        phone,
        invoiceNumber: invoice.invoiceNumber,
        invoiceId: String(invoice._id),
        message,
        status: sms.ok ? 'sent' : 'failed',
        simulated: sms.simulated,
        providerDetail: sms.detail,
      });
      results.push({
        invoiceNumber: invoice.invoiceNumber,
        vendor: invoice.vendorName,
        phone,
        ok: sms.ok,
        simulated: sms.simulated,
        detail: sms.detail,
        reminderId: String(reminder._id),
      });
    }

    await this.audit('admin-portal', `sms.missing_${formType}`, companyCode, { count: results.length });
    return { formType, sent: results.filter((r) => r.ok).length, failed: results.filter((r) => !r.ok).length, results };
  }

  async createReminder(dto: ReminderDto) {
    let status: 'pending' | 'sent' | 'failed' = 'pending';
    let simulated = false;
    let providerDetail: string | undefined;
    const phone = dto.phone?.replace(/\D/g, '').slice(-10);
    const message = dto.message || `GST reminder for ${dto.vendor}: please confirm invoice filing. Amount Rs ${Math.round(dto.amount)}.`;

    if (dto.channel === 'sms' && phone) {
      const sms = await this.sms.sendSms(phone, message);
      status = sms.ok ? 'sent' : 'failed';
      simulated = sms.simulated;
      providerDetail = sms.detail;
    }

    const reminder = await this.remindersModel.create({
      ...dto,
      phone,
      message,
      status,
      simulated,
      providerDetail,
    });
    await this.audit('admin-portal', 'reminder.queued', dto.companyCode, { vendor: dto.vendor, channel: dto.channel, status });
    return reminder;
  }

  reminders(companyCode: string) {
    return this.remindersModel.find({ companyCode }).sort({ createdAt: -1 }).lean();
  }

  async overview() {
    const [companies, invoices, users] = await Promise.all([
      this.companiesModel.find().lean(),
      this.invoicesModel.find().select('ocrConfidence status status2a').lean(),
      this.usersModel.countDocuments({ role: { $ne: 'super_admin' } }),
    ]);
    const now = Date.now();
    return {
      companies: companies.length,
      activeCompanies: companies.filter((c) => c.status === 'active').length,
      expiringSubscriptions: companies.filter((c) => new Date(c.subscriptionExpiresAt).getTime() < now + 1000 * 60 * 60 * 24 * 45).length,
      expiredSubscriptions: companies.filter((c) => new Date(c.subscriptionExpiresAt).getTime() < now).length,
      invoiceVolume: invoices.length,
      accounts: users,
      ocrSuccessRate: Math.round((invoices.filter((i) => i.ocrConfidence > 0.82).length / Math.max(invoices.length, 1)) * 100),
      missingIn2A: invoices.filter((i) => i.status2a === 'not_in_portal').length,
      systemHealth: 'operational',
    };
  }

  async dashboard(companyCode: string) {
    const invoices = await this.invoices(companyCode);
    const today = new Date().toISOString().slice(0, 10);
    return {
      todaysUploads: invoices.filter((i) => String((i as unknown as { createdAt?: string }).createdAt).slice(0, 10) === today).length,
      pendingOcrReviews: invoices.filter((i) => i.status === 'pending_review' || i.status === 'processing').length,
      gstRecovered: invoices.filter((i) => i.status2a === 'matched' || i.status === 'matched').reduce((sum, i) => sum + i.gstAmount, 0),
      missingIn2A: invoices.filter((i) => i.status2a === 'not_in_portal').length,
      missingIn2B: invoices.filter((i) => i.status2b === 'not_in_portal').length,
      amountMismatches: invoices.filter((i) => i.status2a === 'amount_mismatch' || i.status2b === 'amount_mismatch').length,
    };
  }

  subscription(companyCode: string) {
    return this.companiesModel.findOne({ code: companyCode }).lean();
  }

  auditLogs() {
    return this.auditModel.find().sort({ createdAt: -1 }).limit(40).lean();
  }

  audit(actor: string, action: string, companyCode?: string, metadata?: Record<string, unknown>) {
    return this.auditModel.create({ actor, action, companyCode, metadata });
  }

  private makeLicenseCode(businessName: string) {
    const slug = businessName.replace(/[^a-zA-Z0-9]+/g, '').slice(0, 8).toUpperCase() || 'CO';
    const year = new Date().getFullYear();
    const salt = createHash('sha1').update(`${businessName}-${Date.now()}-${randomBytes(3).toString('hex')}`).digest('hex').slice(0, 4).toUpperCase();
    return `${slug}-${year}-GST-${salt}`;
  }
}
