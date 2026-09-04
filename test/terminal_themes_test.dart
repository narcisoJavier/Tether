import 'package:flutter_test/flutter_test.dart';
import 'package:tether/utils/terminal_themes.dart';

void main() {
  group('TerminalThemePreset', () {
    test('contains 6 curated presets', () {
      expect(TerminalThemePreset.presets.length, equals(6));
    });

    test('findById returns matching preset', () {
      expect(TerminalThemePreset.findById('emerald').id, equals('emerald'));
      expect(TerminalThemePreset.findById('tokyo_night').id, equals('tokyo_night'));
      expect(TerminalThemePreset.findById('cyberpunk').id, equals('cyberpunk'));
      expect(TerminalThemePreset.findById('monokai').id, equals('monokai'));
      expect(TerminalThemePreset.findById('amber').id, equals('amber'));
      expect(TerminalThemePreset.findById('solarized').id, equals('solarized'));
    });

    test('findById falls back to OLED Emerald for unknown or null id', () {
      expect(TerminalThemePreset.findById(null).id, equals('emerald'));
      expect(TerminalThemePreset.findById('non_existent').id, equals('emerald'));
    });

    test('all presets have distinct preview colors and non-empty descriptions', () {
      final ids = <String>{};
      for (final p in TerminalThemePreset.presets) {
        expect(ids.add(p.id), isTrue, reason: 'Duplicate theme id: ${p.id}');
        expect(p.name, isNotEmpty);
        expect(p.description, isNotEmpty);
        expect(p.theme.cursor, isNotNull);
        expect(p.theme.background, isNotNull);
        expect(p.theme.foreground, isNotNull);
      }
    });
  });
}
