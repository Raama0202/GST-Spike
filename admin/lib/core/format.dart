import 'package:intl/intl.dart';

final _inr = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
final _inrWhole = NumberFormat.currency(
  locale: 'en_IN',
  symbol: '₹',
  decimalDigits: 0,
);

num? asNum(dynamic value) =>
    value is num ? value : num.tryParse(value?.toString() ?? '');

String formatInr(dynamic value, {bool whole = false}) {
  final amount = asNum(value);
  if (amount == null) return '—';
  return (whole ? _inrWhole : _inr).format(amount);
}

String formatDate(dynamic value) {
  final parsed = DateTime.tryParse(value?.toString() ?? '');
  return parsed == null
      ? '—'
      : DateFormat('dd MMM yyyy').format(parsed.toLocal());
}

String formatDateTime(dynamic value) {
  final parsed = DateTime.tryParse(value?.toString() ?? '');
  return parsed == null
      ? '—'
      : DateFormat('dd MMM yyyy, h:mm a').format(parsed.toLocal());
}

String isoDate(DateTime value) => DateFormat('yyyy-MM-dd').format(value);

/// "camelCase", "snake_case" and "dotted.keys" as "Title Case" labels.
const _fieldLabels = {
  'netAmount': 'Invoice value',
  'net_amount': 'Invoice value',
  'totalAmount': 'Invoice value',
  'gstin': 'GSTIN',
  'cgst': 'CGST',
  'sgst': 'SGST',
  'igst': 'IGST',
};

String fieldLabel(String key) => _fieldLabels[key] ?? key
    .replaceAll(RegExp(r'[_.]'), ' ')
    .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}')
    .split(' ')
    .map((p) => p.isEmpty ? p : p[0].toUpperCase() + p.substring(1))
    .join(' ');

/// Filename from a `Content-Disposition` header, if it names one.
String? dispositionFilename(String? header) {
  if (header == null) return null;
  final match = RegExp(
    r'''filename\*?=(?:UTF-8'')?"?([^";]+)"?''',
    caseSensitive: false,
  ).firstMatch(header);
  final name = match?.group(1)?.trim();
  if (name == null || name.isEmpty) return null;
  try {
    return Uri.decodeComponent(name);
  } on ArgumentError {
    return name;
  }
}
