import 'package:flutter_test/flutter_test.dart';
import 'package:gst_expense_scanner/core/config/server_config.dart';

void main() {
  group('ServerConfig.normalize', () {
    test('bare host becomes an https API root', () {
      expect(
        ServerConfig.normalize('demo.trycloudflare.com'),
        'https://demo.trycloudflare.com/v1',
      );
    });

    test('keeps an explicit path', () {
      expect(
        ServerConfig.normalize('https://demo.trycloudflare.com/v1'),
        'https://demo.trycloudflare.com/v1',
      );
    });

    test('keeps host and port for LAN servers', () {
      expect(
        ServerConfig.normalize('http://192.168.29.21:8000/v1'),
        'http://192.168.29.21:8000/v1',
      );
    });

    test('trims surrounding whitespace and trailing slashes', () {
      expect(
        ServerConfig.normalize('  https://api.example.com/v1//  '),
        'https://api.example.com/v1',
      );
    });

    test('rejects empty, malformed, and non-http schemes', () {
      expect(ServerConfig.normalize(''), isNull);
      expect(ServerConfig.normalize('   '), isNull);
      expect(ServerConfig.normalize('ftp://api.example.com'), isNull);
      expect(ServerConfig.normalize('http://'), isNull);
    });
  });
}
