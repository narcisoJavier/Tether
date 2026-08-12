import 'dart:convert';
import 'dart:typed_data';

import 'package:pinenacl/ed25519.dart' as nacl;

/// Helper for generating and encoding Ed25519 SSH keys.
///
/// We build the OpenSSH wire format by hand rather than relying on the
/// `ssh_key` package's higher-level object API, which has a more complex
/// surface that varies between versions. The binary format is stable and
/// well-documented (PROTOCOL.key in the OpenSSH source).
class SshKeyEncoder {
  SshKeyEncoder._();

  /// Generate a fresh Ed25519 key pair and return both the OpenSSH-format
  /// private key PEM and the single-line public key string.
  static SshKeyMaterial generateEd25519({String comment = 'tether'}) {
    // pinenacl's `Keypair()` generates an X25519 (encryption) keypair by
    // default, NOT Ed25519. For SSH ed25519 keys we must use the signing
    // key directly: `SigningKey()` generates a random Ed25519 key.
    // SigningKey is a 64-byte Uint8List (32-byte seed + 32-byte public key,
    // the "expanded" form). We need the 32-byte seed for SSH serialization.
    final signingKey = nacl.SigningKey.generate();
    final seedBytes = Uint8List.fromList(signingKey.seed);
    final publicKeyBytes = Uint8List.fromList(signingKey.verifyKey);

    final publicKey = _encodePublicKey(publicKeyBytes, comment);
    final privateKeyPem = _encodePrivateKeyPem(
      publicKeyBytes,
      seedBytes,
      comment,
    );

    return SshKeyMaterial(publicKey: publicKey, privateKeyPem: privateKeyPem);
  }

  /// Build the single-line OpenSSH public key string:
  ///   `ssh-ed25519 <base64> <comment>`
  static String _encodePublicKey(Uint8List publicKeyBytes, String comment) {
    final blob = <int>[];
    // key type string
    _writeString(blob, 'ssh-ed25519');
    // public key bytes
    _writeBytes(blob, publicKeyBytes);

    final b64 = base64.encode(blob);
    return 'ssh-ed25519 $b64 $comment';
  }

  /// Build an OpenSSH-format (v1) private key PEM from an Ed25519
  /// seed + public key. This is the format produced by
  /// `ssh-keygen -t ed25519` and understood by dartssh2's fromPem().
  static String _encodePrivateKeyPem(
    Uint8List publicKeyBytes,
    Uint8List seedBytes,
    String comment,
  ) {
    // The private key blob contains 2n keys. For a single key:
    //   checkint (random, twice)
    //   keytype string
    //   public key string
    //   private key string (here: seed + public, 64 bytes for ed25519)
    //   comment string
    //   padding bytes 1,2,3,...
    final checkint = DateTime.now().microsecondsSinceEpoch & 0xFFFFFFFF;
    final blob = <int>[];
    _writeUint32(blob, checkint);
    _writeUint32(blob, checkint);
    _writeString(blob, 'ssh-ed25519');
    _writeBytes(blob, publicKeyBytes);
    // ed25519 private key section = seed (32) || public (32) = 64 bytes
    final privSection = <int>[...seedBytes, ...publicKeyBytes];
    _writeBytes(blob, privSection);
    _writeBytes(blob, utf8.encode(comment));

    // padding
    var pad = 1;
    while (blob.length % 8 != 0) {
      blob.add(pad++);
    }

    final plaintext = Uint8List.fromList(blob);

    // Outer unencrypted structure:
    //   "openssh-key-v1\0"
    //   ciphername ("none")
    //   kdfname ("none")
    //   kdf options (empty string)
    //   number of keys (1)
    //   public key blob
    //   encrypted private key blob
    final outer = <int>[];
    outer.addAll(utf8.encode('openssh-key-v10'));
    _writeString(outer, 'none'); // ciphername
    _writeString(outer, 'none'); // kdfname
    _writeBytes(outer, []); // kdf options
    _writeUint32(outer, 1); // number of keys

    // public key blob (with type + key)
    final pubBlob = <int>[];
    _writeString(pubBlob, 'ssh-ed25519');
    _writeBytes(pubBlob, publicKeyBytes);
    _writeBytes(outer, pubBlob);

    // private key section
    _writeBytes(outer, plaintext);

    final b64 = base64.encode(outer);
    // wrap at 70 chars like ssh-keygen
    final lines = <String>[];
    for (var i = 0; i < b64.length; i += 70) {
      lines.add(b64.substring(i, i + 70 > b64.length ? b64.length : i + 70));
    }

    return '-----BEGIN OPENSSH PRIVATE KEY-----\n'
        '${lines.join('\n')}\n'
        '-----END OPENSSH PRIVATE KEY-----\n';
  }

  /// Write an SSH wire-format string (uint32 length prefix + bytes).
  static void _writeString(List<int> out, String value) {
    _writeBytes(out, utf8.encode(value));
  }

  /// Write raw bytes with a uint32 length prefix.
  static void _writeBytes(List<int> out, List<int> bytes) {
    _writeUint32(out, bytes.length);
    out.addAll(bytes);
  }

  static void _writeUint32(List<int> out, int value) {
    out.add((value >> 24) & 0xFF);
    out.add((value >> 16) & 0xFF);
    out.add((value >> 8) & 0xFF);
    out.add(value & 0xFF);
  }
}

/// Output of key generation: both halves of the key pair as strings.
class SshKeyMaterial {
  const SshKeyMaterial({required this.publicKey, required this.privateKeyPem});

  /// Single-line OpenSSH public key (e.g. `ssh-ed25519 AAAA... tether`).
  final String publicKey;

  /// OpenSSH-format private key PEM.
  final String privateKeyPem;
}
