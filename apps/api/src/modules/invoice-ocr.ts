export type ParsedInvoice = {
  vendorName: string;
  gstin: string;
  invoiceNumber: string;
  invoiceDate: string;
  vendorPhone: string;
  taxableAmount: number;
  gstAmount: number;
  invoiceAmount: number;
  ocrConfidence: number;
  notes: string;
};

/** Prefer vendor (supplier) name; never return the client's registered business name. */
export function parseInvoiceText(rawText: string, businessName?: string): ParsedInvoice {
  const text = rawText.replace(/\r/g, '\n');
  const flat = text.replace(/\s+/g, ' ').trim();
  const lines = text.split('\n').map((line) => line.trim()).filter(Boolean);

  const gstin = flat.match(/\b[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]\b/i)?.[0].toUpperCase() ?? '';
  const phone = flat.match(/\b(?:\+91[-\s]?)?[6-9][0-9]{9}\b/)?.[0]?.replace(/\D/g, '').slice(-10) ?? '';
  const invoiceNumber = flat.match(/\b(?:invoice|inv|bill)\s*(?:no|number|#)?[\s:.-]*([A-Z0-9/-]{3,})\b/i)?.[1] ?? '';
  const rawDate = flat.match(/\b(\d{4}-\d{2}-\d{2}|\d{1,2}[\/.-]\d{1,2}[\/.-]\d{2,4})\b/)?.[1];
  const taxableAmount = amountAfter(flat, ['taxable amount', 'taxable value', 'subtotal', 'sub total']) ?? 0;
  const cgst = amountAfter(flat, ['cgst']) ?? 0;
  const sgst = amountAfter(flat, ['sgst']) ?? 0;
  const igst = amountAfter(flat, ['igst']) ?? 0;
  const gstAmount = amountAfter(flat, ['gst amount', 'total gst', 'gst']) ?? ((cgst + sgst + igst) || 0);
  const invoiceAmount = amountAfter(flat, ['invoice amount', 'net amount', 'grand total', 'invoice total', 'total amount', 'total']) ?? 0;

  const vendorName = pickVendorName(lines, businessName);
  const found = [vendorName, gstin, invoiceNumber, rawDate, phone, taxableAmount, gstAmount, invoiceAmount].filter((v) => v !== '' && v !== 0).length;

  return {
    vendorName: vendorName || 'Unknown vendor',
    gstin,
    invoiceNumber: invoiceNumber || `TMP-${Date.now().toString(36).toUpperCase()}`,
    invoiceDate: rawDate ? normalizeDate(rawDate) : new Date().toISOString().slice(0, 10),
    vendorPhone: phone || '0000000000',
    taxableAmount,
    gstAmount,
    invoiceAmount: invoiceAmount || (taxableAmount + gstAmount),
    ocrConfidence: Math.max(0.4, Math.min(0.97, found / 8)),
    notes: `Server OCR parsed ${found}/8 fields`,
  };
}

function pickVendorName(lines: string[], businessName?: string) {
  const skip = /gstin|invoice|inv\.|bill|date|phone|taxable|total|cgst|sgst|igst|amount|rs\.?|inr|tax|hsn|qty|quantity|rate|buyer|bill to|ship to|customer|address|state|pin|pincode|e-?way|transport/i;
  const businessNorm = normalizeName(businessName ?? '');
  const candidates = lines.filter((line) => {
    if (line.length < 3 || line.length > 80) return false;
    if (skip.test(line)) return false;
    if (/^\d+([.,]\d+)?$/.test(line)) return false;
    if (businessNorm && namesMatch(line, businessNorm)) return false;
    return true;
  });
  // Bills often list vendor first; buyer/business later — take first non-business candidate
  return candidates[0] ?? '';
}

function namesMatch(a: string, businessNorm: string) {
  const left = normalizeName(a);
  if (!left || !businessNorm) return false;
  return left === businessNorm || left.includes(businessNorm) || businessNorm.includes(left);
}

function normalizeName(value: string) {
  return value.toLowerCase().replace(/[^a-z0-9]+/g, ' ').replace(/\s+/g, ' ').trim();
}

function amountAfter(text: string, labels: string[]) {
  for (const label of labels) {
    const match = text.match(new RegExp(`${label}\\s*[:=-]?\\s*(?:rs\\.?|inr|₹)?\\s*([0-9,]+(?:\\.\\d{1,2})?)`, 'i'));
    if (match) return Number(match[1].replace(/,/g, ''));
  }
  return undefined;
}

function normalizeDate(value: string) {
  if (/^\d{4}-\d{2}-\d{2}$/.test(value)) return value;
  const parts = value.split(/[\/.-]/);
  if (parts.length !== 3) return new Date().toISOString().slice(0, 10);
  const [day, month, year] = parts;
  const fullYear = year.length === 2 ? `20${year}` : year;
  return `${fullYear}-${month.padStart(2, '0')}-${day.padStart(2, '0')}`;
}
