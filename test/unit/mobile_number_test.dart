import 'package:flutter_test/flutter_test.dart';
import 'package:gst_expense_scanner/core/utils/mobile_number.dart';

void main() {
  group('IndianMobile.normalize', () {
    test('accepts the formats employees paste', () {
      for (final input in [
        '9876543210',
        '+91 98765 43210',
        '+91-98765-43210',
        '919876543210',
        '09876543210',
        '0091 98765 43210',
        '(+91) 98765 43210',
      ]) {
        expect(IndianMobile.normalize(input), '9876543210', reason: input);
      }
    });

    test('rejects numbers that cannot be Indian mobiles', () {
      for (final input in [
        '',
        '12345',
        '5876543210',
        '98765432101',
        '+1 415 555 0100',
        '919876',
      ]) {
        expect(IndianMobile.normalize(input), isNull, reason: input);
      }
    });
  });

  group('IndianMobile.validate', () {
    test('explains what is wrong', () {
      expect(
        IndianMobile.validate(''),
        'Enter a valid 10-digit Indian mobile number',
      );
      expect(
        IndianMobile.validate('5876543210'),
        'Mobile number must start with 6, 7, 8, or 9',
      );
      expect(IndianMobile.validate('+91 98765 43210'), isNull);
    });
  });

  group('IndianMobile.format', () {
    test('shows the country code exactly once', () {
      expect(IndianMobile.format('9876543210'), '+91 98765 43210');
      expect(IndianMobile.format('+919876543210'), '+91 98765 43210');
      expect(IndianMobile.format('+91 98765 43210'), '+91 98765 43210');
    });

    test('leaves non-Indian values as stored', () {
      expect(IndianMobile.format(' +1 415 555 0100 '), '+1 415 555 0100');
    });
  });
}
