import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/constants.dart';
import 'biometric_service.dart';
import 'onboarding_service.dart';

/// Explicit outcomes of the device-authentication gate.
enum AppLockStatus {
  disabled,
  locked,
  authenticating,
  unlocked,
  unavailable,
  temporaryLockout,
  permanentLockout,
}

/// Injectable access to the existing local_auth integration.
final biometricServiceProvider = Provider<BiometricService>(
  (ref) => BiometricService(),
);

/// Owns authentication and lifecycle state for the application lifetime.
final appLockProvider = ChangeNotifierProvider<AppLockController>((ref) {
  final controller = AppLockController(
    ref.watch(sharedPrefsProvider),
    ref.watch(biometricServiceProvider),
  );
  WidgetsBinding.instance.addObserver(controller);
  ref.onDispose(() => WidgetsBinding.instance.removeObserver(controller));
  return controller;
});

/// Read-only view of the persisted lock preference.
final biometricLockEnabledProvider = Provider<bool>(
  (ref) => ref.watch(appLockProvider).enabled,
);

/// App access gate; it does not encrypt data or bind stored keys to biometrics.
class AppLockController extends ChangeNotifier with WidgetsBindingObserver {
  final SharedPreferences _prefs;
  final BiometricService _authentication;
  final Duration Function() _elapsed;
  final DateTime Function() _now;
  late bool _enabled;
  late AppLockStatus _status;
  String? _message;
  Duration? _backgroundedAt;
  DateTime? _backgroundWallTime;
  Timer? _backgroundTimer;
  int _attempt = 0;
  bool _disposed = false;
  bool _inBackground = false;
  bool _obscured = false;

  /// Process restarts always require authentication when the lock is enabled.
  AppLockController(
    this._prefs,
    this._authentication, {
    Duration Function()? elapsed,
    DateTime Function()? now,
  }) : _elapsed = elapsed ?? (Stopwatch()..start()).elapsedGetter,
       _now = now ?? DateTime.now {
    _enabled = _prefs.getBool(AppConstants.biometricLockEnabledKey) ?? false;
    _status = _enabled ? AppLockStatus.locked : AppLockStatus.disabled;
  }

  /// Content hides immediately; authentication expires after 30 seconds away.
  static const backgroundGrace = Duration(seconds: 30);

  bool get enabled => _enabled;
  AppLockStatus get status => _status;
  String? get message => _message;
  bool get busy => _status == AppLockStatus.authenticating;
  bool get requiresAuthentication =>
      _enabled && _status != AppLockStatus.unlocked;
  bool get obscured => _enabled && _obscured;

  void _setStatus(AppLockStatus status, [String? message]) {
    if (_disposed) return;
    _status = status;
    _message = message;
    notifyListeners();
  }

  bool _isCurrent(int attempt) => !_disposed && attempt == _attempt;

  /// Unlocks only after capability checking and a successful native challenge.
  Future<bool> unlock() async {
    if (!_enabled || busy) return false;
    return _authenticate('Authenticate to unlock Tether');
  }

  /// Enrollment and disabling both require a successful device challenge.
  Future<bool> setEnabled(bool enabled) async {
    if (busy || (_enabled && requiresAuthentication)) return false;
    if (enabled == _enabled) return true;
    final attempt = _attempt + 1;
    if (!await _authenticate(
      enabled
          ? 'Authenticate to enable Tether app lock'
          : 'Authenticate to turn off Tether app lock',
      finishUnlocked: false,
    )) {
      return false;
    }
    if (!_isCurrent(attempt) || _inBackground) return false;
    try {
      final saved = await _prefs.setBool(
        AppConstants.biometricLockEnabledKey,
        enabled,
      );
      if (!saved) throw StateError('Lock preference was not saved');
      if (_disposed) return false;
      _enabled = enabled;
      if (!_isCurrent(attempt) || _inBackground) {
        _setStatus(enabled ? AppLockStatus.locked : AppLockStatus.disabled);
        return false;
      }
      _setStatus(enabled ? AppLockStatus.unlocked : AppLockStatus.disabled);
      return true;
    } catch (_) {
      if (!_isCurrent(attempt)) return false;
      _setStatus(
        _enabled ? AppLockStatus.locked : AppLockStatus.disabled,
        'Could not save the app lock setting. Please try again.',
      );
      return false;
    }
  }

