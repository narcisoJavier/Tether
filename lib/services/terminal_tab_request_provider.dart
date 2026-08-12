import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Request to open a new terminal tab for a given [profileId], optionally
/// pre-seeding the terminal with [initialCommand].
class TerminalTabRequest {
  final String profileId;
  final String? initialCommand;

  const TerminalTabRequest({required this.profileId, this.initialCommand});
}

/// Provider that carries a pending terminal tab request from any screen
/// (Home, QCMD, SFTP) into the persistent [TabbedTerminalScreen].
///
/// Written by the source screen, consumed (and cleared) by the terminal
/// which listens for changes via [ref.listen].
final pendingTerminalTabProvider = StateProvider<TerminalTabRequest?>(
  (ref) => null,
);
