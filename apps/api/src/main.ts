import 'reflect-metadata';
import { setServers } from 'dns';
import { ValidationPipe } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { NestFactory } from '@nestjs/core';
import { NestExpressApplication } from '@nestjs/platform-express';
import helmet from 'helmet';
import { join } from 'path';
import { AppModule } from './modules/app.module';
import { parseOrigins } from './modules/config';

// Some Windows/ISP resolvers refuse MongoDB SRV lookups; prefer public DNS.
try {
  setServers(['8.8.8.8', '1.1.1.1']);
} catch {
  /* ignore */
}

async function bootstrap() {
  const app = await NestFactory.create<NestExpressApplication>(AppModule);
  const config = app.get(ConfigService);
  app.use(helmet({ crossOriginResourcePolicy: { policy: 'cross-origin' } }));
  app.enableCors({
    origin: parseOrigins(config.get<string>('WEB_ORIGIN')),
    credentials: true,
  });
  const uploadDir = config.get<string>('UPLOAD_DIR') || join(process.cwd(), 'uploads');
  app.useStaticAssets(uploadDir, { prefix: '/uploads' });
  app.setGlobalPrefix('api');
  app.useGlobalPipes(new ValidationPipe({ whitelist: true, transform: true, forbidNonWhitelisted: true }));
  await app.listen(Number(config.getOrThrow<string>('PORT')));
}

void bootstrap();
