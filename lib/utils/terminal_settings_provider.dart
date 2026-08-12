import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/onboarding_service.dart';
import '../utils/constants.dart';

const _fontSizeKey = 'opa_terminal_font_size';
const _scrollbackKey = 'opa_terminal_scrollback';
const _keepaliveKey = 'opa_terminal_keepalive';

// --- Font Size ---
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

// --- Scrollback Lines ---
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

// --- Keepalive Interval ---
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
