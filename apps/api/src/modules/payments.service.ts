import { BadRequestException, Injectable, Logger, NotFoundException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { InjectModel } from '@nestjs/mongoose';
import { createHmac, randomBytes } from 'crypto';
import { Model } from 'mongoose';
import { AuditLog, Company, CompanyDocument, Payment, PaymentDocument } from './suite.schema';

@Injectable()
export class PaymentsService {
  private readonly logger = new Logger(PaymentsService.name);

  constructor(
    private readonly config: ConfigService,
    @InjectModel(Company.name) private companiesModel: Model<CompanyDocument>,
    @InjectModel(Payment.name) private paymentsModel: Model<PaymentDocument>,
    @InjectModel(AuditLog.name) private auditModel: Model<AuditLog>,
  ) {}

  publicConfig() {
    return {
      keyId: this.config.get<string>('RAZORPAY_KEY_ID') || '',
      enabled: Boolean(this.config.get<string>('RAZORPAY_KEY_ID') && this.config.get<string>('RAZORPAY_KEY_SECRET')),
      currency: 'INR',
      plans: {
        monthly: { amountPaise: this.planAmount('monthly'), label: 'Monthly', days: 30 },
        yearly: { amountPaise: this.planAmount('yearly'), label: 'Yearly', days: 365 },
      },
    };
  }

  private planAmount(plan: 'monthly' | 'yearly') {
    if (plan === 'yearly') return Number(this.config.get<string>('RAZORPAY_PLAN_YEARLY_PAISE') || 999900);
    return Number(this.config.get<string>('RAZORPAY_PLAN_MONTHLY_PAISE') || 99900);
  }

  async createOrder(companyCode: string, plan: 'monthly' | 'yearly') {
    const company = await this.companiesModel.findOne({ code: companyCode });
    if (!company) throw new NotFoundException('Company not found');

    const amount = this.planAmount(plan);
    const keyId = this.config.get<string>('RAZORPAY_KEY_ID');
    const keySecret = this.config.get<string>('RAZORPAY_KEY_SECRET');

    // Dev / free mode: simulated order (no Razorpay account needed)
    if (!keyId || !keySecret) {
      const orderId = `order_sim_${randomBytes(6).toString('hex')}`;
      const payment = await this.paymentsModel.create({
        companyCode,
        plan,
        amountPaise: amount,
        currency: 'INR',
        provider: 'razorpay',
        orderId,
        status: 'created',
        simulated: true,
      });
      this.logger.warn(`Razorpay keys missing — simulated order ${orderId}`);
      return {
        orderId,
        amount,
        currency: 'INR',
        keyId: '',
        simulated: true,
        paymentId: String(payment._id),
        companyName: company.name,
        plan,
      };
    }

    const auth = Buffer.from(`${keyId}:${keySecret}`).toString('base64');
    const receipt = `gst_${companyCode.slice(0, 12)}_${Date.now()}`.slice(0, 40);
    const response = await fetch('https://api.razorpay.com/v1/orders', {
      method: 'POST',
      headers: {
        Authorization: `Basic ${auth}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        amount,
        currency: 'INR',
        receipt,
        notes: { companyCode, plan },
      }),
    });
    const body = await response.json() as { id?: string; error?: { description?: string } };
    if (!response.ok || !body.id) throw new BadRequestException(body.error?.description || 'Razorpay order failed');

    const payment = await this.paymentsModel.create({
      companyCode,
      plan,
      amountPaise: amount,
      currency: 'INR',
      provider: 'razorpay',
      orderId: body.id,
      status: 'created',
      simulated: false,
    });

    return {
      orderId: body.id,
      amount,
      currency: 'INR',
      keyId,
      simulated: false,
      paymentId: String(payment._id),
      companyName: company.name,
      plan,
    };
  }

  async verify(opts: {
    companyCode: string;
    plan: 'monthly' | 'yearly';
    orderId: string;
    paymentId: string;
    signature?: string;
  }) {
    const payment = await this.paymentsModel.findOne({ orderId: opts.orderId, companyCode: opts.companyCode });
    if (!payment) throw new NotFoundException('Payment order not found');

    const keySecret = this.config.get<string>('RAZORPAY_KEY_SECRET');
    if (payment.simulated || !keySecret) {
      // Simulated checkout confirm
      payment.status = 'paid';
      payment.providerPaymentId = opts.paymentId || `pay_sim_${randomBytes(4).toString('hex')}`;
      await payment.save();
      return this.activateSubscription(opts.companyCode, opts.plan, payment);
    }

    if (!opts.signature) throw new BadRequestException('Missing Razorpay signature');
    const expected = createHmac('sha256', keySecret)
      .update(`${opts.orderId}|${opts.paymentId}`)
      .digest('hex');
    if (expected !== opts.signature) throw new BadRequestException('Invalid payment signature');

    payment.status = 'paid';
    payment.providerPaymentId = opts.paymentId;
    payment.signature = opts.signature;
    await payment.save();
    return this.activateSubscription(opts.companyCode, opts.plan, payment);
  }

  private async activateSubscription(companyCode: string, plan: 'monthly' | 'yearly', payment: PaymentDocument) {
    const company = await this.companiesModel.findOne({ code: companyCode });
    if (!company) throw new NotFoundException('Company not found');

    const days = plan === 'yearly' ? 365 : 30;
    const base = new Date(company.subscriptionExpiresAt) > new Date() ? new Date(company.subscriptionExpiresAt) : new Date();
    base.setDate(base.getDate() + days);
    company.subscriptionExpiresAt = base;
    company.plan = plan;
    company.status = 'active';
    await company.save();

    await this.auditModel.create({
      actor: 'razorpay',
      action: 'subscription.paid',
      companyCode,
      metadata: {
        plan,
        orderId: payment.orderId,
        amountPaise: payment.amountPaise,
        simulated: payment.simulated,
      },
    });

    return {
      ok: true,
      companyCode,
      plan,
      subscriptionExpiresAt: company.subscriptionExpiresAt,
      simulated: payment.simulated,
    };
  }

  list(companyCode?: string) {
    const filter = companyCode ? { companyCode } : {};
    return this.paymentsModel.find(filter).sort({ createdAt: -1 }).limit(50).lean();
  }
}
