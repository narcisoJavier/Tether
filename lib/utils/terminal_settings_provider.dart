import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import '../services/onboarding_service.dart';
import '../utils/constants.dart';
import 'terminal_themes.dart';

const _fontSizeKey = 'opa_terminal_font_size';
const _scrollbackKey = 'opa_terminal_scrollback';
const _keepaliveKey = 'opa_terminal_keepalive';
const _themeIdKey = 'opa_terminal_theme_id';
const _fontFamilyKey = 'opa_terminal_font_family';
const _cursorTypeKey = 'opa_terminal_cursor_type';
const _cursorBlinkKey = 'opa_terminal_cursor_blink';
const _hapticFeedbackKey = 'opa_terminal_haptic_feedback';
const _bellModeKey = 'opa_terminal_bell_mode';

// ── Font Size ────────────────────────────────────────────────────────────────
final terminalFontSizeProvider =
    StateNotifierProvider<TerminalFontSizeNotifier, double>(
      (ref) => TerminalFontSizeNotifier(ref),
    );

class TerminalFontSizeNotifier extends StateNotifier<double> {
  final Ref _ref;
  TerminalFontSizeNotifier(this._ref) : super(AppConstants.defaultFontSize) {
    _load();
  }
  Future<void> _load() async {
    final prefs = _ref.read(sharedPrefsProvider);
    state = prefs.getDouble(_fontSizeKey) ?? AppConstants.defaultFontSize;
  }

  Future<void> setSize(double size) async {
    state = size.clamp(AppConstants.minFontSize, AppConstants.maxFontSize);
    final prefs = _ref.read(sharedPrefsProvider);
    await prefs.setDouble(_fontSizeKey, state);
  }
}

// ── Scrollback Lines ─────────────────────────────────────────────────────────
final terminalScrollbackProvider =
    StateNotifierProvider<TerminalScrollbackNotifier, int>(
      (ref) => TerminalScrollbackNotifier(ref),
    );

class TerminalScrollbackNotifier extends StateNotifier<int> {
  final Ref _ref;
  TerminalScrollbackNotifier(this._ref)
    : super(AppConstants.defaultScrollbackLines) {
    _load();
  }
  Future<void> _load() async {
    final prefs = _ref.read(sharedPrefsProvider);
    state = prefs.getInt(_scrollbackKey) ?? AppConstants.defaultScrollbackLines;
  }

  Future<void> setLines(int lines) async {
    state = lines.clamp(500, 100000);
    final prefs = _ref.read(sharedPrefsProvider);
    await prefs.setInt(_scrollbackKey, state);
  }
}

// ── Keepalive Interval ───────────────────────────────────────────────────────
final terminalKeepaliveProvider =
    StateNotifierProvider<TerminalKeepaliveNotifier, int>(
      (ref) => TerminalKeepaliveNotifier(ref),
    );

class TerminalKeepaliveNotifier extends StateNotifier<int> {
  final Ref _ref;
  TerminalKeepaliveNotifier(this._ref)
    : super(AppConstants.defaultKeepAlive.inSeconds) {
    _load();
  }
  Future<void> _load() async {
    final prefs = _ref.read(sharedPrefsProvider);
    state =
        prefs.getInt(_keepaliveKey) ?? AppConstants.defaultKeepAlive.inSeconds;
  }

  Future<void> setInterval(int seconds) async {
    state = seconds.clamp(5, 300);
    final prefs = _ref.read(sharedPrefsProvider);
    await prefs.setInt(_keepaliveKey, state);
  }
}

// ── Terminal Theme ───────────────────────────────────────────────────────────
final terminalThemeIdProvider =
    StateNotifierProvider<TerminalThemeIdNotifier, String>(
      (ref) => TerminalThemeIdNotifier(ref),
    );

class TerminalThemeIdNotifier extends StateNotifier<String> {
  final Ref _ref;
  TerminalThemeIdNotifier(this._ref) : super(TerminalThemePreset.oledEmerald.id) {
    _load();
  }
  Future<void> _load() async {
    final prefs = _ref.read(sharedPrefsProvider);
    state = prefs.getString(_themeIdKey) ?? TerminalThemePreset.oledEmerald.id;
  }

  Future<void> setTheme(String id) async {
    state = id;
    final prefs = _ref.read(sharedPrefsProvider);
    await prefs.setString(_themeIdKey, id);
  }
}

final terminalThemeProvider = Provider<TerminalThemePreset>((ref) {
  final id = ref.watch(terminalThemeIdProvider);
  return TerminalThemePreset.findById(id);
});

// ── Monospace Font Family ────────────────────────────────────────────────────
final terminalFontFamilyProvider =
    StateNotifierProvider<TerminalFontFamilyNotifier, String>(
      (ref) => TerminalFontFamilyNotifier(ref),
    );

