import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/constants.dart';

/// Service for managing onboarding state via SharedPreferences.
class OnboardingService {
  final SharedPreferences _prefs;
  bool _welcomeShownThisSession = false;

  OnboardingService(this._prefs);

  /// Whether the user has completed onboarding.
  bool isOnboardingComplete() {
    return _prefs.getBool(AppConstants.onboardingCompleteKey) ?? false;
  }

  /// Mark onboarding as completed.
  Future<void> completeOnboarding() async {
    await _prefs.setBool(AppConstants.onboardingCompleteKey, true);
  }

  /// Reset onboarding (useful for debug/dev).
  Future<void> resetOnboarding() async {
    await _prefs.remove(AppConstants.onboardingCompleteKey);
  }

  // ── Launch count + welcome screen ────────────────────────────────

  static const _launchCountKey = 'opa_launch_count';
  static const _welcomeScreenKey = 'opa_welcome_screen_enabled';

  /// Get the number of times the app has been launched.
  int getLaunchCount() => _prefs.getInt(_launchCountKey) ?? 0;

  /// Increment the launch counter (call on each app start).
  Future<void> incrementLaunchCount() async {
    final count = getLaunchCount() + 1;
    await _prefs.setInt(_launchCountKey, count);
  }

  /// Whether the welcome-back screen is enabled.
  bool isWelcomeScreenEnabled() => _prefs.getBool(_welcomeScreenKey) ?? true;

  /// Toggle the welcome-back screen on/off.
  Future<void> setWelcomeScreenEnabled(bool enabled) async {
    await _prefs.setBool(_welcomeScreenKey, enabled);
  }

  /// Whether to show the welcome-back screen right now.
  /// Returns true if: enabled AND second+ launch.
  bool shouldShowWelcomeBack() {
    if (_welcomeShownThisSession) return false;
    return isWelcomeScreenEnabled() && getLaunchCount() >= 2;
  }

  void markWelcomeShown() {
    _welcomeShownThisSession = true;
  }
}

/// Provider for the SharedPreferences instance (overridden in main.dart).
final sharedPrefsProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('Must be overridden before use');
});

/// Provider for the onboarding service.
final onboardingServiceProvider = Provider<OnboardingService>((ref) {
  final prefs = ref.watch(sharedPrefsProvider);
  return OnboardingService(prefs);
});
