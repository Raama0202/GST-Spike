import 'reflect-metadata';
import { NestFactory } from '@nestjs/core';
import { AppModule } from './modules/app.module';
import { SuiteService } from './modules/suite.service';

async function seed() {
  const app = await NestFactory.createApplicationContext(AppModule);
  const suite = app.get(SuiteService);
  await suite.seed();
  await app.close();
  console.log('Seeded GST SaaS Suite demo data.');
}

void seed();
