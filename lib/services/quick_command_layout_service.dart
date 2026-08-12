import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'onboarding_service.dart';

/// A small persisted layout store for the command deck.
///
/// Commands themselves remain in Hive. This store only remembers presentation
/// metadata, which also lets built-in presets be rearranged without copying
/// them into the user's saved-command collection.
class QuickCommandLayoutService {
  QuickCommandLayoutService(this._prefs) {
    _load();
  }

  static const String _storageKey = 'tether_quick_command_layout_v1';
  static const String _folderRowsKey = 'tether_quick_command_folder_rows_v1';

  final SharedPreferences _prefs;
  final Map<String, _LayoutEntry> _entries = {};
  final Map<String, int> _folderRows = {};

  void _load() {
    final encoded = _prefs.getString(_storageKey);
    if (encoded != null && encoded.isNotEmpty) {
      try {
        final decoded = jsonDecode(encoded);
        if (decoded is Map) {
          for (final item in decoded.entries) {
            if (item.value is Map) {
              _entries[item.key.toString()] = _LayoutEntry.fromJson(
                Map<String, dynamic>.from(item.value as Map),
              );
            }
          }
        }
      } catch (_) {
        _entries.clear();
      }
    }

    final encodedRows = _prefs.getString(_folderRowsKey);
    if (encodedRows != null && encodedRows.isNotEmpty) {
      try {
        final decodedRows = jsonDecode(encodedRows);
        if (decodedRows is Map) {
          for (final item in decodedRows.entries) {
            final rows = item.value;
            if (rows is num) {
              _folderRows[item.key.toString()] = rows
                  .toInt()
                  .clamp(1, 4)
                  .toInt();
            }
          }
        }
      } catch (_) {
        _folderRows.clear();
      }
    }
  }

  /// Returns the stored category or [fallback] when an item is new.
  String categoryFor(String key, String fallback) =>
      _entries[key]?.category ?? fallback;

  /// Returns the number of tile rows shown inside a category folder.
  int folderRows(String category, {int fallback = 2}) =>
      _folderRows[category] ?? fallback;

  /// Stores the visible row count for a category folder.
  void setFolderRows(String category, int rows) {
    _folderRows[category] = rows.clamp(1, 4).toInt();
  }

  /// Orders [items] using the user's saved positions while keeping new items
  /// in their source order at the end.
  List<T> orderItems<T>(List<T> items, String Function(T item) keyOf) {
    final indexed = items.asMap().entries.toList();
    indexed.sort((a, b) {
      final aEntry = _entries[keyOf(a.value)];
      final bEntry = _entries[keyOf(b.value)];
      final aOrder = aEntry?.order ?? 1 << 30;
      final bOrder = bEntry?.order ?? 1 << 30;
      return aOrder == bOrder
          ? a.key.compareTo(b.key)
          : aOrder.compareTo(bOrder);
    });
    return indexed.map((entry) => entry.value).toList();
  }

  /// Changes an item's category in memory until the next [persist] call.
  void setCategory(String key, String category) {
    final current = _entries[key];
    _entries[key] = _LayoutEntry(
      category: category,
      order: current?.order ?? (1 << 30),
    );
  }

  /// Saves the order of one category and persists the complete layout.
  Future<void> saveCategoryOrder(List<String> keys, String category) async {
    for (var index = 0; index < keys.length; index++) {
      final key = keys[index];
      _entries[key] = _LayoutEntry(category: category, order: index);
    }
    await persist();
  }

  /// Persists the current in-memory layout.
  Future<void> persist() async {
    final encoded = jsonEncode(
      _entries.map((key, value) => MapEntry(key, value.toJson())),
    );
    await _prefs.setString(_storageKey, encoded);
    await _prefs.setString(_folderRowsKey, jsonEncode(_folderRows));
  }
}

class _LayoutEntry {
  const _LayoutEntry({required this.category, required this.order});

  final String category;
  final int order;

  factory _LayoutEntry.fromJson(Map<String, dynamic> json) {
    return _LayoutEntry(
      category: json['category'] as String? ?? 'custom',
      order: json['order'] as int? ?? (1 << 30),
    );
  }

  Map<String, dynamic> toJson() => {'category': category, 'order': order};
}

/// Riverpod provider for the persisted command-deck layout.
final quickCommandLayoutProvider = Provider<QuickCommandLayoutService>((ref) {
  return QuickCommandLayoutService(ref.watch(sharedPrefsProvider));
});
