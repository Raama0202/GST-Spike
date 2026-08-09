import { Body, Controller, Get, Post, Query, UseGuards } from '@nestjs/common';
import { IsIn, IsOptional, IsString } from 'class-validator';
import { JwtAuthGuard } from './jwt-auth.guard';
import { Roles } from './roles.decorator';
import { RolesGuard } from './roles.guard';
import { PaymentsService } from './payments.service';

class CreatePaymentOrderDto {
  @IsString() companyCode!: string;
  @IsIn(['monthly', 'yearly']) plan!: 'monthly' | 'yearly';
}

class VerifyPaymentDto {
  @IsString() companyCode!: string;
  @IsIn(['monthly', 'yearly']) plan!: 'monthly' | 'yearly';
  @IsString() orderId!: string;
  @IsString() paymentId!: string;
  @IsOptional() @IsString() signature?: string;
}

@Controller('payments')
@UseGuards(JwtAuthGuard, RolesGuard)
export class PaymentsController {
  constructor(private readonly payments: PaymentsService) {}

  @Get('config')
  config() {
    return this.payments.publicConfig();
  }

  @Post('create-order')
  createOrder(@Body() dto: CreatePaymentOrderDto) {
    return this.payments.createOrder(dto.companyCode, dto.plan);
  }

  @Post('verify')
  verify(@Body() dto: VerifyPaymentDto) {
    return this.payments.verify(dto);
  }

  @Get('history')
  @Roles('super_admin', 'owner')
  history(@Query('companyCode') companyCode?: string) {
    return this.payments.list(companyCode);
  }
}
