import 'package:flutter_test/flutter_test.dart';
import 'package:x9_core/x9_core.dart';

String? n(String s) => ServerSettings.normalize(s).value;

void main() {
  group('ServerSettings.normalize', () {
    test('host only gets https and /api/v1', () {
      expect(n('api.example.com'), 'https://api.example.com/api/v1');
      expect(n('  api.example.com  '), 'https://api.example.com/api/v1');
      expect(n('https://api.example.com'), 'https://api.example.com/api/v1');
    });

    test('trailing slashes are removed and the host is lower-cased', () {
      expect(n('https://API.Example.com/'), 'https://api.example.com/api/v1');
      expect(n('https://api.example.com/api/v1/'), 'https://api.example.com/api/v1');
      expect(n('https://api.example.com/api/v1//'), 'https://api.example.com/api/v1');
    });

    test('/api becomes /api/v1', () {
      expect(n('https://api.example.com/api'), 'https://api.example.com/api/v1');
    });

    test('a prefix path is kept', () {
      expect(n('https://example.com/x9/api/v1'), 'https://example.com/x9/api/v1');
    });

    test('ports are kept, default ports dropped', () {
      expect(n('https://api.example.com:8443'), 'https://api.example.com:8443/api/v1');
      expect(n('https://api.example.com:443/api/v1'), 'https://api.example.com/api/v1');
    });

    test('IPv4 over https is accepted', () {
      expect(n('https://203.0.113.10'), 'https://203.0.113.10/api/v1');
      expect(n('203.0.113.10/api/v1'), 'https://203.0.113.10/api/v1');
    });

    test('http only for localhost / 10.x / 192.168.x (and 127.x)', () {
      expect(n('http://localhost:8000'), 'http://localhost:8000/api/v1');
      expect(n('http://10.0.2.2:8000/api/v1'), 'http://10.0.2.2:8000/api/v1');
      expect(n('http://192.168.1.20'), 'http://192.168.1.20/api/v1');
      expect(n('http://127.0.0.1:8000'), 'http://127.0.0.1:8000/api/v1');
      expect(n('http://api.example.com'), isNull);
      expect(n('http://203.0.113.10'), 'http://203.0.113.10/api/v1');
      expect(n('http://187.127.157.39'), 'http://187.127.157.39/api/v1');
      expect(n('http://187.127.157.39:8080/api'), 'http://187.127.157.39:8080/api/v1');
      expect(n('http://10.0.0.999'), isNull);
    });

    test('rejects empty, spaces, other schemes, wrong path, query, credentials', () {
      expect(n(''), isNull);
      expect(n('   '), isNull);
      expect(n('api example.com'), isNull);
      expect(n('ftp://api.example.com'), isNull);
      expect(n('https://api.example.com/v2'), isNull);
      expect(n('https://api.example.com/api/v2'), isNull);
      expect(n('https://api.example.com/api/v1?x=1'), isNull);
      expect(n('https://api.example.com/api/v1#top'), isNull);
      expect(n('https://user:pw@api.example.com'), isNull);
      expect(n('https://'), isNull);
    });

    test('every rejection has a message, every success none', () {
      expect(ServerSettings.validate(''), isNotNull);
      expect(ServerSettings.validate('http://api.example.com'), contains('https'));
      expect(ServerSettings.validate('api.example.com'), isNull);
    });
  });

  group('ServerSettings.cleanDefault (compiled-in API_BASE)', () {
    test('empty define falls back to the default', () {
      expect(ServerSettings.cleanDefault(''), X9Config.fallbackApiBase);
      expect(ServerSettings.cleanDefault('   '), X9Config.fallbackApiBase);
    });

    test('is lenient and tidy', () {
      expect(ServerSettings.cleanDefault('https://203.0.113.10/api/v1/'), 'https://203.0.113.10/api/v1');
      expect(ServerSettings.cleanDefault('https://api.example.com'), 'https://api.example.com/api/v1');
    });

    test('never returns an empty or unparsable address', () {
      for (final raw in ['', ' ', 'not a url', 'http://', '://']) {
        final v = ServerSettings.cleanDefault(raw);
        expect(v, isNotEmpty);
        expect(Uri.tryParse(v)?.host, isNotEmpty, reason: raw);
      }
    });
  });

  group('ServerSettings TLS trust', () {
    test('isIpv4', () {
      expect(ServerSettings.isIpv4('203.0.113.10'), isTrue);
      expect(ServerSettings.isIpv4('256.1.1.1'), isFalse);
      expect(ServerSettings.isIpv4('api.example.com'), isFalse);
      expect(ServerSettings.isIpv4('1.2.3'), isFalse);
    });

    test('only the configured host is ever trusted', () {
      const base = 'https://203.0.113.10/api/v1';
      expect(ServerSettings.trustsCertificate('203.0.113.10', serverBase: base), isTrue);
      expect(ServerSettings.trustsCertificate('evil.example.com', serverBase: base), isFalse);
      expect(ServerSettings.trustsCertificate('203.0.113.11', serverBase: base), isFalse);
      expect(ServerSettings.trustsCertificate('anything', serverBase: ''), isFalse);
    });

    test('effective address is the compiled-in default when nothing is saved', () {
      expect(ServerSettings.override, isNull);
      expect(ServerSettings.effectiveApiBase, X9Config.defaultApiBase);
      expect(X9Config.effectiveApiBase, X9Config.defaultApiBase);
      expect(X9Config.apiUri.host, isNotEmpty);
    });
  });
}
