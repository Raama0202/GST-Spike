import { Module } from '@nestjs/common';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { JwtModule } from '@nestjs/jwt';
import { MongooseModule } from '@nestjs/mongoose';
import { AuthController } from './auth.controller';
import { HealthController } from './health.controller';
import { validateEnvironment } from './config';
import { SuiteController } from './suite.controller';
import { SuiteService } from './suite.service';
import { JwtAuthGuard } from './jwt-auth.guard';
import { RolesGuard } from './roles.guard';
import { AuditLog, AuditLogSchema, Company, CompanySchema, GstPortalRow, GstPortalRowSchema, Invoice, InvoiceSchema, Payment, PaymentSchema, Reminder, ReminderSchema, User, UserSchema } from './suite.schema';
import { SmsService } from './sms.service';
import { GeminiBillService } from './gemini-bill.service';
import { PaymentsService } from './payments.service';
import { PaymentsController } from './payments.controller';

async function resolveMongoUri(config: ConfigService) {
  const configured = config.get<string>('MONGODB_URI');
  const flag = config.get<string>('USE_MEMORY_MONGO') ?? 'auto';
  const forceMemory = flag === 'true';
  const forceRemote = flag === 'false';
  const looksLocal = !configured || configured.includes('127.0.0.1') || configured.includes('localhost');
  const isAtlas = Boolean(configured?.includes('mongodb+srv://'));

  if (forceRemote || isAtlas) {
    console.log('[mongo] Using configured MongoDB URI');
    return { uri: configured || 'mongodb://127.0.0.1:27017/gst-suite' };
  }
  if (forceMemory || (flag === 'auto' && looksLocal && (config.get<string>('NODE_ENV') ?? 'development') !== 'production')) {
    try {
      const { MongoMemoryServer } = await import('mongodb-memory-server');
      const mongod = await MongoMemoryServer.create();
      const uri = mongod.getUri('gst-suite');
      (globalThis as { __gstMongoMemory?: unknown }).__gstMongoMemory = mongod;
      console.log('[mongo] Using in-memory MongoDB for local demo');
      return { uri };
    } catch (error) {
      if (configured) return { uri: configured };
      throw error;
    }
  }
  return { uri: configured || 'mongodb://127.0.0.1:27017/gst-suite' };
}

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true, validate: validateEnvironment }),
    JwtModule.registerAsync({
      inject: [ConfigService],
      useFactory: (config: ConfigService) => ({
        secret: config.getOrThrow<string>('JWT_SECRET'),
        signOptions: { expiresIn: '8h' },
      }),
    }),
    MongooseModule.forRootAsync({
      inject: [ConfigService],
      useFactory: async (config: ConfigService) => resolveMongoUri(config),
    }),
    MongooseModule.forFeature([
      { name: Company.name, schema: CompanySchema },
      { name: User.name, schema: UserSchema },
      { name: Invoice.name, schema: InvoiceSchema },
      { name: GstPortalRow.name, schema: GstPortalRowSchema },
      { name: Reminder.name, schema: ReminderSchema },
      { name: Payment.name, schema: PaymentSchema },
      { name: AuditLog.name, schema: AuditLogSchema },
    ]),
  ],
  controllers: [AuthController, HealthController, SuiteController, PaymentsController],
  providers: [SuiteService, SmsService, GeminiBillService, PaymentsService, JwtAuthGuard, RolesGuard],
})
export class AppModule {}
