import 'package:dartssh2/dartssh2.dart' as dartssh2;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/connection_profile.dart';
import '../utils/terminal_settings_provider.dart';
import 'host_key_verifier.dart';
import 'key_service.dart';
import 'profile_storage_service.dart';
import 'ssh_service.dart';
import 'tailscale_provider.dart';
import 'tailscale_ssh_socket.dart';

/// Creates independently owned connections using the shared transport and trust policy.
class SshConnectionFactory {
  const SshConnectionFactory({
    required this.createService,
    required this.loadPrivateKey,
    required this.loadPassword,
    required this.openSocket,
    required this.keepalive,
  });

  final SshService Function() createService;
  final Future<String?> Function(String keyId) loadPrivateKey;
  final Future<String?> Function(String profileId) loadPassword;
  final Future<dartssh2.SSHSocket?> Function(ConnectionProfile profile)
  openSocket;
  final Duration keepalive;

  /// Connects the caller-owned service without sharing another session's client.
  Future<dartssh2.SSHClient> connect({
    required SshService service,
    required ConnectionProfile profile,
    required HostKeyDecisionHandler onHostKeyDecision,
  }) async {
    final key = profile.keyId == null
        ? null
        : await loadPrivateKey(profile.keyId!);
    final password = await loadPassword(profile.id);
    if (service.isDisposed) throw StateError('SSH session was closed.');
    final socket = await openSocket(profile);
    if (service.isDisposed) {
      socket?.close();
      throw StateError('SSH session was closed.');
    }
    return service.connect(
      profile: profile,
      privateKey: key,
      password: password ?? profile.password,
      socket: socket,
      keepalive: keepalive,
      onHostKeyDecision: onHostKeyDecision,
    );
  }

  /// Executes a command on a private connection and releases it on every path.
  Future<String> executeOnce({
    required ConnectionProfile profile,
    required String command,
    required HostKeyDecisionHandler onHostKeyDecision,
  }) async {
    final service = createService();
    try {
      await connect(
        service: service,
        profile: profile,
        onHostKeyDecision: onHostKeyDecision,
      );
      return await service.executeCommand(command);
    } finally {
      try {
        await service.disconnect();
      } finally {
        service.dispose();
      }
    }
  }
}

/// Shared connection setup for terminals, commands, and file browsers.
final sshConnectionFactoryProvider = Provider<SshConnectionFactory>((ref) {
  final storage = ref.watch(profileStorageProvider);
  final keys = ref.watch(keyServiceProvider);
  final tailscale = ref.watch(tailscaleServiceProvider);
  return SshConnectionFactory(
    createService: ref.watch(sshServiceFactoryProvider),
    loadPrivateKey: keys.getPrivateKey,
    loadPassword: storage.getPassword,
    openSocket: (profile) async {
      if (profile.connectionMethod != ConnectionMethod.tailscale) return null;
      final connection = await tailscale.dial(
        profile.host,
        profile.port,
        timeout: const Duration(seconds: 10),
      );
      return TailscaleSSHSocket(connection);
    },
    keepalive: Duration(seconds: ref.watch(terminalKeepaliveProvider)),
  );
});
