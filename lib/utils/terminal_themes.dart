import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import 'constants.dart';

/// A terminal color palette preset for xterm.dart.
class TerminalThemePreset {
  final String id;
  final String name;
  final String description;
  final Color previewColor;
  final Color previewBackground;
  final TerminalTheme theme;

  const TerminalThemePreset({
    required this.id,
    required this.name,
    required this.description,
    required this.previewColor,
    required this.previewBackground,
    required this.theme,
  });

  /// All available curated terminal themes.
  static const List<TerminalThemePreset> presets = [
    oledEmerald,
    tokyoNight,
    cyberpunkNeon,
    monokaiPro,
    classicAmber,
    solarizedDark,
  ];

  /// Find preset by ID, falling back to OLED Emerald.
  static TerminalThemePreset findById(String? id) {
    if (id == null) return oledEmerald;
    return presets.firstWhere(
      (p) => p.id == id,
      orElse: () => oledEmerald,
    );
  }

  // ── 1. OLED Emerald (Default Tether Aesthetic) ──────────────────────────────
  static const TerminalThemePreset oledEmerald = TerminalThemePreset(
    id: 'emerald',
    name: 'OLED Emerald',
    description: 'High-contrast emerald phosphor on pure OLED black',
    previewColor: Color(0xFF00E599),
    previewBackground: Color(0xFF000000),
    theme: TerminalTheme(
      cursor: AppConstants.primaryGreen,
      selection: Color(0x7F00E676),
      foreground: Colors.white,
      background: Color(0xFF000000),
      black: Color(0xFF000000),
      red: Color(0xFFFF5252),
      green: AppConstants.primaryGreen,
      yellow: Color(0xFFFFAB40),
      blue: Color(0xFF448AFF),
      magenta: Color(0xFFE040FB),
      cyan: Color(0xFF18FFFF),
      white: Color(0xFFFFFFFF),
      brightBlack: Color(0xFF546E7A),
      brightRed: Color(0xFFFF8A80),
      brightGreen: Color(0xFF69F0AE),
      brightYellow: Color(0xFFFFD740),
      brightBlue: Color(0xFF82B1FF),
      brightMagenta: Color(0xFFFF80AB),
      brightCyan: Color(0xFF84FFFF),
      brightWhite: Color(0xFFFFFFFF),
      searchHitBackground: Color(0x7FFFFFFF),
      searchHitBackgroundCurrent: Color(0x7F00E676),
      searchHitForeground: Color(0xFF000000),
    ),
  );

  // ── 2. Tokyo Night ──────────────────────────────────────────────────────────
  static const TerminalThemePreset tokyoNight = TerminalThemePreset(
    id: 'tokyo_night',
    name: 'Tokyo Night',
    description: 'Deep midnight navy with pastel cyan and violet',
    previewColor: Color(0xFF7DCFFF),
    previewBackground: Color(0xFF1A1B26),
    theme: TerminalTheme(
      cursor: Color(0xFFC0CAF5),
      selection: Color(0x40364A82),
      foreground: Color(0xFFA9B1D6),
      background: Color(0xFF1A1B26),
      black: Color(0xFF15161E),
      red: Color(0xFFF7768E),
      green: Color(0xFF9ECE6A),
      yellow: Color(0xFFE0AF68),
      blue: Color(0xFF7AA2F7),
      magenta: Color(0xFFBB9AF7),
      cyan: Color(0xFF7DCFFF),
      white: Color(0xFFA9B1D6),
      brightBlack: Color(0xFF414868),
      brightRed: Color(0xFFF7768E),
      brightGreen: Color(0xFF9ECE6A),
      brightYellow: Color(0xFFE0AF68),
      brightBlue: Color(0xFF7AA2F7),
      brightMagenta: Color(0xFFBB9AF7),
      brightCyan: Color(0xFF7DCFFF),
      brightWhite: Color(0xFFC0CAF5),
      searchHitBackground: Color(0x507AA2F7),
      searchHitBackgroundCurrent: Color(0x807AA2F7),
      searchHitForeground: Color(0xFFFFFFFF),
    ),
  );

  // ── 3. Cyberpunk Neon ───────────────────────────────────────────────────────
  static const TerminalThemePreset cyberpunkNeon = TerminalThemePreset(
    id: 'cyberpunk',
    name: 'Cyberpunk Neon',
    description: 'Electric cyan and vivid hot pink on dark purple',
    previewColor: Color(0xFF00FFF0),
    previewBackground: Color(0xFF100E23),
    theme: TerminalTheme(
      cursor: Color(0xFF00FFF0),
      selection: Color(0x50FF0055),
      foreground: Color(0xFFEBF8FF),
      background: Color(0xFF100E23),
      black: Color(0xFF0B0A14),
      red: Color(0xFFFF0055),
      green: Color(0xFF00FF9F),
      yellow: Color(0xFFFFE600),
      blue: Color(0xFF00FFF0),
      magenta: Color(0xFFD600FF),
      cyan: Color(0xFF00FFF0),
      white: Color(0xFFEBF8FF),
      brightBlack: Color(0xFF383556),
      brightRed: Color(0xFFFF3377),
      brightGreen: Color(0xFF33FFAF),
      brightYellow: Color(0xFFFFEE33),
      brightBlue: Color(0xFF33FFFF),
      brightMagenta: Color(0xFFDE33FF),
      brightCyan: Color(0xFF33FFFF),
      brightWhite: Color(0xFFFFFFFF),
      searchHitBackground: Color(0x50D600FF),
      searchHitBackgroundCurrent: Color(0x8000FFF0),
      searchHitForeground: Color(0xFF000000),
    ),
  );

