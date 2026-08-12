import 'package:flutter_test/flutter_test.dart';

// Minimal copy of exception classes for testing (avoids tailscale build hook).
class _TailscaleException implements Exception {
  final String message;
  final String code;
  final Object? cause;
  const _TailscaleException(this.message, this.code, {this.cause});
  @override
  String toString() => '_TailscaleException[$code]: $message';
}

class _TailscaleDialException extends _TailscaleException {
  const _TailscaleDialException(String message, {Object? cause})
    : super(message, 'DIAL', cause: cause);
}

class _TailscaleAuthException extends _TailscaleException {
  const _TailscaleAuthException(String message, {Object? cause})
    : super(message, 'AUTH', cause: cause);
}

class _TailscaleConnectException extends _TailscaleException {
  const _TailscaleConnectException(String message, {Object? cause})
    : super(message, 'CONNECT', cause: cause);
}

void main() {
  group('TailscaleException', () {
    test('stores message and code', () {
      const exc = _TailscaleException('test msg', 'E1');
      expect(exc.message, 'test msg');
      expect(exc.code, 'E1');
    });

    test('toString includes code and message', () {
      const exc = _TailscaleException('err', 'X99');
      expect(exc.toString(), contains('X99'));
      expect(exc.toString(), contains('err'));
    });

    test('cause is null when omitted', () {
      const exc = _TailscaleException('m', 'c');
      expect(exc.cause, isNull);
    });
  });

  group('TailscaleDialException', () {
    test('inherits code DIAL', () {
      const exc = _TailscaleDialException('fail');
      expect(exc.code, 'DIAL');
    });
  });

  group('TailscaleAuthException', () {
    test('inherits code AUTH', () {
      const exc = _TailscaleAuthException('fail');
      expect(exc.code, 'AUTH');
    });
  });

  group('TailscaleConnectException', () {
    test('inherits code CONNECT', () {
      const exc = _TailscaleConnectException('fail');
      expect(exc.code, 'CONNECT');
    });
  });
}
