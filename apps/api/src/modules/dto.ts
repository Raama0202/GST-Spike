import { Type } from 'class-transformer';
import { IsArray, IsEmail, IsIn, IsNumber, IsOptional, IsString, Min, MinLength, ValidateNested } from 'class-validator';

export class LoginDto {
  @IsEmail() email!: string;
  @IsString() @MinLength(6) password!: string;
}

export class RegisterDto {
  @IsString() @MinLength(2) businessName!: string;
  @IsString() @MinLength(2) name!: string;
  @IsEmail() email!: string;
  @IsString() @MinLength(6) password!: string;
  @IsOptional() @IsString() phone?: string;
}

export class CreateCompanyDto {
  @IsString() name!: string;
  @IsOptional() @IsString() code?: string;
  @IsOptional() @IsString() subscriptionExpiresAt?: string;
  @IsOptional() @IsIn(['trial', 'monthly', 'yearly']) plan?: 'trial' | 'monthly' | 'yearly';
  @IsOptional() @IsEmail() ownerEmail?: string;
  @IsOptional() @IsString() ownerName?: string;
  @IsOptional() @IsString() @MinLength(6) ownerPassword?: string;
  @IsOptional() @IsString() phone?: string;
}

export class CompanyStatusDto {
  @IsIn(['active', 'suspended']) status!: 'active' | 'suspended';
}

export class ExtendSubscriptionDto {
  @IsString() subscriptionExpiresAt!: string;
  @IsOptional() @IsIn(['trial', 'monthly', 'yearly']) plan?: 'trial' | 'monthly' | 'yearly';
}

export class FeatureFlagsDto {
  @IsArray()
  @IsString({ each: true })
  featureFlags!: string[];
}

export class UpsertInvoiceDto {
  @IsString() companyCode!: string;
  @IsString() vendorName!: string;
  @IsString() gstin!: string;
  @IsString() invoiceNumber!: string;
  @IsString() invoiceDate!: string;
  @IsString() vendorPhone!: string;
  @IsNumber() @Min(0) taxableAmount!: number;
  @IsNumber() @Min(0) gstAmount!: number;
  @IsNumber() @Min(0) invoiceAmount!: number;
  @IsOptional() @IsNumber() ocrConfidence?: number;
  @IsOptional() @IsString() notes?: string;
}

export class PatchInvoiceDto {
  @IsOptional() @IsString() vendorName?: string;
  @IsOptional() @IsString() gstin?: string;
  @IsOptional() @IsString() invoiceNumber?: string;
  @IsOptional() @IsString() invoiceDate?: string;
  @IsOptional() @IsString() vendorPhone?: string;
  @IsOptional() @IsNumber() @Min(0) taxableAmount?: number;
  @IsOptional() @IsNumber() @Min(0) gstAmount?: number;
  @IsOptional() @IsNumber() @Min(0) invoiceAmount?: number;
  @IsOptional() @IsNumber() ocrConfidence?: number;
  @IsOptional() @IsString() notes?: string;
  @IsOptional() @IsIn(['processing', 'draft', 'pending_review', 'synced', 'matched', 'client_only', 'gst_only', 'amount_mismatch'])
  status?: string;
}

export class ReminderDto {
  @IsString() companyCode!: string;
  @IsString() vendor!: string;
  @IsIn(['email', 'sms', 'whatsapp', 'manual']) channel!: 'email' | 'sms' | 'whatsapp' | 'manual';
  @IsNumber() amount!: number;
  @IsOptional() @IsString() phone?: string;
  @IsOptional() @IsString() invoiceNumber?: string;
  @IsOptional() @IsString() invoiceId?: string;
  @IsOptional() @IsString() message?: string;
}

export class GstImportRowDto {
  @IsString() invoiceNumber!: string;
  @IsNumber() @Min(0) invoiceAmount!: number;
  @IsOptional() @IsString() gstin?: string;
  @IsOptional() @IsString() vendorName?: string;
  @IsOptional() @IsString() invoiceDate?: string;
  @IsOptional() @IsNumber() taxableAmount?: number;
}

export class GstImportDto {
  @IsString() companyCode!: string;
  @IsIn(['2A', '2B']) formType!: '2A' | '2B';
  @IsOptional() @IsString() csv?: string;
  @IsOptional()
  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => GstImportRowDto)
  rows?: GstImportRowDto[];
}

export class SmsMissingDto {
  @IsString() companyCode!: string;
  @IsOptional() @IsIn(['2A', '2B']) formType?: '2A' | '2B';
}

export class UserStatusDto {
  @IsIn(['active', 'locked']) status!: 'active' | 'locked';
}
