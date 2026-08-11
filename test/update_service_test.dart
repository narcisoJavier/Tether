import 'package:flutter_test/flutter_test.dart';
import 'package:tether/services/update_service.dart';

void main() {
  group('UpdateService.parseVersion', () {
    test('parses standard semver strings correctly', () {
      final v = UpdateService.parseVersion('0.4.0');
      expect(v, isNotNull);
      expect(v.toString(), equals('0.4.0'));
    });

    test('strips leading v prefix', () {
      final v = UpdateService.parseVersion('v0.4.0');
      expect(v, isNotNull);
      expect(v.toString(), equals('0.4.0'));
    });

    test('normalizes 2-part tag names like v0.4 into 0.4.0', () {
      final v = UpdateService.parseVersion('v0.4');
      expect(v, isNotNull);
      expect(v.toString(), equals('0.4.0'));
    });

    test('normalizes 1-part tag names like v1 into 1.0.0', () {
      final v = UpdateService.parseVersion('v1');
      expect(v, isNotNull);
      expect(v.toString(), equals('1.0.0'));
    });

    test('handles versions with build numbers e.g. 0.4.0+2', () {
      final v = UpdateService.parseVersion('0.4.0+2');
      expect(v, isNotNull);
      expect(v.toString(), equals('0.4.0+2'));
    });

    test('handles versions with pre-release tags e.g. v0.5.0-beta1', () {
      final v = UpdateService.parseVersion('v0.5.0-beta1');
      expect(v, isNotNull);
      expect(v.toString(), equals('0.5.0-beta1'));
    });

    test('returns null for empty or invalid version strings', () {
      expect(UpdateService.parseVersion(''), isNull);
      expect(UpdateService.parseVersion('  '), isNull);
      expect(UpdateService.parseVersion('invalid-version'), isNull);
    });
  });

  group('UpdateService.isNewer', () {
    test('returns true when remote tag v0.5 is compared against 0.4.0', () {
      expect(UpdateService.isNewer('v0.5', '0.4.0'), isTrue);
    });

    test('returns true when remote v0.4.1 is compared against 0.4.0', () {
      expect(UpdateService.isNewer('v0.4.1', '0.4.0'), isTrue);
    });

    test('returns true when build number is incremented (0.4.0+3 vs 0.4.0+2)', () {
      expect(UpdateService.isNewer('0.4.0+3', '0.4.0+2'), isTrue);
    });

    test('returns false when versions are identical', () {
      expect(UpdateService.isNewer('v0.4.0', '0.4.0'), isFalse);
      expect(UpdateService.isNewer('v0.4', '0.4.0'), isFalse);
    });

    test('returns false when remote is older', () {
      expect(UpdateService.isNewer('v0.3.9', '0.4.0'), isFalse);
    });

    test('returns false if parsing fails', () {
      expect(UpdateService.isNewer('invalid', '0.4.0'), isFalse);
      expect(UpdateService.isNewer('v0.5', 'invalid'), isFalse);
    });
  });
}
