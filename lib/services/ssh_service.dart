import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart' as dartssh2;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/connection_profile.dart';
import '../models/tunnel_config.dart';
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

  /// Auto-start all enabled tunnels from a profile's tunnel configuration.
  ///
  /// Called after a successful SSH connection to start tunnels marked as
  /// enabled. Errors on individual tunnels are logged but don't prevent
  /// other tunnels from starting.
  Future<int> autoStartTunnels(List<TunnelConfig> tunnels) async {
    int started = 0;
    for (final tunnel in tunnels) {
      if (!tunnel.enabled) continue;
      try {
        switch (tunnel.type) {
          case TunnelType.local:
            await forwardLocal(
              tunnelId: tunnel.id,
              localPort: tunnel.localPort,
              remoteHost: tunnel.remoteHost,
              remotePort: tunnel.remotePort,
            );
            break;
          case TunnelType.remote:
            await forwardRemote(
              tunnelId: tunnel.id,
              remotePort: tunnel.remotePort,
              localHost: tunnel.remoteHost,
              localPort: tunnel.localPort,
            );
            break;
          case TunnelType.dynamicSocks5:
            await dynamicSocks5(
              tunnelId: tunnel.id,
              localPort: tunnel.localPort,
            );
            break;
        }
        started++;
      } catch (e) {
        debugPrint('[TUNNEL] Auto-start failed for "${tunnel.label}": $e');
      }
    }
    return started;
  }

  // --- Port Forwarding / Tunnels ---

  /// Active tunnel tracking: tunnelId → ActiveTunnel.
  final Map<String, ActiveTunnel> _activeTunnels = {};

  /// Read-only view of active tunnels.
  Map<String, ActiveTunnel> get activeTunnels =>
      Map.unmodifiable(_activeTunnels);

  /// Start a local port forward: binds localPort on localhost and tunnels
  /// each connection to remoteHost:remotePort via the SSH session.
  Future<ActiveTunnel> forwardLocal({
    required String tunnelId,
    required int localPort,
    required String remoteHost,
    required int remotePort,
  }) async {
    if (_client == null) {
      throw StateError('Not connected. Call connect() first.');
    }

    final serverSocket = await ServerSocket.bind('localhost', localPort);
    final subscriptions = <StreamSubscription>[];

    final sub = serverSocket.listen((socket) async {
      try {
        final forward = await _client!.forwardLocal(remoteHost, remotePort);
        forward.stream.cast<List<int>>().pipe(socket);
        socket.cast<List<int>>().pipe(forward.sink);
      } catch (e) {
        debugPrint('[TUNNEL] Local forward connection error: $e');
        socket.destroy();
      }
    });
    subscriptions.add(sub);

    final tunnel = ActiveTunnel(
      id: tunnelId,
      type: TunnelType.local,
      localPort: localPort,
      remoteHost: remoteHost,
      remotePort: remotePort,
      serverSocket: serverSocket,
      subscriptions: subscriptions,
    );
    _activeTunnels[tunnelId] = tunnel;
    notifyListeners();
    return tunnel;
  }

  /// Start a remote port forward: asks the server to listen on remotePort
  /// and tunnels connections back to localHost:localPort.
  Future<ActiveTunnel> forwardRemote({
    required String tunnelId,
    required int remotePort,
    required String localHost,
    required int localPort,
  }) async {
    if (_client == null) {
      throw StateError('Not connected. Call connect() first.');
    }

    final forward = await _client!.forwardRemote(port: remotePort);
    if (forward == null) {
      throw StateError('Remote forwarding rejected by server');
    }

    final subscriptions = <StreamSubscription>[];
    final sub = forward.connections.listen((connection) async {
      try {
        final local = await Socket.connect(localHost, localPort);
        connection.stream.cast<List<int>>().pipe(local);
        local.cast<List<int>>().pipe(connection.sink);
      } catch (e) {
        debugPrint('[TUNNEL] Remote forward connection error: $e');
      }
    });
    subscriptions.add(sub);

    final tunnel = ActiveTunnel(
      id: tunnelId,
      type: TunnelType.remote,
      localPort: localPort,
      remoteHost: localHost,
      remotePort: remotePort,
      subscriptions: subscriptions,
    );
    _activeTunnels[tunnelId] = tunnel;
    notifyListeners();
    return tunnel;
  }

  /// Start a SOCKS5 dynamic tunnel: binds localPort on localhost and handles
  /// SOCKS5 CONNECT requests, forwarding each to the requested host via SSH.
  Future<ActiveTunnel> dynamicSocks5({
    required String tunnelId,
    required int localPort,
  }) async {
    if (_client == null) {
      throw StateError('Not connected. Call connect() first.');
    }

    final serverSocket = await ServerSocket.bind('localhost', localPort);
    final subscriptions = <StreamSubscription>[];

    final sub = serverSocket.listen((socket) {
      _handleSocks5Connection(socket);
    });
    subscriptions.add(sub);

    final tunnel = ActiveTunnel(
      id: tunnelId,
      type: TunnelType.dynamicSocks5,
      localPort: localPort,
      remoteHost: 'dynamic',
      remotePort: 0,
      serverSocket: serverSocket,
      subscriptions: subscriptions,
    );
    _activeTunnels[tunnelId] = tunnel;
    notifyListeners();
    return tunnel;
  }

  /// Minimal SOCKS5 handler: supports CONNECT only (no auth).
  void _handleSocks5Connection(Socket socket) async {
    try {
      // Use StreamIterator for proper sequential reads — socket.first
      // would create separate subscriptions that can miss data.
      final iter = StreamIterator(socket);

      // Read SOCKS5 greeting
      if (!await iter.moveNext()) {
        socket.destroy();
        return;
      }
      final greeting = iter.current;
      if (greeting.isEmpty || greeting[0] != 0x05) {
        socket.destroy();
        return;
      }

      // Reply: no auth required
      socket.add([0x05, 0x00]);

      // Read CONNECT request
      if (!await iter.moveNext()) {
        socket.destroy();
        return;
      }
      final request = iter.current;
      if (request.length < 4 || request[1] != 0x01) {
        socket.add([0x05, 0x07, 0x00, 0x01, 0, 0, 0, 0, 0, 0]);
        socket.destroy();
        return;
      }

      String host;
      int port;
      final addrType = request[3];

      if (addrType == 0x01) {
        // IPv4
        host = '${request[4]}.${request[5]}.${request[6]}.${request[7]}';
        port = (request[8] << 8) | request[9];
      } else if (addrType == 0x03) {
        // Domain name
        final len = request[4];
        host = String.fromCharCodes(request.sublist(5, 5 + len));
        port = (request[5 + len] << 8) | request[6 + len];
      } else {
        // IPv6 or unsupported
        socket.add([0x05, 0x08, 0x00, 0x01, 0, 0, 0, 0, 0, 0]);
        socket.destroy();
        return;
      }

      // Cancel the iterator before piping — the pipe will take over the stream.
      await iter.cancel();

      // Forward via SSH
      final forward = await _client!.forwardLocal(host, port);

      // Reply: success
      socket.add([0x05, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0]);

      // Pipe data bidirectionally
      forward.stream.cast<List<int>>().pipe(socket);
      socket.cast<List<int>>().pipe(forward.sink);
    } catch (e) {
      debugPrint('[TUNNEL] SOCKS5 error: $e');
      try {
        socket.destroy();
      } catch (_) {}
    }
  }

  /// Stop a specific tunnel by ID.
  Future<void> stopTunnel(String tunnelId) async {
    final tunnel = _activeTunnels.remove(tunnelId);
    if (tunnel != null) {
      await tunnel.close();
      notifyListeners();
    }
  }

  /// Stop all active tunnels.
  Future<void> stopAllTunnels() async {
    for (final tunnel in _activeTunnels.values) {
      await tunnel.close();
    }
    _activeTunnels.clear();
    notifyListeners();
  }

  // --- Helpers ---

  Future<void> _safeClose() async {
    // Stop all tunnels before closing the SSH connection.
    for (final tunnel in _activeTunnels.values) {
      await tunnel.close();
    }
    _activeTunnels.clear();

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

/// Represents an active, running tunnel.
class ActiveTunnel {
  ActiveTunnel({
    required this.id,
    required this.type,
    required this.localPort,
    required this.remoteHost,
    required this.remotePort,
    this.serverSocket,
    this.subscriptions = const [],
  });

  final String id;
  final TunnelType type;
  final int localPort;
  final String remoteHost;
  final int remotePort;
  final ServerSocket? serverSocket;
  final List<StreamSubscription> subscriptions;

  /// Close the tunnel and clean up resources.
  Future<void> close() async {
    for (final sub in subscriptions) {
      await sub.cancel();
    }
    try {
      await serverSocket?.close();
    } catch (_) {}
  }
}

/// Provider for per-session SSH service instances.
///
/// Each profile gets its own [SshService] keyed by `profileId`, enabling
/// multiple independent SSH sessions. Auto-disposed when no longer watched.
final sshServiceProvider =
    ChangeNotifierProvider.autoDispose.family<SshService, String>((ref, profileId) {
  return SshService();
});
