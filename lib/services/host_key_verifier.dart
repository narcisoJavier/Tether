import 'dart:async';

import 'package:dartssh2/dartssh2.dart' as dartssh2;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../models/host_key_record.dart';
import '../utils/constants.dart';

/// User decision for a previously unseen SSH host key.
enum HostKeyTrustDecision { reject, trust }

/// Details presented when an endpoint has no trusted host key yet.
class HostKeyChallenge {
  const HostKeyChallenge({required this.presented});

  /// Key presented by the server during key exchange.
  final HostKeyRecord presented;
}

/// Callback that explicitly accepts or rejects an unknown host key.
typedef HostKeyDecisionHandler =
    Future<HostKeyTrustDecision> Function(HostKeyChallenge challenge);

/// Persistent storage contract for SSH host keys.
abstract interface class HostKeyStore {
  /// Returns the trusted key for [endpoint], if one exists.
  Future<HostKeyRecord?> read(HostEndpoint endpoint);

  /// Persists [record] for its canonical endpoint.
  Future<void> write(HostKeyRecord record);
}

/// Hive-backed host-key store.
class HiveHostKeyStore implements HostKeyStore {
  const HiveHostKeyStore(this._box);

  final Box<HostKeyRecord> _box;

  @override
  Future<HostKeyRecord?> read(HostEndpoint endpoint) async =>
      _box.get(endpoint.canonicalKey);

  @override
  Future<void> write(HostKeyRecord record) =>
      _box.put(record.endpoint.canonicalKey, record);
}

/// Verifies SSH host keys before authentication begins.
abstract interface class HostKeyVerifier {
  /// Maximum time allowed for an explicit unknown-key decision.
  Duration get decisionTimeout;

  /// Verifies the presented key and persists explicit first-time trust.
  Future<bool> verify({
    required HostEndpoint endpoint,
    required String algorithm,
    required String fingerprint,
    required HostKeyDecisionHandler onDecision,
  });

  /// Replaces a changed key after a separate explicit user action.
  Future<void> replace(HostKeyChangedException change);
}

/// Persistent verifier that rejects unknown keys unless explicitly trusted.
class PersistentHostKeyVerifier implements HostKeyVerifier {
  PersistentHostKeyVerifier({
    required HostKeyStore store,
    this.decisionTimeout = const Duration(seconds: 90),
    DateTime Function()? clock,
  }) : _store = store,
       _clock = clock ?? DateTime.now;

  final HostKeyStore _store;
  final DateTime Function() _clock;

  @override
  final Duration decisionTimeout;

  @override
  Future<bool> verify({
    required HostEndpoint endpoint,
    required String algorithm,
    required String fingerprint,
    required HostKeyDecisionHandler onDecision,
  }) async {
    final normalizedAlgorithm = algorithm.trim();
    final normalizedFingerprint = fingerprint.trim();
    if (normalizedAlgorithm.isEmpty || normalizedFingerprint.isEmpty) {
      return false;
    }

    final trusted = await _store.read(endpoint);
    final now = _clock().toUtc();
    final presented = HostKeyRecord(
      endpoint: endpoint,
      algorithm: normalizedAlgorithm,
      fingerprint: normalizedFingerprint,
      firstSeen: now,
      lastSeen: now,
    );

    if (trusted != null) {
      if (_matches(trusted, presented)) {
        await _store.write(trusted.copyWith(lastSeen: now));
        return true;
      }
      throw HostKeyChangedException(trusted: trusted, presented: presented);
    }

    HostKeyTrustDecision decision;
    try {
      decision = await onDecision(
        HostKeyChallenge(presented: presented),
      ).timeout(decisionTimeout, onTimeout: () => HostKeyTrustDecision.reject);
    } catch (_) {
      return false;
    }

    if (decision != HostKeyTrustDecision.trust) {
      return false;
    }

    final current = await _store.read(endpoint);
    if (current != null && !_matches(current, presented)) {
      throw HostKeyChangedException(trusted: current, presented: presented);
    }
    if (current != null) {
      await _store.write(current.copyWith(lastSeen: now));
      return true;
    }

    await _store.write(presented);
    return true;
  }

  @override
  Future<void> replace(HostKeyChangedException change) async {
    final current = await _store.read(change.endpoint);
    if (current == null || !_matches(current, change.trusted)) {
      throw StateError(
        'The trusted host key changed again. Reconnect and review it.',
      );
    }
    final now = _clock().toUtc();
    await _store.write(
      HostKeyRecord(
        endpoint: change.endpoint,
        algorithm: change.presented.algorithm,
        fingerprint: change.presented.fingerprint,
        firstSeen: now,
        lastSeen: now,
      ),
    );
  }

  bool _matches(HostKeyRecord left, HostKeyRecord right) =>
      left.algorithm == right.algorithm &&
      left.fingerprint == right.fingerprint;
}

/// Error raised when a trusted endpoint presents a different host key.
class HostKeyChangedException implements Exception, dartssh2.SSHError {
  HostKeyChangedException({required this.trusted, required this.presented}) {
    if (trusted.endpoint != presented.endpoint) {
      throw ArgumentError(
        'Trusted and presented host keys must use the same endpoint.',
      );
    }
  }

  /// Previously trusted key.
  final HostKeyRecord trusted;

  /// Newly presented, untrusted key.
  final HostKeyRecord presented;

  /// Endpoint whose key changed.
  HostEndpoint get endpoint => trusted.endpoint;

  @override
  String toString() =>
      'SSH host key changed for ${endpoint.displayName}. '
      'Expected ${trusted.algorithm} ${trusted.fingerprint}, received '
      '${presented.algorithm} ${presented.fingerprint}. '
      'The connection was blocked.';
}

/// Provider for the persisted host-key store.
final hostKeyStoreProvider = Provider<HostKeyStore>((ref) {
  final box = Hive.box<HostKeyRecord>(AppConstants.hostKeysBox);
  return HiveHostKeyStore(box);
});

/// Provider for SSH host-key verification.
final hostKeyVerifierProvider = Provider<HostKeyVerifier>((ref) {
  return PersistentHostKeyVerifier(store: ref.watch(hostKeyStoreProvider));
});