  Future<bool> _authenticate(
    String reason, {
    bool finishUnlocked = true,
  }) async {
    final attempt = ++_attempt;
    _setStatus(AppLockStatus.authenticating);
    try {
      final supported = await _authentication.canAuthenticate();
      if (!_isCurrent(attempt)) return false;
      if (!supported) {
        _setStatus(
          AppLockStatus.unavailable,
          'Device authentication is unavailable. Check your Android screen '
          'lock settings, then retry.',
        );
        return false;
      }
      final authenticated = await _authentication.authenticate(reason: reason);
      if (!_isCurrent(attempt)) return false;
      if (!authenticated || _inBackground) {
        _setStatus(
          _enabled ? AppLockStatus.locked : AppLockStatus.disabled,
          'Authentication was canceled or interrupted. Please try again.',
        );
        return false;
      }
      if (finishUnlocked) _setStatus(AppLockStatus.unlocked);
      return true;
    } on LocalAuthException catch (error) {
      if (!_isCurrent(attempt)) return false;
      switch (error.code) {
        case LocalAuthExceptionCode.temporaryLockout:
          _setStatus(
            AppLockStatus.temporaryLockout,
            'Too many attempts. Wait for your device to allow another attempt, '
            'then retry.',
          );
        case LocalAuthExceptionCode.biometricLockout:
          _setStatus(
            AppLockStatus.permanentLockout,
            'Biometrics are locked. Unlock your phone with its PIN, pattern, '
            'or password, then return and retry.',
          );
        case LocalAuthExceptionCode.userCanceled:
        case LocalAuthExceptionCode.systemCanceled:
        case LocalAuthExceptionCode.timeout:
          _setStatus(
            _enabled ? AppLockStatus.locked : AppLockStatus.disabled,
            'Authentication was canceled or interrupted. Please try again.',
          );
        default:
          _setStatus(
            AppLockStatus.unavailable,
            'Device authentication could not complete. Check your Android '
            'screen lock settings, then retry.',
          );
      }
      return false;
    } on PlatformException catch (error) {
      if (!_isCurrent(attempt)) return false;
      _setStatus(
        switch (error.code) {
          'LockedOut' => AppLockStatus.temporaryLockout,
          'PermanentlyLockedOut' => AppLockStatus.permanentLockout,
          _ => AppLockStatus.unavailable,
        },
        'Device authentication could not complete. Unlock your phone with '
        'its screen lock, then return and retry.',
      );
      return false;
    } catch (_) {
      if (!_isCurrent(attempt)) return false;
      _setStatus(
        AppLockStatus.unavailable,
        'Device authentication is unavailable. Please retry or check your '
        'Android screen lock settings.',
      );
      return false;
    }
  }

  /// Invalidates pending authentication so late native results cannot unlock.
  void lock() {
    ++_attempt;
    if (busy) unawaited(_authentication.cancel());
    _setStatus(_enabled ? AppLockStatus.locked : AppLockStatus.disabled);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed) return;
    _obscured = state != AppLifecycleState.resumed;
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      _inBackground = true;
      _backgroundedAt ??= _elapsed();
      _backgroundWallTime ??= _now();
      _backgroundTimer ??= Timer(backgroundGrace, lock);
    } else if (state == AppLifecycleState.resumed) {
      _inBackground = false;
      final backgroundedAt = _backgroundedAt;
      final wallTimeAway = _backgroundWallTime == null
          ? Duration.zero
          : _now().difference(_backgroundWallTime!);
      _backgroundTimer?.cancel();
      _backgroundTimer = null;
      _backgroundedAt = null;
      _backgroundWallTime = null;
      if (backgroundedAt != null &&
          (_elapsed() - backgroundedAt >= backgroundGrace ||
              wallTimeAway >= backgroundGrace ||
              wallTimeAway.isNegative)) {
        lock();
      }
    } else if (state == AppLifecycleState.detached) {
      _inBackground = true;
      lock();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_attempt;
    _backgroundTimer?.cancel();
    if (busy) unawaited(_authentication.cancel());
    super.dispose();
  }
}

extension on Stopwatch {
  Duration elapsedGetter() => elapsed;
}
