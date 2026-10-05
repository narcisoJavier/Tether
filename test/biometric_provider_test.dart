import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tether/app_router.dart';
import 'package:tether/screens/lock_screen.dart';
import 'package:tether/services/biometric_provider.dart';
import 'package:tether/services/biometric_service.dart';
import 'package:tether/services/onboarding_service.dart';
import 'package:tether/utils/constants.dart';

class _Authentication extends BiometricService {
  bool supported = true;
  bool result = true;
  Object? error;
  int calls = 0;
  int cancellations = 0;
  Completer<bool>? pending;

  @override
  Future<bool> canAuthenticate() async => supported;

  @override
  Future<bool> authenticate({required String reason}) async {
    calls++;
    if (error != null) throw error!;
    return pending?.future ?? result;
  }

  @override
  Future<void> cancel() async {
    cancellations++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  late _Authentication authentication;
  late AppLockController lock;
  var elapsed = Duration.zero;
  var now = DateTime.utc(2026);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    authentication = _Authentication();
    elapsed = Duration.zero;
    now = DateTime.utc(2026);
    lock = AppLockController(
      prefs,
      authentication,
      elapsed: () => elapsed,
      now: () => now,
    );
  });

  tearDown(() => lock.dispose());

  Future<void> enabledLock() async {
    expect(await lock.setEnabled(true), isTrue);
    lock.lock();
  }

  test(
    'disabled until a supported device successfully authenticates',
    () async {
      expect(lock.status, AppLockStatus.disabled);
      authentication.supported = false;
      expect(await lock.setEnabled(true), isFalse);
      expect(lock.enabled, isFalse);
      expect(authentication.calls, 0);
      expect(prefs.getBool(AppConstants.biometricLockEnabledKey), isNull);
      authentication.supported = true;
      expect(await lock.setEnabled(true), isTrue);
      expect(lock.status, AppLockStatus.unlocked);
      expect(prefs.getBool(AppConstants.biometricLockEnabledKey), isTrue);
    },
  );

  test('canceling enrollment leaves app lock disabled', () async {
    authentication.result = false;
    expect(await lock.setEnabled(true), isFalse);
    expect(lock.enabled, isFalse);
    expect(lock.status, AppLockStatus.disabled);
  });

  test('missing enrollment never enables app lock', () async {
    authentication.error = const LocalAuthException(
      code: LocalAuthExceptionCode.noCredentialsSet,
    );
    expect(await lock.setEnabled(true), isFalse);
    expect(lock.enabled, isFalse);
    expect(lock.status, AppLockStatus.unavailable);
  });

  test('restart always begins locked', () async {
    await enabledLock();
    final restarted = AppLockController(prefs, authentication);
    addTearDown(restarted.dispose);
    expect(restarted.status, AppLockStatus.locked);
    expect(restarted.requiresAuthentication, isTrue);
  });

  test(
    'unlock transitions through authenticating and rejects double tap',
    () async {
      await enabledLock();
      authentication.pending = Completer<bool>();
      final unlock = lock.unlock();
      await Future<void>.delayed(Duration.zero);
      expect(lock.status, AppLockStatus.authenticating);
      expect(lock.requiresAuthentication, isTrue);
      expect(await lock.unlock(), isFalse);
      authentication.pending!.complete(true);
      expect(await unlock, isTrue);
      expect(lock.status, AppLockStatus.unlocked);
    },
  );

  for (final entry in {
    LocalAuthExceptionCode.userCanceled: AppLockStatus.locked,
    LocalAuthExceptionCode.systemCanceled: AppLockStatus.locked,
    LocalAuthExceptionCode.noCredentialsSet: AppLockStatus.unavailable,
    LocalAuthExceptionCode.noBiometricsEnrolled: AppLockStatus.unavailable,
    LocalAuthExceptionCode.noBiometricHardware: AppLockStatus.unavailable,
    LocalAuthExceptionCode.temporaryLockout: AppLockStatus.temporaryLockout,
    LocalAuthExceptionCode.biometricLockout: AppLockStatus.permanentLockout,
    LocalAuthExceptionCode.unknownError: AppLockStatus.unavailable,
  }.entries) {
    test('fails closed for ${entry.key.name}', () async {
      await enabledLock();
      authentication.error = LocalAuthException(code: entry.key);
      expect(await lock.unlock(), isFalse);
      expect(lock.status, entry.value);
      expect(lock.requiresAuthentication, isTrue);
      expect(lock.enabled, isTrue);
    });
  }

  test(
    'unexpected plugin failure stays locked and retry can recover',
    () async {
      await enabledLock();
      authentication.error = StateError('plugin unavailable');
      expect(await lock.unlock(), isFalse);
      expect(lock.requiresAuthentication, isTrue);
      authentication.error = null;
      expect(await lock.unlock(), isTrue);
    },
  );

  test('cannot disable from locked state without first unlocking', () async {
    await enabledLock();
    expect(await lock.setEnabled(false), isFalse);
    expect(lock.enabled, isTrue);
    expect(await lock.unlock(), isTrue);
    authentication.result = false;
    expect(await lock.setEnabled(false), isFalse);
    expect(lock.enabled, isTrue);
    expect(lock.requiresAuthentication, isTrue);
    authentication.result = true;
    await lock.unlock();
    expect(await lock.setEnabled(false), isTrue);
    expect(lock.status, AppLockStatus.disabled);
    expect(prefs.getBool(AppConstants.biometricLockEnabledKey), isFalse);
  });

  test(
    'inactive covers content without treating native prompt as background',
    () async {
      await lock.setEnabled(true);
      lock.didChangeAppLifecycleState(AppLifecycleState.inactive);
      expect(lock.obscured, isTrue);
      elapsed = const Duration(minutes: 2);
      lock.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(lock.requiresAuthentication, isFalse);
      expect(lock.obscured, isFalse);
    },
  );

  test('background below grace retains access; at boundary relocks', () async {
    await lock.setEnabled(true);
    lock.didChangeAppLifecycleState(AppLifecycleState.paused);
    elapsed = const Duration(seconds: 29);
    lock.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(lock.requiresAuthentication, isFalse);
    lock.didChangeAppLifecycleState(AppLifecycleState.hidden);
    elapsed += const Duration(seconds: 30);
    lock.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(lock.requiresAuthentication, isTrue);
  });

  test('repeated hidden and paused events cannot extend grace', () async {
    await lock.setEnabled(true);
    lock.didChangeAppLifecycleState(AppLifecycleState.hidden);
    elapsed = const Duration(seconds: 25);
    lock.didChangeAppLifecycleState(AppLifecycleState.paused);
    elapsed = const Duration(seconds: 30);
    lock.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(lock.requiresAuthentication, isTrue);
  });

  test('device sleep and backward clock changes cannot extend grace', () async {
    await lock.setEnabled(true);
    lock.didChangeAppLifecycleState(AppLifecycleState.paused);
    now = now.add(const Duration(minutes: 5));
    lock.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(lock.requiresAuthentication, isTrue);
    await lock.unlock();
    lock.didChangeAppLifecycleState(AppLifecycleState.paused);
    now = now.subtract(const Duration(minutes: 1));
    lock.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(lock.requiresAuthentication, isTrue);
  });

  test('late auth success after relock cannot grant access', () async {
    await enabledLock();
    authentication.pending = Completer<bool>();
    final unlock = lock.unlock();
    await Future<void>.delayed(Duration.zero);
    lock.didChangeAppLifecycleState(AppLifecycleState.paused);
    elapsed = const Duration(seconds: 30);
    lock.didChangeAppLifecycleState(AppLifecycleState.resumed);
    authentication.pending!.complete(true);
    expect(await unlock, isFalse);
    expect(lock.requiresAuthentication, isTrue);
    expect(authentication.cancellations, 1);
  });

  test('auth completion in background cannot grant access', () async {
    await enabledLock();
    authentication.pending = Completer<bool>();
    final unlock = lock.unlock();
    await Future<void>.delayed(Duration.zero);
    lock.didChangeAppLifecycleState(AppLifecycleState.paused);
    authentication.pending!.complete(true);
    expect(await unlock, isFalse);
    expect(lock.requiresAuthentication, isTrue);
  });

  group('lock routing', () {
    test(
      'cold deep link preserves query and fragment after authentication',
      () {
        final guard = AppLockRouteGuard();
        final destination = Uri.parse('/sftp/server?path=%2Fhome#files');
        final redirect = guard.redirect(uri: destination, locked: true)!;
        expect(Uri.parse(redirect).path, '/lock');
        expect(guard.redirect(uri: Uri.parse(redirect), locked: true), isNull);
        expect(
          guard.redirect(uri: Uri.parse(redirect), locked: false),
          destination.toString(),
        );
      },
    );

    test('onboarding deep link cannot bypass enabled lock', () {
      final guard = AppLockRouteGuard();
      expect(
        guard.redirect(uri: Uri.parse('/onboarding'), locked: true),
        startsWith('/lock?'),
      );
    });

    test('relock preserves terminal route and defers navigation', () {
      final guard = AppLockRouteGuard();
      final terminal = Uri.parse('/terminal');
      expect(guard.redirect(uri: terminal, locked: false), isNull);
      expect(guard.redirect(uri: terminal, locked: true), isNull);
      expect(
        guard.redirect(uri: Uri.parse('/keys'), locked: true),
        '/terminal',
      );
      expect(guard.redirect(uri: terminal, locked: false), '/keys');
      expect(guard.redirect(uri: Uri.parse('/keys'), locked: false), isNull);
    });

    for (final destination in [
      'https://evil.test',
      '//evil.test',
      '/lock',
      'keys',
    ]) {
      test('rejects unsafe return destination $destination', () {
        final guard = AppLockRouteGuard();
        expect(
          guard.redirect(
            uri: Uri(path: '/lock', queryParameters: {'from': destination}),
            locked: false,
          ),
          '/',
        );
      });
    }
  });

  testWidgets('gate hides protected semantics and retains its mounted state', (
    tester,
  ) async {
    await enabledLock();
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          appLockProvider.overrideWith((ref) => lock),
        ],
        child: const MaterialApp(
          home: AppLockGate(child: Text('Private terminal output')),
        ),
      ),
    );
    expect(find.text('Private terminal output'), findsNothing);
    expect(
      find.text('Private terminal output', skipOffstage: false),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Private terminal output'), findsNothing);
    expect(find.bySemanticsLabel('Unlock Tether'), findsOneWidget);
    await lock.unlock();
    await tester.pump();
    expect(find.text('Private terminal output'), findsOneWidget);
    lock.lock();
    await tester.pump();
    expect(find.bySemanticsLabel('Private terminal output'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    semantics.dispose();
    // ProviderScope owns disposal for its override.
    lock = AppLockController(prefs, authentication);
  });

  testWidgets(
    'unavailable lock has retry and recovery with large text and reduced motion',
    (tester) async {
      await enabledLock();
      authentication.supported = false;
      await lock.unlock();
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appLockProvider.overrideWith((ref) => lock)],
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(2.0),
                disableAnimations: true,
              ),
              child: child!,
            ),
            home: const LockScreen(),
          ),
        ),
      );
      expect(find.text('Open Tether'), findsNothing);
      expect(find.text('Authentication unavailable'), findsOneWidget);
      expect(find.text('Retry authentication'), findsOneWidget);
      expect(find.text('Device settings and recovery'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      lock = AppLockController(prefs, authentication);
    },
  );
}
