/// Indian mobile number helpers shared by login and profile.
///
/// Employees paste numbers in every format (`+91 98765-43210`, `0987…`,
/// `919876543210`); the API matches on the canonical 10 digits.
abstract final class IndianMobile {
  static final _valid = RegExp(r'^[6-9]\d{9}$');

  /// Strips formatting and the `+91` / `91` / `0` / `0091` prefixes.
  static String _localDigits(String input) {
    var digits = input.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 14 && digits.startsWith('0091')) {
      digits = digits.substring(4);
    } else if (digits.length == 12 && digits.startsWith('91')) {
      digits = digits.substring(2);
    } else if (digits.length == 11 && digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    return digits;
  }

  /// Canonical 10-digit number, or null when [input] cannot be one.
  static String? normalize(String input) {
    final digits = _localDigits(input);
    return _valid.hasMatch(digits) ? digits : null;
  }

  /// Form-field validator; null when valid.
  static String? validate(String? input) {
    final digits = _localDigits(input ?? '');
    if (digits.length != 10) {
      return 'Enter a valid 10-digit Indian mobile number';
    }
    if (!_valid.hasMatch(digits)) {
      return 'Mobile number must start with 6, 7, 8, or 9';
    }
    return null;
  }

  /// `+91 98765 43210`; values that are not Indian mobiles are shown as stored.
  static String format(String stored) {
    final number = normalize(stored);
    if (number == null) return stored.trim();
    return '+91 ${number.substring(0, 5)} ${number.substring(5)}';
  }
}