class TerminalFontFamilyNotifier extends StateNotifier<String> {
  final Ref _ref;
  TerminalFontFamilyNotifier(this._ref) : super('JetBrainsMono') {
    _load();
  }
  Future<void> _load() async {
    final prefs = _ref.read(sharedPrefsProvider);
    state = prefs.getString(_fontFamilyKey) ?? 'JetBrainsMono';
  }

  Future<void> setFont(String font) async {
    state = font;
    final prefs = _ref.read(sharedPrefsProvider);
    await prefs.setString(_fontFamilyKey, font);
  }
}

// ── Cursor Type ──────────────────────────────────────────────────────────────
final terminalCursorTypeProvider =
    StateNotifierProvider<TerminalCursorTypeNotifier, TerminalCursorType>(
      (ref) => TerminalCursorTypeNotifier(ref),
    );

class TerminalCursorTypeNotifier extends StateNotifier<TerminalCursorType> {
  final Ref _ref;
  TerminalCursorTypeNotifier(this._ref) : super(TerminalCursorType.block) {
    _load();
  }
  Future<void> _load() async {
    final prefs = _ref.read(sharedPrefsProvider);
    final raw = prefs.getString(_cursorTypeKey);
    state = _cursorTypeFromString(raw);
  }

  Future<void> setType(TerminalCursorType type) async {
    state = type;
    final prefs = _ref.read(sharedPrefsProvider);
    await prefs.setString(_cursorTypeKey, _cursorTypeToString(type));
  }

  static String _cursorTypeToString(TerminalCursorType type) {
    switch (type) {
      case TerminalCursorType.underline:
        return 'underline';
      case TerminalCursorType.verticalBar:
        return 'verticalBar';
      case TerminalCursorType.block:
        return 'block';
    }
  }

  static TerminalCursorType _cursorTypeFromString(String? str) {
    switch (str) {
      case 'underline':
        return TerminalCursorType.underline;
      case 'verticalBar':
        return TerminalCursorType.verticalBar;
      case 'block':
      default:
        return TerminalCursorType.block;
    }
  }
}

// ── Cursor Blink ─────────────────────────────────────────────────────────────
final terminalCursorBlinkProvider =
    StateNotifierProvider<TerminalCursorBlinkNotifier, bool>(
      (ref) => TerminalCursorBlinkNotifier(ref),
    );

class TerminalCursorBlinkNotifier extends StateNotifier<bool> {
  final Ref _ref;
  TerminalCursorBlinkNotifier(this._ref) : super(true) {
    _load();
  }
  Future<void> _load() async {
    final prefs = _ref.read(sharedPrefsProvider);
    state = prefs.getBool(_cursorBlinkKey) ?? true;
  }

  Future<void> toggle() async {
    state = !state;
    final prefs = _ref.read(sharedPrefsProvider);
    await prefs.setBool(_cursorBlinkKey, state);
  }

  Future<void> setBlink(bool value) async {
    state = value;
    final prefs = _ref.read(sharedPrefsProvider);
    await prefs.setBool(_cursorBlinkKey, value);
  }
}

// ── Haptic Feedback ──────────────────────────────────────────────────────────
final terminalHapticFeedbackProvider =
    StateNotifierProvider<TerminalHapticFeedbackNotifier, bool>(
      (ref) => TerminalHapticFeedbackNotifier(ref),
    );

class TerminalHapticFeedbackNotifier extends StateNotifier<bool> {
  final Ref _ref;
  TerminalHapticFeedbackNotifier(this._ref) : super(true) {
    _load();
  }
  Future<void> _load() async {
    final prefs = _ref.read(sharedPrefsProvider);
    state = prefs.getBool(_hapticFeedbackKey) ?? true;
  }

  Future<void> toggle() async {
    state = !state;
    final prefs = _ref.read(sharedPrefsProvider);
    await prefs.setBool(_hapticFeedbackKey, state);
  }

  Future<void> setEnabled(bool value) async {
    state = value;
    final prefs = _ref.read(sharedPrefsProvider);
    await prefs.setBool(_hapticFeedbackKey, value);
  }
}

// ── Bell Mode (vibrate, visual, off) ─────────────────────────────────────────
final terminalBellModeProvider =
    StateNotifierProvider<TerminalBellModeNotifier, String>(
      (ref) => TerminalBellModeNotifier(ref),
    );

class TerminalBellModeNotifier extends StateNotifier<String> {
  final Ref _ref;
  TerminalBellModeNotifier(this._ref) : super('vibrate') {
    _load();
  }
  Future<void> _load() async {
    final prefs = _ref.read(sharedPrefsProvider);
    state = prefs.getString(_bellModeKey) ?? 'vibrate';
  }

  Future<void> setMode(String mode) async {
    state = mode;
    final prefs = _ref.read(sharedPrefsProvider);
    await prefs.setString(_bellModeKey, mode);
  }
}
