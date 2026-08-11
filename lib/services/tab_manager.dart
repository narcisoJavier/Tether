import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/terminal_tab.dart';

/// Global state notifier that tracks all open terminal tabs across the app.
///
/// Used by:
/// - [TabbedTerminalScreen] to register/deregister tabs
/// - [QuickCommandsScreen] to show the tab picker dialog
/// - Any screen that needs to know whether a terminal is alive
class TabManager extends StateNotifier<List<TerminalTab>> {
  TabManager() : super([]);

  void addTab(TerminalTab tab) {
    state = [...state, tab];
  }

  void removeTab(String tabId) {
    state = state.where((t) => t.tabId != tabId).toList();
  }

  void updateTab(String tabId, TerminalTab Function(TerminalTab) updater) {
    state = state.map((t) => t.tabId == tabId ? updater(t) : t).toList();
  }

  void clear() {
    state = [];
  }

  /// Returns all tabs for a given profile.
  List<TerminalTab> tabsForProfile(String profileId) {
    return state.where((t) => t.profileId == profileId).toList();
  }

  /// Whether any tab exists for the given profile.
  bool hasTabsForProfile(String profileId) {
    return state.any((t) => t.profileId == profileId);
  }
}

/// Riverpod provider for the global [TabManager].
final tabManagerProvider = StateNotifierProvider<TabManager, List<TerminalTab>>(
  (ref) => TabManager(),
);
