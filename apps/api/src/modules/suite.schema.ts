import { Prop, Schema, SchemaFactory } from '@nestjs/mongoose';
import { HydratedDocument } from 'mongoose';

export type Role = 'super_admin' | 'owner' | 'chartered_accountant' | 'accountant' | 'supervisor' | 'worker' | 'manager';
export type InvoiceStatus = 'processing' | 'draft' | 'pending_review' | 'synced' | 'matched' | 'client_only' | 'gst_only' | 'amount_mismatch';
export type GstrMatchStatus = 'unchecked' | 'matched' | 'amount_mismatch' | 'not_in_portal' | 'portal_only';
export type ReminderStatus = 'pending' | 'sent' | 'failed' | 'manual_follow_up';
export type Plan = 'trial' | 'monthly' | 'yearly';

@Schema({ timestamps: true })
export class Company {
  @Prop({ required: true }) name!: string;
  @Prop({ required: true, unique: true }) code!: string;
  @Prop({ default: 'active' }) status!: 'active' | 'suspended';
  @Prop({ required: true }) subscriptionExpiresAt!: Date;
  @Prop({ default: 'trial' }) plan!: Plan;
  @Prop({ type: [String], default: ['OCR', 'GST_RECONCILIATION'] }) featureFlags!: string[];
  @Prop({ default: 0 }) storageMb!: number;
  @Prop() phone?: string;
}
export type CompanyDocument = HydratedDocument<Company>;
export const CompanySchema = SchemaFactory.createForClass(Company);

@Schema({ timestamps: true })
export class User {
  @Prop({ required: true }) name!: string;
  @Prop({ required: true, unique: true }) email!: string;
  @Prop({ required: true }) passwordHash!: string;
  @Prop({ required: true }) role!: Role;
  @Prop() companyCode?: string;
  @Prop({ default: 'active' }) status!: 'active' | 'locked';
  @Prop() phone?: string;
}
export type UserDocument = HydratedDocument<User>;
export const UserSchema = SchemaFactory.createForClass(User);

@Schema({ timestamps: true })
export class Invoice {
  @Prop({ required: true }) companyCode!: string;
  @Prop({ required: true }) vendorName!: string;
  @Prop({ required: true }) gstin!: string;
  @Prop({ required: true }) invoiceNumber!: string;
  @Prop({ required: true }) invoiceDate!: string;
  @Prop({ required: true }) vendorPhone!: string;
  @Prop({ required: true }) taxableAmount!: number;
  @Prop({ required: true }) gstAmount!: number;
  /** Grand total on the bill — labeled Invoice Amount in UI */
  @Prop({ required: true }) invoiceAmount!: number;
  @Prop({ default: 0.5 }) ocrConfidence!: number;
  @Prop({ default: 'pending_review' }) status!: InvoiceStatus;
  @Prop({ default: 'unchecked' }) status2a!: GstrMatchStatus;
  @Prop({ default: 'unchecked' }) status2b!: GstrMatchStatus;
  @Prop() amount2a?: number;
  @Prop() amount2b?: number;
  @Prop() imageUrl?: string;
  @Prop() notes?: string;
  @Prop() capturedBy?: string;
}
export type InvoiceDocument = HydratedDocument<Invoice>;
export const InvoiceSchema = SchemaFactory.createForClass(Invoice);
InvoiceSchema.index({ companyCode: 1, invoiceNumber: 1 });

@Schema({ timestamps: true })
export class GstPortalRow {
  @Prop({ required: true }) companyCode!: string;
  @Prop({ required: true }) formType!: '2A' | '2B';
  @Prop({ required: true }) invoiceNumber!: string;
  @Prop({ required: true }) invoiceAmount!: number;
  @Prop() gstin?: string;
  @Prop() vendorName?: string;
  @Prop() invoiceDate?: string;
  @Prop() taxableAmount?: number;
  @Prop({ default: 'books_missing' }) matchStatus!: 'matched' | 'amount_mismatch' | 'books_missing';
  @Prop() billId?: string;
  @Prop() billAmount?: number;
}
export type GstPortalRowDocument = HydratedDocument<GstPortalRow>;
export const GstPortalRowSchema = SchemaFactory.createForClass(GstPortalRow);
GstPortalRowSchema.index({ companyCode: 1, formType: 1, invoiceNumber: 1 });

@Schema({ timestamps: true })
export class Reminder {
  @Prop({ required: true }) companyCode!: string;
  @Prop({ required: true }) vendor!: string;
  @Prop({ required: true }) channel!: 'email' | 'sms' | 'whatsapp' | 'manual';
  @Prop({ default: 'pending' }) status!: ReminderStatus;
  @Prop({ required: true }) amount!: number;
  @Prop() phone?: string;
  @Prop() invoiceNumber?: string;
  @Prop() invoiceId?: string;
  @Prop() message?: string;
  @Prop() providerDetail?: string;
  @Prop({ default: false }) simulated?: boolean;
}
export type ReminderDocument = HydratedDocument<Reminder>;
export const ReminderSchema = SchemaFactory.createForClass(Reminder);

@Schema({ timestamps: true })
export class Payment {
  @Prop({ required: true }) companyCode!: string;
  @Prop({ required: true }) plan!: 'monthly' | 'yearly';
  @Prop({ required: true }) amountPaise!: number;
  @Prop({ default: 'INR' }) currency!: string;
  @Prop({ default: 'razorpay' }) provider!: string;
  @Prop({ required: true }) orderId!: string;
  @Prop() providerPaymentId?: string;
  @Prop() signature?: string;
  @Prop({ default: 'created' }) status!: 'created' | 'paid' | 'failed';
  @Prop({ default: false }) simulated!: boolean;
}
export type PaymentDocument = HydratedDocument<Payment>;
export const PaymentSchema = SchemaFactory.createForClass(Payment);

@Schema({ timestamps: true })
export class AuditLog {
  @Prop({ required: true }) actor!: string;
  @Prop({ required: true }) action!: string;
  @Prop() companyCode?: string;
  @Prop({ type: Object }) metadata?: Record<string, unknown>;
}
export const AuditLogSchema = SchemaFactory.createForClass(AuditLog);
