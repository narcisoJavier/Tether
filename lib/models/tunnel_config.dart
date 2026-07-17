import 'package:hive/hive.dart';

/// Type of SSH port forward / tunnel.
enum TunnelType {
  /// Local forwarding: binds a local port, forwards to remote host:port.
  /// SSH equivalent: `ssh -L localPort:remoteHost:remotePort`
  local,

  /// Remote forwarding: binds a port on the remote server, forwards to
  /// a local host:port.
  /// SSH equivalent: `ssh -R remotePort:localHost:localPort`
  remote,

  /// Dynamic SOCKS5 proxy: binds a local port as a SOCKS5 proxy.
  /// SSH equivalent: `ssh -D localPort`
  dynamicSocks5,
}

/// Configuration for a single SSH port-forward tunnel.
///
/// Stored as part of a [ConnectionProfile]'s tunnel list.
/// Serialized by [TunnelConfigAdapter] (manual Hive TypeAdapter, typeId: 3).
class TunnelConfig extends HiveObject {
  /// Unique ID for this tunnel configuration.
  String id;

  /// Human-readable label, e.g. "MySQL local", "Web proxy".
  String label;

  /// The type of forwarding.
  TunnelType type;

  /// The local port to bind (used by local and dynamic forwarding).
  int localPort;

  /// The remote host to forward to (used by local and remote forwarding).
  /// Ignored for dynamic SOCKS5.
  String remoteHost;

  /// The remote port to forward to (used by local and remote forwarding).
  /// Ignored for dynamic SOCKS5.
  int remotePort;

  /// Whether this tunnel should auto-start when the SSH session connects.
  bool enabled;

  TunnelConfig({
    required this.id,
    required this.label,
    required this.type,
    this.localPort = 0,
    this.remoteHost = 'localhost',
    this.remotePort = 0,
    this.enabled = true,
  });

  TunnelConfig copyWith({
    String? label,
    TunnelType? type,
    int? localPort,
    String? remoteHost,
    int? remotePort,
    bool? enabled,
  }) {
    return TunnelConfig(
      id: id,
      label: label ?? this.label,
      type: type ?? this.type,
      localPort: localPort ?? this.localPort,
      remoteHost: remoteHost ?? this.remoteHost,
      remotePort: remotePort ?? this.remotePort,
      enabled: enabled ?? this.enabled,
    );
  }

  /// Short display string, e.g. "L:8080 → db:3306" or "D:1080".
  String get displayString {
    switch (type) {
      case TunnelType.local:
        return 'L:$localPort → $remoteHost:$remotePort';
      case TunnelType.remote:
        return 'R:$remotePort → $remoteHost:$localPort';
      case TunnelType.dynamicSocks5:
        return 'D:$localPort (SOCKS5)';
    }
  }

  /// The type label for UI display.
  String get typeLabel {
    switch (type) {
      case TunnelType.local:
        return 'Local';
      case TunnelType.remote:
        return 'Remote';
      case TunnelType.dynamicSocks5:
        return 'SOCKS5';
    }
  }
}
