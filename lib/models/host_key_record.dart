import 'dart:io';

import 'package:hive/hive.dart';

import 'connection_profile.dart';

/// Canonical identity of an SSH server endpoint.
class HostEndpoint {
  HostEndpoint({
    required String host,
    required this.port,
    required this.connectionMethod,
  }) : host = normalizeHost(host) {
    if (this.host.isEmpty) {
      throw ArgumentError.value(host, 'host', 'Host must not be empty.');
    }
    if (port < 1 || port > 65535) {
      throw RangeError.range(port, 1, 65535, 'port');
    }
  }

  /// Creates an endpoint from a saved connection profile.
  factory HostEndpoint.fromProfile(ConnectionProfile profile) => HostEndpoint(
    host: profile.host,
    port: profile.port,
    connectionMethod: profile.connectionMethod,
  );

  /// Normalized lowercase host without IPv6 brackets or a DNS root dot.
  final String host;

  /// SSH port.
  final int port;

  /// Network path used to reach the host.
  final ConnectionMethod connectionMethod;

  /// Stable Hive key for this endpoint.
  String get canonicalKey =>
      '${connectionMethod.name}|${Uri.encodeComponent(host)}|$port';

  /// Human-readable endpoint including its network path.
  String get displayName {
    final displayHost = host.contains(':') ? '[$host]' : host;
    return '${connectionMethod.name}://$displayHost:$port';
  }

  /// Applies canonical host normalization.
  static String normalizeHost(String value) {
    var result = value.trim().toLowerCase();
    if (result.startsWith('[') && result.endsWith(']')) {
      result = result.substring(1, result.length - 1).trim();
    }
    while (result.endsWith('.')) {
      result = result.substring(0, result.length - 1);
    }
    final parsed = InternetAddress.tryParse(result);
    if (parsed == null) return result;
    if (parsed.type == InternetAddressType.IPv4) return parsed.address;
    return _canonicalizeIpv6(parsed.rawAddress);
  }

  @override
  bool operator ==(Object other) =>
      other is HostEndpoint &&
      other.host == host &&
      other.port == port &&
      other.connectionMethod == connectionMethod;

  @override
  int get hashCode => Object.hash(host, port, connectionMethod);

  @override
  String toString() => displayName;
}

String _canonicalizeIpv6(List<int> bytes) {
  final groups = List<int>.generate(
    8,
    (index) => (bytes[index * 2] << 8) | bytes[index * 2 + 1],
  );
  var bestStart = -1;
  var bestLength = 0;
  var runStart = -1;
  for (var index = 0; index <= groups.length; index++) {
    final isZero = index < groups.length && groups[index] == 0;
    if (isZero && runStart < 0) {
      runStart = index;
    } else if (!isZero && runStart >= 0) {
      final length = index - runStart;
      if (length > bestLength && length >= 2) {
        bestStart = runStart;
        bestLength = length;
      }
      runStart = -1;
    }
  }
  if (bestStart < 0) {
    return groups.map((group) => group.toRadixString(16)).join(':');
  }

  final before = groups
      .take(bestStart)
      .map((group) => group.toRadixString(16))
      .join(':');
  final after = groups
      .skip(bestStart + bestLength)
      .map((group) => group.toRadixString(16))
      .join(':');
  if (before.isEmpty && after.isEmpty) return '::';
  if (before.isEmpty) return '::$after';
  if (after.isEmpty) return '$before::';
  return '$before::$after';
}

/// Persisted SSH host-key trust record.
class HostKeyRecord extends HiveObject {
  HostKeyRecord({
    required this.endpoint,
    required this.algorithm,
    required this.fingerprint,
    required this.firstSeen,
    required this.lastSeen,
  });

  /// Canonical server endpoint associated with this key.
  final HostEndpoint endpoint;

  /// SSH host-key algorithm, such as `ssh-ed25519`.
  final String algorithm;

  /// OpenSSH-style SHA-256 fingerprint.
  final String fingerprint;

  /// Time this key was first explicitly trusted.
  final DateTime firstSeen;

  /// Time this trusted key was most recently observed.
  final DateTime lastSeen;

  /// Returns a copy with selected fields replaced.
  HostKeyRecord copyWith({
    String? algorithm,
    String? fingerprint,
    DateTime? firstSeen,
    DateTime? lastSeen,
  }) => HostKeyRecord(
    endpoint: endpoint,
    algorithm: algorithm ?? this.algorithm,
    fingerprint: fingerprint ?? this.fingerprint,
    firstSeen: firstSeen ?? this.firstSeen,
    lastSeen: lastSeen ?? this.lastSeen,
  );
}
