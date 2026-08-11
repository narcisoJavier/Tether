import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A request to send a command to a specific terminal tab.
class PendingTabCommand {
  final String tabId;
  final String command;

  const PendingTabCommand({
    required this.tabId,
    required this.command,
  });
}

/// Provider that carries a command from the QuickCommands tab-picker dialog
/// to the target terminal tab within [TabbedTerminalScreen].
///
/// The source screen (QuickCommandsScreen) writes this when the user picks an
/// existing tab; the terminal's build method listens and forwards the command
/// into the tab's terminal.  Cleared after consumption.
final pendingQuickCommandProvider =
    StateProvider<PendingTabCommand?>((ref) => null);
