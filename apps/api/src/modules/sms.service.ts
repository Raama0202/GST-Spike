import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

export type SmsResult = {
  phone: string;
  ok: boolean;
  simulated: boolean;
  provider?: string;
  detail?: string;
};

@Injectable()
export class SmsService {
  private readonly logger = new Logger(SmsService.name);

  constructor(private readonly config: ConfigService) {}

  /** Fast2SMS free signup credit (~₹50). Quick route needs no DLT for testing. */
  async sendSms(phone: string, message: string): Promise<SmsResult> {
    const normalized = phone.replace(/\D/g, '').slice(-10);
    if (!/^[6-9]\d{9}$/.test(normalized)) {
      return { phone, ok: false, simulated: false, detail: 'Invalid Indian mobile number' };
    }

    const apiKey = this.config.get<string>('FAST2SMS_API_KEY') || this.config.get<string>('SMS_PROVIDER_API_KEY');
    if (!apiKey) {
      this.logger.warn(`SMS simulated (set FAST2SMS_API_KEY) → ${normalized}: ${message}`);
      return { phone: normalized, ok: true, simulated: true, provider: 'dev-log', detail: 'No API key — queued as simulated send' };
    }

    try {
      const url = new URL('https://www.fast2sms.com/dev/bulkV2');
      url.searchParams.set('route', this.config.get<string>('FAST2SMS_ROUTE') || 'q');
      url.searchParams.set('message', message.slice(0, 200));
      url.searchParams.set('numbers', normalized);
      url.searchParams.set('flash', '0');

      const response = await fetch(url, {
        method: 'GET',
        headers: { authorization: apiKey },
      });
      const body = await response.text();
      let ok = response.ok;
      try {
        const json = JSON.parse(body) as { return?: boolean; message?: string | string[] };
        ok = Boolean(json.return ?? response.ok);
        return { phone: normalized, ok, simulated: false, provider: 'fast2sms', detail: Array.isArray(json.message) ? json.message.join(', ') : String(json.message ?? body) };
      } catch {
        return { phone: normalized, ok, simulated: false, provider: 'fast2sms', detail: body.slice(0, 200) };
      }
    } catch (error) {
      return { phone: normalized, ok: false, simulated: false, provider: 'fast2sms', detail: error instanceof Error ? error.message : 'SMS failed' };
    }
  }
}
