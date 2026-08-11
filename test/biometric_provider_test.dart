import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tether/services/biometric_provider.dart';
import 'package:tether/utils/constants.dart';

void main() {
  group('BiometricLockNotifier', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    test('starts disabled when no stored value', () {
      final notifier = BiometricLockNotifier(prefs);
      expect(notifier.state, false);
    });

    test('starts enabled when stored value is true', () async {
      SharedPreferences.setMockInitialValues({
        AppConstants.biometricLockEnabledKey: true,
      });
      prefs = await SharedPreferences.getInstance();
      final notifier = BiometricLockNotifier(prefs);
      expect(notifier.state, true);
    });

    test('toggle switches state', () async {
      final notifier = BiometricLockNotifier(prefs);
      expect(notifier.state, false);

      await notifier.toggle();
      expect(notifier.state, true);

      await notifier.toggle();
      expect(notifier.state, false);
    });

    test('toggle persists to SharedPreferences', () async {
      final notifier = BiometricLockNotifier(prefs);
      await notifier.toggle();

      final stored = prefs.getBool(AppConstants.biometricLockEnabledKey);
      expect(stored, true);
    });

    test('enable() sets state to true', () async {
      final notifier = BiometricLockNotifier(prefs);
      await notifier.enable();
      expect(notifier.state, true);
    });

    test('disable() sets state to false', () async {
      final notifier = BiometricLockNotifier(prefs);
      await notifier.enable();
      expect(notifier.state, true);

      await notifier.disable();
      expect(notifier.state, false);
    });

    test('enable() is idempotent', () async {
      final notifier = BiometricLockNotifier(prefs);
      await notifier.enable();
      await notifier.enable();
      expect(notifier.state, true);
    });

    test('disable() is idempotent', () async {
      final notifier = BiometricLockNotifier(prefs);
      await notifier.disable();
      expect(notifier.state, false);
    });
  });

  group('authSessionProvider', () {
    test('starts as false', () {
      final container = ProviderContainer();
      final session = container.read(authSessionProvider);
      expect(session, false);
      container.dispose();
    });

    test('can be set to true', () {
      final container = ProviderContainer();
      container.read(authSessionProvider.notifier).state = true;
      expect(container.read(authSessionProvider), true);
      container.dispose();
    });

    test('can be reset to false after being true', () {
      final container = ProviderContainer();
      container.read(authSessionProvider.notifier).state = true;
      container.read(authSessionProvider.notifier).state = false;
      expect(container.read(authSessionProvider), false);
      container.dispose();
    });
  });
}

