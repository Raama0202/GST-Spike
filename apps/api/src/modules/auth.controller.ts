import { Body, Controller, Post } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { LoginDto, RegisterDto } from './dto';
import { SuiteService } from './suite.service';

@Controller('auth')
export class AuthController {
  constructor(private readonly suite: SuiteService, private readonly jwt: JwtService) {}

  @Post('login')
  async login(@Body() dto: LoginDto) {
    const user = await this.suite.validateUser(dto.email, dto.password);
    const token = await this.jwt.signAsync({ sub: user.id, role: user.role, companyCode: user.companyCode, name: user.name });
    await this.suite.audit(user.email, 'login', user.companyCode);
    return { token, user };
  }

  @Post('register')
  async register(@Body() dto: RegisterDto) {
    const user = await this.suite.register(dto);
    const token = await this.jwt.signAsync({ sub: user.id, role: user.role, companyCode: user.companyCode, name: user.name });
    return { token, user };
  }
}
