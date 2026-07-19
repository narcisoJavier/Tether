import 'package:flutter/material.dart';

/// App-wide constants.
class AppConstants {
  AppConstants._();

  static const String appName = 'OPA';
  static const String appFullTitle = 'OpenSSH Pocket Agent';

  // Hive box names
  static const String profilesBox = 'connection_profiles';
  static const String keysBox = 'ssh_keys';
  static const String commandsBox = 'quick_commands';

  // Secure storage keys prefix
  static const String secureStoragePrefix = 'opa_key_';

  // Onboarding
  static const String onboardingCompleteKey = 'opa_onboarding_complete';

  // Biometric lock
  static const String biometricLockEnabledKey = 'opa_biometric_lock_enabled';

  // Tailscale
  static const String tailscaleAuthKeyKey = 'opa_tailscale_auth_key';
  static const String tailscaleStateDirName = 'tailscale-state';

  // GitHub repository — used for update checks via Releases API
  static const String gitHubOwner = '2241812';
  static const String gitHubRepo = 'OPA_Flutter';

  // SSH defaults
  static const int defaultSshPort = 22;
  static const Duration defaultKeepAlive = Duration(seconds: 30);
  static const int defaultScrollbackLines = 10000;
  static const Duration connectionTimeout = Duration(seconds: 15);

  // Terminal defaults
  static const String defaultTermEnv = 'xterm-256color';
  static const double defaultFontSize = 14.0;
  static const double minFontSize = 6.0;
  static const double maxFontSize = 32.0;

  // Terminal auto-fit targets (for TUI apps like opencode)
  static const int targetMinColsPortrait = 80;
  static const int targetMinColsLandscape = 120;

  // Terminal char width approx multiplier (monospace char ≈ fontSize * ratio)
  static const double charWidthRatio = 0.6;

  // Status bar heights
  static const double statusBarHeightPortrait = 28.0;
  static const double statusBarHeightLandscape = 22.0;

  // Keyboard bar height
  static const double keyboardBarHeightPortrait = 44.0;
  static const double keyboardBarHeightLandscape = 36.0;

  // ── Design System Colors ──────────────────────────────────────────────────
  // Apple TUI: OLED black canvas + System Blue accent with iOS gray surfaces.

  /// Primary System Blue accent — used for active states, CTAs, focus.
  static const Color primaryGreen = Color(0xFF0A84FF);

  /// True darkest background — OLED black.
  static const Color bgDeep = Color(0xFF000000);

  /// Main scaffold background — OLED black.
  static const Color bgBase = Color(0xFF000000);

  /// Card/surface layer 1 (lowest) — iOS dark surface.
  static const Color surface0 = Color(0xFF1C1C1E);

  /// Card/surface layer 2 — main cards and tiles.
  static const Color surface1 = Color(0xFF2C2C2E);

  /// Card/surface layer 3 — modals, sheets, elevated containers.
  static const Color surface2 = Color(0xFF3A3A3C);

  /// Border/divider — ultra-subtle white.
  static const Color border0 = Color(0x0FFFFFFF); // 6% white
  static const Color border1 = Color(0x18FFFFFF); // 9% white — for hover/active

  /// Semantic accent: System Blue — secondary calls to action.
  static const Color accentBlue = Color(0xFF0A84FF);

  /// Semantic accent: System Orange — warnings, config actions.
  static const Color accentAmber = Color(0xFFFF9F0A);

  /// Semantic accent: System Purple — premium/power features.
  static const Color accentPurple = Color(0xFFBF5AF2);

  /// Input field fill.
  static const Color inputFill = Color(0xFF1C1C1E);

  // ── Legacy aliases (kept for backward compatibility) ──────────────────────
  static const Color surfaceDark = surface1;
  static const Color backgroundDark = bgBase;
}
