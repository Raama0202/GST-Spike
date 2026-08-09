import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { readFile } from 'fs/promises';
import { parseInvoiceText, ParsedInvoice } from './invoice-ocr';

type GeminiInvoiceJson = {
  vendorName?: string;
  gstin?: string;
  invoiceNumber?: string;
  invoiceDate?: string;
  vendorPhone?: string;
  taxableAmount?: number;
  gstAmount?: number;
  invoiceAmount?: number;
  confidence?: number;
  rawText?: string;
};

@Injectable()
export class GeminiBillService {
  private readonly logger = new Logger(GeminiBillService.name);

  constructor(private readonly config: ConfigService) {}

  hasApiKey() {
    return Boolean(this.config.get<string>('GEMINI_API_KEY'));
  }

  /**
   * Extract structured invoice fields from a bill image using Gemini Vision.
   * Falls back to local text parse if Gemini is unavailable.
   */
  async extractFromImage(filePath: string, businessName: string, mimeType = 'image/jpeg'): Promise<ParsedInvoice & { engine: string }> {
    const key = this.config.get<string>('GEMINI_API_KEY');
    if (!key) {
      this.logger.warn('GEMINI_API_KEY missing — using empty extraction (manual edit)');
      return { ...parseInvoiceText('', businessName), engine: 'none', ocrConfidence: 0.3, notes: 'No Gemini API key. Enter fields manually.' };
    }

    try {
      const buffer = await readFile(filePath);
      const base64 = buffer.toString('base64');
      const model = this.config.get<string>('GEMINI_MODEL') || 'gemini-2.0-flash';
      const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`;

      const prompt = `You are an Indian GST invoice extractor.
Return ONLY JSON with these fields:
vendorName, gstin, invoiceNumber, invoiceDate (YYYY-MM-DD), vendorPhone (10 digits), taxableAmount, gstAmount, invoiceAmount, confidence (0-1), rawText.
Rules:
- vendorName is the SUPPLIER/SELLER who issued the bill — NEVER "${businessName}" (that is the buyer/customer business).
- If both buyer and seller names appear, choose the seller/vendor only.
- invoiceAmount is the grand total / net payable / invoice amount (not taxable alone).
- Prefer numbers printed on the bill. Use 0 if missing.
- gstin must match Indian GSTIN pattern when present.`;

      const response = await fetch(url, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-goog-api-key': key,
        },
        body: JSON.stringify({
          contents: [{
            parts: [
              { text: prompt },
              { inline_data: { mime_type: mimeType || 'image/jpeg', data: base64 } },
            ],
          }],
          generationConfig: {
            temperature: 0.1,
            responseMimeType: 'application/json',
          },
        }),
      });

      const payload = await response.json() as {
        error?: { message?: string };
        candidates?: Array<{ content?: { parts?: Array<{ text?: string }> } }>;
      };

      if (!response.ok) {
        throw new Error(payload.error?.message || `Gemini HTTP ${response.status}`);
      }

      const text = payload.candidates?.[0]?.content?.parts?.map((p) => p.text || '').join('') || '';
      const json = this.safeJson(text);
      if (!json) {
        // Model returned prose — parse as OCR text
        const parsed = parseInvoiceText(text, businessName);
        return { ...parsed, engine: 'gemini-text-fallback', notes: `${parsed.notes} (Gemini text fallback)` };
      }

      const vendorName = this.pickVendor(json.vendorName || '', businessName);
      const confidence = Math.max(0.4, Math.min(0.99, Number(json.confidence ?? 0.9)));
      return {
        vendorName: vendorName || 'Unknown vendor',
        gstin: String(json.gstin || '').toUpperCase(),
        invoiceNumber: String(json.invoiceNumber || `TMP-${Date.now().toString(36).toUpperCase()}`),
        invoiceDate: this.normalizeDate(String(json.invoiceDate || '')) || new Date().toISOString().slice(0, 10),
        vendorPhone: String(json.vendorPhone || '').replace(/\D/g, '').slice(-10) || '0000000000',
        taxableAmount: Number(json.taxableAmount || 0),
        gstAmount: Number(json.gstAmount || 0),
        invoiceAmount: Number(json.invoiceAmount || 0) || Number(json.taxableAmount || 0) + Number(json.gstAmount || 0),
        ocrConfidence: confidence,
        notes: `Gemini Vision extracted fields (confidence ${Math.round(confidence * 100)}%)`,
        engine: 'gemini',
      };
    } catch (error) {
      this.logger.error(`Gemini extraction failed: ${error instanceof Error ? error.message : error}`);
      // Last resort: local tesseract text + regex
      try {
        const { createWorker } = await import('tesseract.js');
        const worker = await createWorker('eng');
        const { data } = await worker.recognize(filePath);
        await worker.terminate();
        const parsed = parseInvoiceText(data.text || '', businessName);
        return { ...parsed, engine: 'tesseract-fallback', notes: `${parsed.notes} (Gemini failed; Tesseract fallback)` };
      } catch {
        return {
          ...parseInvoiceText('', businessName),
          engine: 'failed',
          ocrConfidence: 0.3,
          notes: `AI extraction failed: ${error instanceof Error ? error.message : 'unknown'}. Edit manually.`,
        };
      }
    }
  }

  private safeJson(text: string): GeminiInvoiceJson | null {
    try {
      const cleaned = text.replace(/^```json\s*/i, '').replace(/```$/i, '').trim();
      return JSON.parse(cleaned) as GeminiInvoiceJson;
    } catch {
      const match = text.match(/\{[\s\S]*\}/);
      if (!match) return null;
      try { return JSON.parse(match[0]) as GeminiInvoiceJson; } catch { return null; }
    }
  }

  private pickVendor(vendorName: string, businessName: string) {
    const a = vendorName.toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();
    const b = businessName.toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();
    if (a && b && (a === b || a.includes(b) || b.includes(a))) return '';
    return vendorName.trim();
  }

  private normalizeDate(value: string) {
    if (!value) return '';
    if (/^\d{4}-\d{2}-\d{2}$/.test(value)) return value;
    const parts = value.split(/[\/.-]/);
    if (parts.length !== 3) return '';
    const [d, m, y] = parts;
    const year = y.length === 2 ? `20${y}` : y;
    return `${year}-${m.padStart(2, '0')}-${d.padStart(2, '0')}`;
  }
}
