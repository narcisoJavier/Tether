import 'package:hive/hive.dart';

import '../utils/constants.dart';

/// Supported SSH key types.
enum KeyType { ed25519, rsa }

/// Metadata for a stored SSH key pair.
///
/// The private key itself is stored in flutter_secure_storage (not Hive).
/// This model stores the public key for display/copy and references the
/// secure storage slot.
///
/// Serialized by [StoredKeyPairAdapter] (manual Hive TypeAdapter).
///
/// NOTE: Named `StoredKeyPair` (not `SSHKeyPair`) to avoid a name collision
/// with dartssh2's `SSHKeyPair` class, which we also import in key_service
/// and ssh_service.
class StoredKeyPair extends HiveObject {
  String id;
  String label;
  KeyType keyType;
  String publicKey; // OpenSSH format, e.g. "ssh-ed25519 AAAAC3NzaC1l..."
  DateTime createdAt;

  StoredKeyPair({
    required this.id,
    required this.label,
    required this.keyType,
    required this.publicKey,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// The secure storage key used to look up the private key.
  String get secureStorageKey => '${AppConstants.secureStoragePrefix}$id';

  /// Short fingerprint-like label, e.g. "My Key (ed25519)"
  String get fingerprint => '$label (${keyType.name})';

  /// Extract just the key comment/type for display.
  String get keyTypeLabel => keyType == KeyType.ed25519 ? 'Ed25519' : 'RSA';
}
