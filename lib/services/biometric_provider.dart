import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/constants.dart';
import 'onboarding_service.dart';

/// Provider tracking whether the biometric lock toggle is enabled.
///
/// Persisted to SharedPreferences so it survives app restarts.
final biometricLockEnabledProvider =
    StateNotifierProvider<BiometricLockNotifier, bool>((ref) {
      final prefs = ref.watch(sharedPrefsProvider);
      return BiometricLockNotifier(prefs);
    });

class BiometricLockNotifier extends StateNotifier<bool> {
  final SharedPreferences _prefs;

  BiometricLockNotifier(this._prefs)
    : super(_prefs.getBool(AppConstants.biometricLockEnabledKey) ?? false);

  /// Toggle the lock on/off and persist.
  Future<void> toggle() async {
    state = !state;
    await _prefs.setBool(AppConstants.biometricLockEnabledKey, state);
  }

  /// Enable the lock (e.g. from settings).
  Future<void> enable() async {
    if (!state) {
      state = true;
      await _prefs.setBool(AppConstants.biometricLockEnabledKey, true);
    }
  }

  /// Disable the lock (e.g. from settings).
  Future<void> disable() async {
    if (state) {
      state = false;
      await _prefs.setBool(AppConstants.biometricLockEnabledKey, false);
    }
  }
}

/// Tracks whether the user has authenticated in the current app session.
///
/// Resets to `false` when the app process is killed. Remains `true` while the
/// app is backgrounded (does not re-prompt every background/foreground cycle).
///
/// WARNING: This is in-memory only — on app restart, the gate widget reads
/// [biometricLockEnabledProvider] and shows the lock screen again.
final authSessionProvider = StateProvider<bool>((ref) => false);
