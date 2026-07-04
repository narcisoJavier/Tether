import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart' as dartssh2;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/connection_profile.dart';
import '../utils/constants.dart';

/// Connection state for an SSH session.
enum SshConnectionState {
  disconnected,
  connecting,
  connected,
  authenticating,
  error,
}

/// An active SSH session wrapping dartssh2's SSHSession.
class SshSession {
  SshSession({
    required this.client,
    required this.session,
  });

  final dartssh2.SSHClient client;
  final dartssh2.SSHSession session;

  /// Stream of output bytes from the remote shell.
  Stream<Uint8List> get stdout => session.stdout;

  /// Sink to write input bytes to the remote shell.
  StreamSink<Uint8List> get stdinSink => session.stdin;
}

/// Core SSH service wrapping dartssh2.
///
/// Provides methods to connect, open interactive shells, execute commands,
/// and manage the connection lifecycle.
class SshService extends ChangeNotifier {
  dartssh2.SSHClient? _client;
  dartssh2.SSHSession? _session;
  SshConnectionState _state = SshConnectionState.disconnected;
  String? _errorMessage;

  // PTY dimension tracking (last known cols/rows).
  int _currentCols = 80;
  int _currentRows = 24;

  SshConnectionState get state => _state;
  String? get errorMessage => _errorMessage;
  bool get isConnected => _state == SshConnectionState.connected;
  int get currentCols => _currentCols;
  int get currentRows => _currentRows;

  /// The underlying dartssh2 SSHClient, or null if not connected.
  dartssh2.SSHClient? get client => _client;

  /// Connect to a remote host using the given profile.
  ///
  /// [privateKey] is the OpenSSH-formatted private key PEM string, used for
  /// key-based auth. [keepalive] overrides the default keepalive interval.
  /// If [socket] is provided it is used instead of creating a direct TCP
  /// connection — this enables routing through a Tailscale tunnel.
  /// Returns the established dartssh2.SSHClient.
  Future<dartssh2.SSHClient> connect({
    required ConnectionProfile profile,
    String? privateKey,
    String? password,
    Duration? keepalive,
    dartssh2.SSHSocket? socket,
  }) async {
    _state = SshConnectionState.connecting;
    _errorMessage = null;
    notifyListeners();

    try {
      // Use the provided socket (e.g. from Tailscale) or create a direct
      // TCP connection through dartssh2's native socket.
      final sock = socket ??
          await dartssh2.SSHSocket.connect(
            profile.host,
            profile.port,
            timeout: AppConstants.connectionTimeout,
          );

      // Build identities for key-based auth. A PEM file may contain
      // multiple keys, so fromPem returns a List<SSHKeyPair>.
      final List<dartssh2.SSHKeyPair>? identities =
          (privateKey != null && privateKey.trim().isNotEmpty)
              ? dartssh2.SSHKeyPair.fromPem(privateKey)
              : null;

      final effectivePassword = password ?? profile.password;

      // SSHClient handles authentication automatically:
      //  - key auth via `identities`
      //  - password auth via `onPasswordRequest`
      _client = dartssh2.SSHClient(
        sock,
        username: profile.username,
        keepAliveInterval: keepalive ?? AppConstants.defaultKeepAlive,
        identities: identities ?? const [],
        onPasswordRequest: effectivePassword == null
            ? null
            : () => effectivePassword,
      );

      _state = SshConnectionState.authenticating;
      notifyListeners();

      // dartssh2 authenticates lazily on first channel open. Force
      // authentication by running a no-op command; an SSHAuthError is
      // thrown here if credentials are invalid.
      final testSession = await _client!.execute('true');
      await testSession.done;

      _state = SshConnectionState.connected;
      notifyListeners();

      return _client!;
    } on dartssh2.SSHAuthError catch (e) {
      _state = SshConnectionState.error;
      _errorMessage = 'Authentication failed: ${e.message}';
      notifyListeners();
      await _safeClose();
      rethrow;
    } on SocketException catch (e) {
      _state = SshConnectionState.error;
      _errorMessage = 'Connection failed: $e';
      notifyListeners();
      await _safeClose();
      rethrow;
    } catch (e) {
      _state = SshConnectionState.error;
      _errorMessage = 'Connection error: $e';
      notifyListeners();
      await _safeClose();
      rethrow;
    }
  }

  /// Open an interactive PTY shell session.
  ///
  /// Returns an [SshSession] with stdout stream and stdin sink wired up.
  Future<SshSession> startShell({
    required int cols,
    required int rows,
    int pixelWidth = 0,
    int pixelHeight = 0,
  }) async {
    if (_client == null) {
      throw StateError('Not connected. Call connect() first.');
    }

    _currentCols = cols;
    _currentRows = rows;

    _session = await _client!.shell(
      pty: dartssh2.SSHPtyConfig(
        type: AppConstants.defaultTermEnv,
        width: cols,
        height: rows,
        pixelWidth: pixelWidth,
        pixelHeight: pixelHeight,
      ),
    );

    return SshSession(client: _client!, session: _session!);
  }

  /// Execute a single command and return its stdout output.
  Future<String> executeCommand(String command) async {
    if (_client == null) {
      throw StateError('Not connected. Call connect() first.');
    }

    final session = await _client!.execute(command);
    return _stdoutToString(session.stdout);
  }

  /// Resize the PTY when the terminal view changes size.
  void resizeShell({
    required int cols,
    required int rows,
    int pixelWidth = 0,
    int pixelHeight = 0,
  }) {
    _currentCols = cols;
    _currentRows = rows;
    _session?.resizeTerminal(cols, rows, pixelWidth, pixelHeight);
  }

  /// Disconnect and clean up all resources.
  Future<void> disconnect() async {
    await _safeClose();
    _state = SshConnectionState.disconnected;
    _errorMessage = null;
    notifyListeners();
  }

  /// Test connection to a host without opening a shell.
  Future<bool> testConnection({
    required ConnectionProfile profile,
    String? privateKey,
    String? password,
    dartssh2.SSHSocket? socket,
  }) async {
    await connect(
      profile: profile,
      privateKey: privateKey,
      password: password,
      socket: socket,
    );
    await disconnect();
    return true;
  }

  // --- Helpers ---

  Future<void> _safeClose() async {
    try {
      _client?.close();
    } catch (_) {
      // Ignore cleanup errors
    }
    _session = null;
    _client = null;
  }

  Future<String> _stdoutToString(Stream<Uint8List> stream) async {
    final buffer = <int>[];
    await for (final chunk in stream) {
      buffer.addAll(chunk);
    }
    return String.fromCharCodes(buffer);
  }
}

/// Provider for the SSH service singleton.
final sshServiceProvider = ChangeNotifierProvider<SshService>((ref) {
  return SshService();
});
