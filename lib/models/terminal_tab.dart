/// Represents a single terminal tab's metadata within a [TabbedTerminalScreen].
///
/// Each tab corresponds to one SSH session on a specific profile. Tabs are
/// tracked globally by [TabManager] and can receive commands from outside
/// (e.g. Quick Commands) via [PendingTabCommand].
class TerminalTab {
  final String tabId;
  final String profileId;
  final String label;
  final bool isConnected;
  final bool isConnecting;
  final bool shellStarted;
  final String? error;

  const TerminalTab({
    required this.tabId,
    required this.profileId,
    required this.label,
    this.isConnected = false,
    this.isConnecting = false,
    this.shellStarted = false,
    this.error,
  });

  TerminalTab copyWith({
    String? tabId,
    String? profileId,
    String? label,
    bool? isConnected,
    bool? isConnecting,
    bool? shellStarted,
    String? error,
  }) {
    return TerminalTab(
      tabId: tabId ?? this.tabId,
      profileId: profileId ?? this.profileId,
      label: label ?? this.label,
      isConnected: isConnected ?? this.isConnected,
      isConnecting: isConnecting ?? this.isConnecting,
      shellStarted: shellStarted ?? this.shellStarted,
      error: error ?? this.error,
    );
  }
}
