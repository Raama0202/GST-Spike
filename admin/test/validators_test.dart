import 'package:flutter_test/flutter_test.dart';
import 'package:gst_expense_admin/core/validators.dart';

void main() {
  group('normalizeMobile', () {
    test('keeps plain 10-digit numbers', () {
      expect(normalizeMobile('9876543210'), '9876543210');
    });

    test('strips formatting and country / trunk prefixes', () {
      expect(normalizeMobile('+91 98765 43210'), '9876543210');
      expect(normalizeMobile('+91-98765-43210'), '9876543210');
      expect(normalizeMobile('0091 9876543210'), '9876543210');
      expect(normalizeMobile('919876543210'), '9876543210');
      expect(normalizeMobile('09876543210'), '9876543210');
      expect(normalizeMobile('(987) 654.3210'), '9876543210');
    });

    test('leaves short numbers starting with 91 alone', () {
      expect(normalizeMobile('9198765432'), '9198765432');
    });
  });

  group('mobileError', () {
    test('requires a value', () {
      expect(mobileError(null), 'Mobile number is required');
      expect(mobileError('  '), 'Mobile number is required');
    });

    test('accepts formatted Indian mobiles', () {
      expect(mobileError('+91 98765 43210'), isNull);
      expect(mobileError('6000000000'), isNull);
    });

    test('rejects landline-like, short and long numbers', () {
      expect(mobileError('5876543210'), isNotNull);
      expect(mobileError('98765'), isNotNull);
      expect(mobileError('98765432101'), isNotNull);
      expect(mobileError('98765abcde'), isNotNull);
    });
  });

  group('GSTIN', () {
    test('accepts valid GSTINs regardless of case and spacing', () {
      expect(isValidGstin('36AABCU9603R1ZM'), isTrue);
      expect(isValidGstin(' 36aabcu9603r1zm '), isTrue);
      expect(gstinError('36 AABCU 9603R1ZM'), isNull);
    });

    test('is optional', () {
      expect(gstinError(null), isNull);
      expect(gstinError(''), isNull);
    });

    test('rejects malformed GSTINs', () {
      expect(gstinError('36AABCU9603R1Z'), isNotNull);
      expect(gstinError('36AABCU9603R1XM'), isNotNull);
      expect(gstinError('XXAABCU9603R1ZM'), isNotNull);
    });

    test('normalizeGstin uppercases and removes whitespace', () {
      expect(normalizeGstin(' 36aabcu 9603r1zm\n'), '36AABCU9603R1ZM');
    });
  });

  test('isValidEmail', () {
    expect(isValidEmail('owner@acme.in'), isTrue);
    expect(isValidEmail(' owner@acme.in '), isTrue);
    expect(isValidEmail('owner@acme'), isFalse);
    expect(isValidEmail('owner acme.in'), isFalse);
  });

  test('newPasswordError enforces the minimum length', () {
    expect(newPasswordError('short'), isNotNull);
    expect(newPasswordError('long enough!'), isNull);
  });

  test('initialOf handles empty names', () {
    expect(initialOf('acme'), 'A');
    expect(initialOf('  zed'), 'Z');
    expect(initialOf(''), 'A');
    expect(initialOf(null, fallback: '?'), '?');
  });
}
