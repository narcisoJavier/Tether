import 'dart:convert';

import 'package:dartssh2/dartssh2.dart' as dartssh2;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';

import '../models/stored_key_pair.dart';
import '../utils/constants.dart';
import '../utils/ssh_key_encoder.dart';

/// Service for generating, importing, storing, and managing SSH keys.
class KeyService extends ChangeNotifier {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(),
  );
  final Box<StoredKeyPair> _keysBox;

  KeyService(this._keysBox);

  /// List all stored key metadata (public info only).
  List<StoredKeyPair> listKeys() {
    return _keysBox.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  /// Generate a new Ed25519 SSH key pair.
  ///
  /// Returns the created [StoredKeyPair] with the public key in OpenSSH format.
  /// The private key is stored securely in the device keystore.
  Future<StoredKeyPair> generateEd25519({required String label}) async {
    final material = SshKeyEncoder.generateEd25519(comment: 'tether-$label');

    // Sanity check: make sure dartssh2 can parse what we produced.
    dartssh2.SSHKeyPair.fromPem(material.privateKeyPem);

    return _storeKey(
      label: label,
      keyType: KeyType.ed25519,
      publicKey: material.publicKey,
      privateKey: material.privateKeyPem,
    );
  }

  /// Import an existing private key in OpenSSH/PEM format.
  ///
  /// Validates the key by parsing it with dartssh2, then derives the public
  /// key string from the parsed key pair. Supports both Ed25519 and RSA keys.
  Future<StoredKeyPair> importKey({
    required String label,
    required String privateKeyPem,
  }) async {
    // Validate + parse via dartssh2 (throws on malformed key).
    final parsedPairs = dartssh2.SSHKeyPair.fromPem(privateKeyPem.trim());
    if (parsedPairs.isEmpty) {
      throw const FormatException('No keys found in the provided PEM.');
    }
    final parsed = parsedPairs.first;

    // dartssh2's SSHKeyPair exposes the public key via toPublicKey().
    final hostKey = parsed.toPublicKey();
    final publicKeyType = parsed.type;
    final publicKey = '$publicKeyType ${base64.encode(hostKey.encode())}';

    // Determine key type from the algorithm identifier.
    final type = parsed.type.toLowerCase();
    final keyType = type.contains('rsa') ? KeyType.rsa : KeyType.ed25519;

    return _storeKey(
      label: label,
      keyType: keyType,
      publicKey: publicKey,
      privateKey: privateKeyPem.trim(),
    );
  }

  /// Internal: store a key pair and persist metadata.
  Future<StoredKeyPair> _storeKey({
    required String label,
    required KeyType keyType,
    required String publicKey,
    required String privateKey,
  }) async {
    final id = DateTime.now().microsecondsSinceEpoch.toString();

    final keyPair = StoredKeyPair(
      id: id,
      label: label,
      keyType: keyType,
      publicKey: publicKey,
    );

    // Store private key in secure storage
    await _secureStorage.write(
      key: keyPair.secureStorageKey,
      value: privateKey,
    );

    // Store public metadata in Hive
    await _keysBox.put(id, keyPair);
    notifyListeners();

    return keyPair;
  }

  /// Retrieve the private key for a given key pair ID.
  Future<String?> getPrivateKey(String keyId) async {
    final current = await _secureStorage.read(
      key: '${AppConstants.secureStoragePrefix}$keyId',
    );
    if (current != null) return current;

    // Preserve access to keys created before the OPA → Tether rename.
    return _secureStorage.read(
      key: '${AppConstants.legacySecureStoragePrefix}$keyId',
    );
  }

  /// Get a specific key by ID.
  StoredKeyPair? getKey(String keyId) {
    return _keysBox.get(keyId);
  }

  /// Delete a stored key pair (both metadata and private key).
  Future<void> deleteKey(String keyId) async {
    await _keysBox.delete(keyId);
    await _secureStorage.delete(
      key: '${AppConstants.secureStoragePrefix}$keyId',
    );
    await _secureStorage.delete(
      key: '${AppConstants.legacySecureStoragePrefix}$keyId',
    );
    notifyListeners();
  }

  /// Update the label of an existing key pair.
  Future<void> updateLabel(String keyId, String newLabel) async {
    final keyPair = _keysBox.get(keyId);
    if (keyPair == null) return;

    final updated = StoredKeyPair(
      id: keyPair.id,
      label: newLabel,
      keyType: keyPair.keyType,
      publicKey: keyPair.publicKey,
      createdAt: keyPair.createdAt,
    );

    await _keysBox.put(keyId, updated);
    notifyListeners();
  }

  /// Check whether the device's secure storage is available.
  Future<bool> isSecureStorageAvailable() async {
    try {
      await _secureStorage.write(key: '_opa_test', value: '1');
      await _secureStorage.delete(key: '_opa_test');
      return true;
    } catch (_) {
      return false;
    }
  }
}

/// Provider for the key management service.
final keyServiceProvider = ChangeNotifierProvider<KeyService>((ref) {
  final keysBox = Hive.box<StoredKeyPair>(AppConstants.keysBox);
  return KeyService(keysBox);
});
