import {
  BadRequestException,
  Body,
  Controller,
  Get,
  Param,
  Patch,
  Post,
  Query,
  Req,
  UploadedFile,
  UseGuards,
  UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { memoryStorage } from 'multer';
import { CompanyStatusDto, CreateCompanyDto, ExtendSubscriptionDto, FeatureFlagsDto, GstImportDto, PatchInvoiceDto, ReminderDto, SmsMissingDto, UpsertInvoiceDto, UserStatusDto } from './dto';
import { JwtAuthGuard } from './jwt-auth.guard';
import { Roles } from './roles.decorator';
import { RolesGuard } from './roles.guard';
import { SuiteService } from './suite.service';

type AuthRequest = { user?: { sub?: string; role?: string; companyCode?: string; name?: string } };

@Controller()
@UseGuards(JwtAuthGuard, RolesGuard)
export class SuiteController {
  constructor(private readonly suite: SuiteService) {}

  @Get('overview')
  @Roles('super_admin')
  overview() {
    return this.suite.overview();
  }

  @Get('companies')
  @Roles('super_admin')
  companies() {
    return this.suite.companies();
  }

  @Post('companies')
  @Roles('super_admin')
  createCompany(@Body() dto: CreateCompanyDto) {
    return this.suite.createCompany(dto);
  }

  @Patch('companies/:code/status')
  @Roles('super_admin')
  companyStatus(@Param('code') code: string, @Body() dto: CompanyStatusDto) {
    return this.suite.setCompanyStatus(code, dto.status);
  }

  @Patch('companies/:code/subscription')
  @Roles('super_admin')
  extendSubscription(@Param('code') code: string, @Body() dto: ExtendSubscriptionDto) {
    return this.suite.extendSubscription(code, dto);
  }

  @Patch('companies/:code/features')
  @Roles('super_admin')
  features(@Param('code') code: string, @Body() dto: FeatureFlagsDto) {
    return this.suite.setFeatures(code, dto.featureFlags);
  }

  @Get('users')
  @Roles('super_admin')
  users(@Query('companyCode') companyCode?: string) {
    return this.suite.users(companyCode);
  }

  @Patch('users/:id/status')
  @Roles('super_admin')
  userStatus(@Param('id') id: string, @Body() dto: UserStatusDto) {
    return this.suite.setUserStatus(id, dto.status);
  }

  @Get('dashboard')
  dashboard(@Query('companyCode') companyCode: string, @Req() req: AuthRequest) {
    return this.suite.dashboard(companyCode || req.user?.companyCode || '');
  }

  @Get('invoices')
  invoices(@Query('companyCode') companyCode: string, @Req() req: AuthRequest) {
    return this.suite.invoices(companyCode || req.user?.companyCode || '');
  }

  @Get('invoice/:id')
  invoice(@Param('id') id: string) {
    return this.suite.invoice(id);
  }

  @Post('invoice/capture')
  @UseInterceptors(FileInterceptor('image', { storage: memoryStorage(), limits: { fileSize: 8 * 1024 * 1024 } }))
  capture(
    @UploadedFile() file: Express.Multer.File,
    @Body('companyCode') companyCode: string,
    @Req() req: AuthRequest,
  ) {
    const code = companyCode || req.user?.companyCode;
    if (!file) throw new BadRequestException('Image required');
    if (!code) throw new BadRequestException('companyCode required');
    return this.suite.captureBillImage({ companyCode: code, file, capturedBy: req.user?.role });
  }

  @Post('invoice/upload')
  upload(@Body() dto: UpsertInvoiceDto, @Req() req: AuthRequest) {
    return this.suite.createInvoice(dto, req.user?.role);
  }

  @Patch('invoice/:id')
  updateInvoice(@Param('id') id: string, @Body() dto: PatchInvoiceDto) {
    return this.suite.updateInvoice(id, dto);
  }

  @Post('gst/import')
  importGst(@Body() dto: GstImportDto) {
    return this.suite.reconcile(dto.companyCode, dto.formType, { csv: dto.csv, rows: dto.rows });
  }

  @Get('gst/summary')
  gstrSummary(@Query('companyCode') companyCode: string, @Req() req: AuthRequest) {
    return this.suite.gstrSummary(companyCode || req.user?.companyCode || '');
  }

  @Post('gst/sms-missing')
  smsMissing(@Body() dto: SmsMissingDto) {
    return this.suite.smsMissingFromForm(dto.companyCode, dto.formType ?? '2A');
  }

  @Post('reminders/send')
  reminder(@Body() dto: ReminderDto) {
    return this.suite.createReminder(dto);
  }

  @Get('reminders')
  reminders(@Query('companyCode') companyCode: string, @Req() req: AuthRequest) {
    return this.suite.reminders(companyCode || req.user?.companyCode || '');
  }

  @Get('audit')
  @Roles('super_admin')
  audit() {
    return this.suite.auditLogs();
  }

  @Get('subscription')
  subscription(@Query('companyCode') companyCode: string, @Req() req: AuthRequest) {
    return this.suite.subscription(companyCode || req.user?.companyCode || '');
  }
}