  // ── 4. Monokai Pro ──────────────────────────────────────────────────────────
  static const TerminalThemePreset monokaiPro = TerminalThemePreset(
    id: 'monokai',
    name: 'Monokai Pro',
    description: 'Warm charcoal background with classic syntax colors',
    previewColor: Color(0xFFFFD866),
    previewBackground: Color(0xFF222222),
    theme: TerminalTheme(
      cursor: Color(0xFFFFD866),
      selection: Color(0x50403E41),
      foreground: Color(0xFFFCFCFA),
      background: Color(0xFF222222),
      black: Color(0xFF2C2525),
      red: Color(0xFFFF6188),
      green: Color(0xFFA9DC76),
      yellow: Color(0xFFFFD866),
      blue: Color(0xFF78DCE8),
      magenta: Color(0xFFAB9DF2),
      cyan: Color(0xFF78DCE8),
      white: Color(0xFFFCFCFA),
      brightBlack: Color(0xFF727072),
      brightRed: Color(0xFFFF6188),
      brightGreen: Color(0xFFA9DC76),
      brightYellow: Color(0xFFFFD866),
      brightBlue: Color(0xFF78DCE8),
      brightMagenta: Color(0xFFAB9DF2),
      brightCyan: Color(0xFF78DCE8),
      brightWhite: Color(0xFFFFFFFF),
      searchHitBackground: Color(0x50AB9DF2),
      searchHitBackgroundCurrent: Color(0x80FFD866),
      searchHitForeground: Color(0xFF000000),
    ),
  );

  // ── 5. Classic Amber ────────────────────────────────────────────────────────
  static const TerminalThemePreset classicAmber = TerminalThemePreset(
    id: 'amber',
    name: 'Classic Amber',
    description: 'Retro 1980s DEC VT220 amber phosphor monitor',
    previewColor: Color(0xFFFFB000),
    previewBackground: Color(0xFF141008),
    theme: TerminalTheme(
      cursor: Color(0xFFFFB000),
      selection: Color(0x50FFB000),
      foreground: Color(0xFFFFB000),
      background: Color(0xFF141008),
      black: Color(0xFF0D0B05),
      red: Color(0xFFFF8C00),
      green: Color(0xFFFFC04D),
      yellow: Color(0xFFFFD000),
      blue: Color(0xFFFFA500),
      magenta: Color(0xFFFF9900),
      cyan: Color(0xFFFFB833),
      white: Color(0xFFFFE0B2),
      brightBlack: Color(0xFF5C4724),
      brightRed: Color(0xFFFF9E33),
      brightGreen: Color(0xFFFFCC66),
      brightYellow: Color(0xFFFFDD33),
      brightBlue: Color(0xFFFFB733),
      brightMagenta: Color(0xFFFFAD33),
      brightCyan: Color(0xFFFFC55C),
      brightWhite: Color(0xFFFFF3E0),
      searchHitBackground: Color(0x50FF9900),
      searchHitBackgroundCurrent: Color(0x80FFB000),
      searchHitForeground: Color(0xFF141008),
    ),
  );

  // ── 6. Solarized Dark ───────────────────────────────────────────────────────
  static const TerminalThemePreset solarizedDark = TerminalThemePreset(
    id: 'solarized',
    name: 'Solarized Dark',
    description: 'Precision teal-slate palette designed for low eye strain',
    previewColor: Color(0xFF2AA198),
    previewBackground: Color(0xFF002B36),
    theme: TerminalTheme(
      cursor: Color(0xFF839496),
      selection: Color(0x40073642),
      foreground: Color(0xFF839496),
      background: Color(0xFF002B36),
      black: Color(0xFF073642),
      red: Color(0xFFDC322F),
      green: Color(0xFF859900),
      yellow: Color(0xFFB58900),
      blue: Color(0xFF268BD2),
      magenta: Color(0xFFD33682),
      cyan: Color(0xFF2AA198),
      white: Color(0xFFEEE8D5),
      brightBlack: Color(0xFF586E75),
      brightRed: Color(0xFFCB4B16),
      brightGreen: Color(0xFF859900),
      brightYellow: Color(0xFFB58900),
      brightBlue: Color(0xFF268BD2),
      brightMagenta: Color(0xFF6C71C4),
      brightCyan: Color(0xFF2AA198),
      brightWhite: Color(0xFFFDF6E3),
      searchHitBackground: Color(0x502AA198),
      searchHitBackgroundCurrent: Color(0x802AA198),
      searchHitForeground: Color(0xFF002B36),
    ),
  );
}
