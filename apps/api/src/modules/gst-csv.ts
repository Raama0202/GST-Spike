export type GstrFormType = '2A' | '2B';
export type GstrMatchStatus = 'unchecked' | 'matched' | 'amount_mismatch' | 'not_in_portal' | 'portal_only';

export type ParsedGstRow = {
  invoiceNumber: string;
  invoiceAmount: number;
  gstin?: string;
  vendorName?: string;
  invoiceDate?: string;
  taxableAmount?: number;
};

/** Parse GSTR-2A / 2B style CSV (header optional). */
export function parseGstCsv(raw: string): ParsedGstRow[] {
  const lines = raw
    .replace(/^\uFEFF/, '')
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean);
  if (!lines.length) return [];

  const firstCells = splitCsvLine(lines[0]).map((c) => c.trim());
  const hasHeader = firstCells.some((cell) => /invoice|gstin|taxable|value|amount|date|trade|supplier/i.test(cell));
  const header = hasHeader ? firstCells.map((c) => c.toLowerCase()) : null;
  const dataLines = hasHeader ? lines.slice(1) : lines;

  const rows: ParsedGstRow[] = [];
  for (const line of dataLines) {
    const cells = splitCsvLine(line).map((c) => c.trim().replace(/^"|"$/g, ''));
    if (!cells.length) continue;
    const row = header ? mapByHeader(header, cells) : mapByPosition(cells);
    if (!row?.invoiceNumber || !Number.isFinite(row.invoiceAmount)) continue;
    rows.push(row);
  }
  return rows;
}

function mapByHeader(header: string[], cells: string[]): ParsedGstRow | null {
  const get = (...aliases: string[]) => {
    const idx = header.findIndex((h) => aliases.some((a) => h.includes(a)));
    return idx >= 0 ? cells[idx] : undefined;
  };
  const invoiceNumber = get('invoice number', 'invoice no', 'inv no', 'inum', 'document number', 'doc no') ?? cells[0];
  const amountRaw = get('invoice value', 'invoice amount', 'taxable value', 'total', 'value', 'inv_value', 'invoicevalue') ?? cells[1];
  const invoiceAmount = parseAmount(amountRaw ?? '');
  if (!invoiceNumber || invoiceAmount == null) return null;
  const gstin = get('gstin', 'supplier gstin', 'ctin');
  const vendorName = get('trade name', 'legal name', 'supplier', 'vendor', 'party');
  const invoiceDate = normalizeDate(get('invoice date', 'date', 'idt') ?? '');
  const taxableRaw = get('taxable value', 'taxable', 'txval');
  const taxableAmount = taxableRaw ? parseAmount(taxableRaw) : undefined;
  return {
    invoiceNumber: invoiceNumber.trim(),
    invoiceAmount,
    gstin: gstin?.toUpperCase(),
    vendorName: vendorName?.trim(),
    invoiceDate: invoiceDate || undefined,
    taxableAmount: taxableAmount ?? undefined,
  };
}

function mapByPosition(cells: string[]): ParsedGstRow | null {
  // Formats:
  // invoiceNumber,invoiceAmount
  // gstin,invoiceNumber,invoiceDate,invoiceAmount
  // gstin,vendor,invoiceNumber,invoiceDate,invoiceAmount
  if (cells.length === 2) {
    const invoiceAmount = parseAmount(cells[1]);
    if (invoiceAmount == null) return null;
    return { invoiceNumber: cells[0], invoiceAmount };
  }
  if (cells.length >= 4 && looksLikeGstin(cells[0])) {
    const invoiceAmount = parseAmount(cells[cells.length - 1]);
    if (invoiceAmount == null) return null;
    if (cells.length === 4) {
      return { gstin: cells[0].toUpperCase(), invoiceNumber: cells[1], invoiceDate: normalizeDate(cells[2]) || undefined, invoiceAmount };
    }
    return {
      gstin: cells[0].toUpperCase(),
      vendorName: cells[1],
      invoiceNumber: cells[2],
      invoiceDate: normalizeDate(cells[3]) || undefined,
      invoiceAmount,
    };
  }
  const invoiceAmount = parseAmount(cells[1]);
  if (invoiceAmount == null) return null;
  return { invoiceNumber: cells[0], invoiceAmount };
}

function looksLikeGstin(value: string) {
  return /^[0-9]{2}[A-Z0-9]{10}[0-9A-Z]{3}$/i.test(value.trim());
}

function parseAmount(value: string) {
  const cleaned = value.replace(/[₹,\s]/g, '').replace(/rs\.?/i, '');
  if (!cleaned) return null;
  const n = Number(cleaned);
  return Number.isFinite(n) ? n : null;
}

function normalizeDate(value: string) {
  if (!value) return '';
  if (/^\d{4}-\d{2}-\d{2}$/.test(value)) return value;
  const parts = value.split(/[\/.-]/);
  if (parts.length !== 3) return value;
  const [a, b, c] = parts;
  if (c.length === 4) return `${c}-${b.padStart(2, '0')}-${a.padStart(2, '0')}`;
  return value;
}

function splitCsvLine(line: string) {
  const out: string[] = [];
  let cur = '';
  let inQuotes = false;
  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (ch === '"') {
      inQuotes = !inQuotes;
      continue;
    }
    if (ch === ',' && !inQuotes) {
      out.push(cur);
      cur = '';
      continue;
    }
    cur += ch;
  }
  out.push(cur);
  return out;
}

export function normalizeInvoiceNo(value: string) {
  return value.replace(/\s+/g, '').toUpperCase();
}
