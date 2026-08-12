import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:tailscale/tailscale.dart';

import '../utils/constants.dart';

/// Base exception for all Tailscale service errors in Tether.
class TailscaleException implements Exception {
  final String message;
  final String code;
  final Object? cause;
  const TailscaleException(this.message, this.code, {this.cause});
  @override
  String toString() => 'TailscaleException[$code]: $message';
}

/// Thrown when the Tailscale TCP dial fails (node not reachable).
class TailscaleDialException extends TailscaleException {
  const TailscaleDialException(String message, {Object? cause})
    : super(message, 'DIAL', cause: cause);
}

/// Thrown when the node cannot connect to the tailnet.
class TailscaleConnectException extends TailscaleException {
  const TailscaleConnectException(String message, {Object? cause})
    : super(message, 'CONNECT', cause: cause);
}

/// Thrown when the auth key is missing or invalid.
class TailscaleAuthException extends TailscaleException {
  const TailscaleAuthException(String message, {Object? cause})
    : super(message, 'AUTH', cause: cause);
}

/// Service wrapping an embedded Tailscale node via `package:tailscale`.
///
/// The app joins the user's tailnet as its own node — no separate Tailscale
/// app needed. Provides lifecycle management (init, up, down, logout), TCP
/// dial for SSH routing through the WireGuard tunnel, and node discovery.
class TailscaleService {
  Completer<void>? _upMutex;
  bool _hasConnected = false;
  bool _initialized = false;

  final FlutterSecureStorage _secureStorage;

  TailscaleService({FlutterSecureStorage? secureStorage})
    : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  // --- Guard helpers ---

  void _requireInit() {
    if (!_initialized) {
      throw StateError(
        'TailscaleService not initialized. Call initialize() first.',
      );
    }
  }

  // --- Lifecycle ---

  /// Whether [initialize] has been called.
  bool get isInitialized => _initialized;

  /// The Tailscale singleton — safe to access after [initialize].
  Tailscale get instance {
    _requireInit();
    return Tailscale.instance;
  }

  /// Current node status from the embedded runtime.
  ///
  /// Returns [TailscaleStatus.stopped] before [up] is called (or after
  /// [down]). Throws if [initialize] was not called.
  Future<TailscaleStatus> status() async {
    _requireInit();
    return Tailscale.instance.status();
  }

  // --- Stream passthroughs ---

  /// Stream of [NodeState] changes from the embedded node.
  ///
  /// Available after [initialize]. Consecutive duplicate states are filtered
  /// (except [NodeState.needsLogin], which can re-fire with a fresh auth URL).
  Stream<NodeState> get onStateChange {
    _requireInit();
    return Tailscale.instance.onStateChange;
  }

  /// Stream of background runtime errors pushed from Go.
  Stream<TailscaleRuntimeError> get onError {
    _requireInit();
    return Tailscale.instance.onError;
  }

  /// Stream of node inventory changes (nodes joined, left, went online/offline).
  Stream<List<TailscaleNode>> get onNodeChanges {
    _requireInit();
    return Tailscale.instance.onNodeChanges;
  }

  // --- Init / Up / Down / Logout ---

  /// Initialize the Tailscale library. Call once at app startup.
  ///
  /// [stateDir] must be an app-private directory that persists across
  /// restarts. The node's WireGuard key is stored here — do NOT back it up
  /// to the cloud.
  void initialize(String stateDir) {
    if (_initialized) return;
    Tailscale.init(stateDir: stateDir, logLevel: TailscaleLogLevel.silent);
    _initialized = true;

    debugPrint('[Tailscale] initialized (stateDir: $stateDir)');
  }

  /// Bring the embedded node up and connect to the tailnet.
  ///
  /// On first launch, [authKey] is required (generate from Tailscale admin
  /// console). Subsequent launches reconnect using persisted credentials.
  /// Set [ephemeral] to register as a short-lived node (auto-removed when
  /// inactive — suitable for mobile apps).
  Future<TailscaleStatus> up({
    String? authKey,
    bool ephemeral = false,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    _requireInit();
    final status = await Tailscale.instance.up(
      hostname: 'tether-phone',
      authKey: authKey,
      ephemeral: ephemeral,
      timeout: timeout,
    );
    _hasConnected = true;
    debugPrint(
      '[Tailscale] up: state=${status.state}, '
      'ipv4=${status.ipv4}, nodeId=${status.stableNodeId}',
    );
    return status;
  }

  /// Disconnect from the tailnet, preserving credentials for reconnection.
  Future<void> down() async {
    if (!_initialized) return;
    await Tailscale.instance.down();
    debugPrint('[Tailscale] down');
  }

  /// Log out and clear persisted credentials. The node is deregistered.
  Future<void> logout() async {
    if (!_initialized) return;
    await Tailscale.instance.logout();
    await _secureStorage.delete(key: AppConstants.tailscaleAuthKeyKey);
    debugPrint('[Tailscale] logged out');
  }

  // --- TCP dial (for SSH) ---

  /// Ensure the tailnet node is up before attempting to dial.
  Future<void> _ensureUp({Duration? timeout}) async {
    _requireInit();
    if (_upMutex != null) return _upMutex!.future;
    try {
      final st = await Tailscale.instance.status();
      if (st.state == NodeState.running) return;
    } catch (_) {}
    _upMutex = Completer<void>();
    try {
      if (_hasConnected) {
        await up(timeout: timeout ?? const Duration(seconds: 30));
      } else {
        final key = await readAuthKey();
        if (key == null || key.isEmpty) {
          throw const TailscaleAuthException(
            'No auth key configured. Add one in Profile > Tailscale.',
          );
        }
        await up(authKey: key, timeout: timeout ?? const Duration(seconds: 30));
      }
    } finally {
      if (!_upMutex!.isCompleted) _upMutex!.complete();
      _upMutex = null;
    }
  }

  Future<TailscaleConnection> dial(
    String address,
    int port, {
    Duration? timeout,
  }) async {
    await _ensureUp(timeout: timeout);
    try {
      return await Tailscale.instance.tcp.dial(address, port, timeout: timeout);
    } catch (e) {
      throw TailscaleDialException(
        'Could not reach $address:$port over tailnet. '
        'Verify the remote host is online and connected to the tailnet.',
        cause: e is Exception ? e : null,
      );
    }
  }

  // --- Node discovery ---

  /// List all nodes visible on the tailnet.
  Future<List<TailscaleNode>> listNodes() async {
    _requireInit();
    return Tailscale.instance.nodes();
  }

  /// Get the identity of a tailnet node by its Tailscale IP.
  Future<TailscaleNodeIdentity?> whois(String ip) async {
    _requireInit();
    return Tailscale.instance.whois(ip);
  }

  // --- Auth key management ---

  /// Persist an auth key in secure storage.
  Future<void> storeAuthKey(String key) async {
    await _secureStorage.write(
      key: AppConstants.tailscaleAuthKeyKey,
      value: key,
    );
  }

  /// Read the stored auth key, or null if none.
  Future<String?> readAuthKey() async {
    return _secureStorage.read(key: AppConstants.tailscaleAuthKeyKey);
  }
}
