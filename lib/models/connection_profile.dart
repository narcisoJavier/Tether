import 'package:hive/hive.dart';

import 'tunnel_config.dart';

/// Authentication method for an SSH connection.
///
/// Indexed values are used by the manual Hive adapter in
/// `lib/services/hive_adapters.dart` (do NOT use code-gen annotations here —
/// those would require build_runner and a generated .g.dart part file).
enum AuthType {
  password,
  publicKey,
  passwordAndPublicKey,
}

/// How the connection reaches the remote host.
enum ConnectionMethod {
  /// Direct TCP connection (DNS hostname or public IP).
  direct,
  /// Via an embedded Tailscale node over WireGuard.
  tailscale,
}

/// A saved SSH connection profile.
///
/// Serialized by [ConnectionProfileAdapter] (manual Hive TypeAdapter).
/// Extending [HiveObject] gives us `save()`/`delete()` helpers, but no
/// code-gen annotations are used.
class ConnectionProfile extends HiveObject {
  String id;
  String label;
  String host;
  int port;
  String username;
  AuthType authType;
  String? password; // null for key-only auth
  String? keyId; // Reference to SSHKeyPair.id; null for password-only auth
  int colorIndex; // Index into a predefined color palette
  DateTime createdAt;
  DateTime updatedAt;
  bool lastConnectionSuccess; // Green/red indicator on home screen
  ConnectionMethod connectionMethod; // How to reach this host
  List<TunnelConfig> tunnels; // Port forwarding configurations
  String? environment; // 'Prod', 'Staging', or 'HomeLab'

  ConnectionProfile({
    required this.id,
    required this.label,
    required this.host,
    required this.port,
    required this.username,
    required this.authType,
    this.password,
    this.keyId,
    this.colorIndex = 0,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.lastConnectionSuccess = false,
    this.connectionMethod = ConnectionMethod.direct,
    List<TunnelConfig>? tunnels,
    this.environment,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now(),
        tunnels = tunnels ?? [];

  ConnectionProfile copyWith({
    String? label,
    String? host,
    int? port,
    String? username,
    AuthType? authType,
    String? password,
    String? keyId,
    int? colorIndex,
    bool? lastConnectionSuccess,
    ConnectionMethod? connectionMethod,
    List<TunnelConfig>? tunnels,
    String? environment,
  }) {
    return ConnectionProfile(
      id: id,
      label: label ?? this.label,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      authType: authType ?? this.authType,
      password: password ?? this.password,
      keyId: keyId ?? this.keyId,
      colorIndex: colorIndex ?? this.colorIndex,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      lastConnectionSuccess:
          lastConnectionSuccess ?? this.lastConnectionSuccess,
      connectionMethod: connectionMethod ?? this.connectionMethod,
      tunnels: tunnels ?? this.tunnels,
      environment: environment ?? this.environment,
    );
  }

  /// Display-friendly representation, e.g. "user@host:22"
  String get displayName => '$username@$host';

  /// Short label for chips/cards, e.g. "My PC"
  String get shortLabel => label.isNotEmpty ? label : displayName;

  /// Effective environment tag with fallback inference.
  String get effectiveEnvironment {
    if (environment != null && environment!.isNotEmpty) {
      return environment!;
    }
    final l = label.toLowerCase();
    final h = host.toLowerCase();
    if (l.contains('stg') || l.contains('stage') || h.contains('stg')) {
      return 'Staging';
    }
    if (l.contains('home') || l.contains('lab') || h.contains('home')) {
      return 'HomeLab';
    }
    return 'Prod';
  }
}
