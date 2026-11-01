import 'constants.dart';

final _gstinPattern = RegExp(r'^[0-9]{2}[A-Z0-9]{10}[0-9A-Z]Z[0-9A-Z]$');
final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
final _indianMobile = RegExp(r'^[6-9][0-9]{9}$');

String normalizeGstin(String value) =>
    value.replaceAll(RegExp(r'\s'), '').toUpperCase();

bool isValidGstin(String value) =>
    _gstinPattern.hasMatch(normalizeGstin(value));

/// Null for an empty value: GSTINs are optional everywhere they're entered.
String? gstinError(String? value) {
  final gstin = normalizeGstin(value ?? '');
  if (gstin.isEmpty || _gstinPattern.hasMatch(gstin)) return null;
  return 'Not a valid GSTIN (15 characters, e.g. 36AABCU9603R1ZM)';
}

bool isValidEmail(String value) => _emailPattern.hasMatch(value.trim());

/// Strips formatting and the +91 / 91 / 0 trunk prefixes so Indian mobiles
/// are sent as the 10 digits employees type at login.
String normalizeMobile(String input) {
  var digits = input.replaceAll(RegExp(r'[\s\-().]'), '');
  if (digits.startsWith('+91')) {
    digits = digits.substring(3);
  } else if (digits.startsWith('0091')) {
    digits = digits.substring(4);
  } else if (digits.length == 12 && digits.startsWith('91')) {
    digits = digits.substring(2);
  } else if (digits.length == 11 && digits.startsWith('0')) {
    digits = digits.substring(1);
  }
  return digits;
}

String? mobileError(String? value) {
  final mobile = normalizeMobile(value ?? '');
  if (mobile.isEmpty) return 'Mobile number is required';
  if (!_indianMobile.hasMatch(mobile)) {
    return 'Enter a 10-digit Indian mobile number';
  }
  return null;
}

String? newPasswordError(String? value) =>
    (value ?? '').length < AppConstants.minPasswordLength
    ? 'Use at least ${AppConstants.minPasswordLength} characters'
    : null;

/// First letter for avatars; safe for empty or whitespace-only names.
String initialOf(String? value, {String fallback = 'A'}) {
  final text = value?.trim() ?? '';
  return text.isEmpty
      ? fallback
      : String.fromCharCode(text.runes.first).toUpperCase();
}
