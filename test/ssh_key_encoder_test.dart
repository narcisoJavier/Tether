import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tether/utils/ssh_key_encoder.dart';

void main() {
  group('SshKeyEncoder.generateEd25519', () {
    test('returns non-empty public and private key strings', () {
      final material = SshKeyEncoder.generateEd25519(comment: 'test-key');

      expect(material.publicKey, isNotEmpty);
      expect(material.privateKeyPem, isNotEmpty);
    });

    test('public key has correct OpenSSH single-line format', () {
      final material = SshKeyEncoder.generateEd25519(comment: 'my-comment');

      // Format: "ssh-ed25519 <base64> <comment>"
      expect(material.publicKey, startsWith('ssh-ed25519 '));
      expect(material.publicKey, endsWith(' my-comment'));

      final parts = material.publicKey.split(' ');
      expect(parts.length, 3);
      expect(parts[0], 'ssh-ed25519');
      expect(parts[2], 'my-comment');
    });

    test('public key base64 decodes to correct ed25519 wire format', () {
      final material = SshKeyEncoder.generateEd25519();

      final parts = material.publicKey.split(' ');
      final blob = base64.decode(parts[1]);

      // Wire format: uint32 len + "ssh-ed25519" + uint32 len + 32-byte pubkey
      var offset = 0;
      final typeLen = _readUint32(blob, offset);
      offset += 4;
      final typeStr = utf8.decode(blob.sublist(offset, offset + typeLen));
      offset += typeLen;
      final keyLen = _readUint32(blob, offset);
      offset += 4;
      final publicKey = blob.sublist(offset, offset + keyLen);

      expect(typeStr, 'ssh-ed25519');
      expect(keyLen, 32); // ed25519 public keys are exactly 32 bytes
      expect(publicKey.length, 32);
    });

    test('private key PEM has correct OpenSSH headers', () {
      final material = SshKeyEncoder.generateEd25519();

      expect(
        material.privateKeyPem,
        startsWith('-----BEGIN OPENSSH PRIVATE KEY-----\n'),
      );
      expect(
        material.privateKeyPem.trim(),
        endsWith('-----END OPENSSH PRIVATE KEY-----'),
      );
    });

    test('private key PEM body is wrapped at <= 70 chars per line', () {
      final material = SshKeyEncoder.generateEd25519();

      final lines = material.privateKeyPem
          .split('\n')
          .where((l) =>
              !l.startsWith('-----') && l.trim().isNotEmpty)
          .toList();

      expect(lines, isNotEmpty);
      for (final line in lines) {
        expect(line.length, lessThanOrEqualTo(70),
            reason: 'PEM line exceeds 70 chars: "$line"');
      }
    });

    test('private key PEM decodes to valid outer structure', () {
      final material = SshKeyEncoder.generateEd25519();

      final b64Body = material.privateKeyPem
          .split('\n')
          .where((l) => !l.startsWith('-----'))
          .join();
      final outer = base64.decode(b64Body);

      // Must start with "openssh-key-v1\0" (15 chars + null)
      final magic = utf8.decode(outer.sublist(0, 15));
      expect(magic, 'openssh-key-v1');
      expect(outer[15], 0); // null terminator

      var offset = 16;
      final cipherLen = _readUint32(outer, offset);
      offset += 4;
      final cipher = utf8.decode(outer.sublist(offset, offset + cipherLen));
      offset += cipherLen;
      expect(cipher, 'none'); // unencrypted

      final kdfLen = _readUint32(outer, offset);
      offset += 4;
      final kdf = utf8.decode(outer.sublist(offset, offset + kdfLen));
      offset += kdfLen;
      expect(kdf, 'none');

      // kdf options (empty string)
      final kdfOptsLen = _readUint32(outer, offset);
      offset += 4;
      expect(kdfOptsLen, 0);

      // number of keys
      final numKeys = _readUint32(outer, offset);
      offset += 4;
      expect(numKeys, 1);
    });

    test('each generation produces a unique key (randomness)', () {
      final a = SshKeyEncoder.generateEd25519();
      final b = SshKeyEncoder.generateEd25519();

      expect(a.publicKey, isNot(equals(b.publicKey)));
      expect(a.privateKeyPem, isNot(equals(b.privateKeyPem)));
    });

    test('public and private keys correspond to the same keypair', () {
      final material = SshKeyEncoder.generateEd25519(comment: 'verify');

      // Extract the 32-byte public key from the public key string.
      final pubParts = material.publicKey.split(' ');
      final pubBlob = base64.decode(pubParts[1]);
      // skip type string (uint32 len + "ssh-ed25519")
      var offset = 4 + 11;
      final pubLen = _readUint32(pubBlob, offset);
      offset += 4;
      final pubFromPublic = pubBlob.sublist(offset, offset + pubLen);

      // Decode the private key PEM and extract the embedded public key
      // from the private section (seed 32 bytes || public 32 bytes).
      final b64Body = material.privateKeyPem
          .split('\n')
          .where((l) => !l.startsWith('-----'))
          .join();
      final outer = base64.decode(b64Body);
      var o = 16;
      o += 4 + 4; // cipher string len + "none"
      o += 4 + 4; // kdf string len + "none"
      o += 4; // kdf options empty
      o += 4; // num keys
      // public key blob
      final pubBlobLen = _readUint32(outer, o);
      o += 4;
      // skip the public blob
      o += pubBlobLen;
      // private section
      final privSecLen = _readUint32(outer, o);
      o += 4;
      final privSection = outer.sublist(o, o + privSecLen);
      // privSection: checkint(4) + checkint(4) + type string + pub string +
      //              priv string(seed32||pub32) + comment + padding
      // skip 2 checkints
      var p = 8;
      p += 4 + 11; // type string
      p += 4 + 32; // public key string
      final privStrLen = _readUint32(privSection, p);
      p += 4;
      // The last 32 bytes of the 64-byte private string are the public key.
      final pubFromPrivate =
          privSection.sublist(p + privStrLen - 32, p + privStrLen);

      expect(pubFromPrivate, equals(pubFromPublic),
          reason: 'Public key in PEM must match the public key string');
      expect(privStrLen, 64); // ed25519: seed(32) + pub(32)
    });

    test('uses provided comment in public key', () {
      final material =
          SshKeyEncoder.generateEd25519(comment: 'opa-custom-label');
      expect(material.publicKey, endsWith(' opa-custom-label'));
    });

    test('handles empty comment', () {
      final material = SshKeyEncoder.generateEd25519(comment: '');
      // Should end with a trailing space + empty
      expect(material.publicKey, endsWith(' '));
    });

    test('handles unicode comment', () {
      final material = SshKeyEncoder.generateEd25519(comment: 'tëst-kéy 🔑');
      expect(material.publicKey, contains('tëst-kéy 🔑'));
    });
  });
}

/// Read a big-endian uint32 from [data] at [offset].
int _readUint32(List<int> data, int offset) {
  return (data[offset] << 24) |
      (data[offset + 1] << 16) |
      (data[offset + 2] << 8) |
      data[offset + 3];
}
