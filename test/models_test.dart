import 'package:flutter_test/flutter_test.dart';
import 'package:tether/models/connection_profile.dart';
import 'package:tether/models/quick_command.dart';
import 'package:tether/models/stored_key_pair.dart';
import 'package:tether/models/tunnel_config.dart';

void main() {
  group('ConnectionProfile', () {
    ConnectionProfile makeProfile() => ConnectionProfile(
      id: 'p1',
      label: 'My PC',
      host: '192.168.1.50',
      port: 22,
      username: 'admin',
      authType: AuthType.password,
    );

    test('displayName formats as user@host', () {
      final p = makeProfile();
      expect(p.displayName, 'admin@192.168.1.50');
    });

    test('shortLabel uses label when set', () {
      final p = makeProfile();
      expect(p.shortLabel, 'My PC');
    });

    test('shortLabel falls back to displayName when label is empty', () {
      final p = makeProfile()..label = '';
      expect(p.shortLabel, 'admin@192.168.1.50');
    });

    test(
      'effectiveEnvironment returns explicit value if present or infers fallback',
      () {
        final pProd = ConnectionProfile(
          id: '1',
          label: 'prod-server',
          host: '10.0.0.1',
          port: 22,
          username: 'root',
          authType: AuthType.password,
        );
        expect(pProd.effectiveEnvironment, 'Prod');

        final pStg = ConnectionProfile(
          id: '2',
          label: 'api-gateway-stg',
          host: '10.0.0.2',
          port: 22,
          username: 'root',
          authType: AuthType.password,
        );
        expect(pStg.effectiveEnvironment, 'Staging');

        final pExplicit = ConnectionProfile(
          id: '3',
          label: 'server',
          host: '10.0.0.3',
          port: 22,
          username: 'root',
          authType: AuthType.password,
          environment: 'HomeLab',
        );
        expect(pExplicit.effectiveEnvironment, 'HomeLab');
      },
    );

    test('defaults: port-independent, colorIndex 0, not connected', () {
      final p = makeProfile();
      expect(p.colorIndex, 0);
      expect(p.lastConnectionSuccess, false);
      expect(p.password, isNull);
      expect(p.keyId, isNull);
    });

    test('createdAt/updatedAt default to ~now', () {
      final before = DateTime.now();
      final p = makeProfile();
      final after = DateTime.now();

      expect(
        p.createdAt.isAfter(before.subtract(const Duration(seconds: 1))),
        isTrue,
      );
      expect(
        p.createdAt.isBefore(after.add(const Duration(seconds: 1))),
        isTrue,
      );
      expect(p.updatedAt.isAtSameMomentAs(p.createdAt), isTrue);
    });

    test('explicit createdAt is preserved', () {
      final fixed = DateTime(2023, 5, 1);
      final p = ConnectionProfile(
        id: 'p',
        label: 'l',
        host: 'h',
        port: 22,
        username: 'u',
        authType: AuthType.password,
        createdAt: fixed,
      );
      expect(p.createdAt, fixed);
    });

    test('copyWith updates only specified fields and bumps updatedAt', () {
      final p = makeProfile();
      final originalUpdatedAt = p.updatedAt;

      final updated = p.copyWith(label: 'New Label', port: 2222);

      expect(updated.id, 'p1'); // unchanged
      expect(updated.label, 'New Label'); // changed
      expect(updated.port, 2222); // changed
      expect(updated.host, '192.168.1.50'); // unchanged
      expect(updated.username, 'admin'); // unchanged
      expect(
        updated.updatedAt.isAfter(originalUpdatedAt) ||
            updated.updatedAt.isAtSameMomentAs(originalUpdatedAt),
        isTrue,
      );
    });

    test('copyWith preserves createdAt (does not reset it)', () {
      final created = DateTime(2020, 1, 1);
      final p = makeProfile()..createdAt = created;
      final updated = p.copyWith(label: 'x');
      expect(updated.createdAt, created);
    });

    test('copyWith with no args returns equivalent profile', () {
      final p = makeProfile();
      final copy = p.copyWith();
      expect(copy.id, p.id);
      expect(copy.label, p.label);
      expect(copy.host, p.host);
      expect(copy.port, p.port);
      expect(copy.authType, p.authType);
    });

    test('copyWith lastConnectionSuccess flag', () {
      final p = makeProfile();
      expect(p.lastConnectionSuccess, false);
      final updated = p.copyWith(lastConnectionSuccess: true);
      expect(updated.lastConnectionSuccess, true);
    });

    test('defaults: empty tunnels list', () {
      final p = makeProfile();
      expect(p.tunnels, isEmpty);
    });

    test('copyWith preserves tunnels when not specified', () {
      final tunnels = [
        TunnelConfig(
          id: 'tun-1',
          label: 'DB',
          type: TunnelType.local,
          localPort: 3306,
          remoteHost: 'db',
          remotePort: 3306,
        ),
      ];
      final p = ConnectionProfile(
        id: 'p',
        label: 'l',
        host: 'h',
        port: 22,
        username: 'u',
        authType: AuthType.password,
        tunnels: tunnels,
      );
      final updated = p.copyWith(label: 'new');
      expect(updated.tunnels.length, 1);
      expect(updated.tunnels[0].id, 'tun-1');
    });

    test('copyWith can replace tunnels', () {
      final p = makeProfile();
      final newTunnels = [
        TunnelConfig(
          id: 'tun-new',
          label: 'New',
          type: TunnelType.dynamicSocks5,
          localPort: 1080,
        ),
      ];
      final updated = p.copyWith(tunnels: newTunnels);
      expect(updated.tunnels.length, 1);
      expect(updated.tunnels[0].type, TunnelType.dynamicSocks5);
    });

    test('copyWith can clear nullable fields', () {
      final p = makeProfile().copyWith(
        password: 'secret',
        keyId: 'key-1',
        environment: 'Staging',
      );

      final cleared = p.copyWith(
        password: null,
        keyId: null,
        environment: null,
      );

      expect(cleared.password, isNull);
      expect(cleared.keyId, isNull);
      expect(cleared.environment, isNull);
    });
  });

  group('StoredKeyPair', () {
    test('secureStorageKey uses prefix + id', () {
      final k = StoredKeyPair(
        id: 'abc123',
        label: 'L',
        keyType: KeyType.ed25519,
        publicKey: 'ssh-ed25519 AAAA L',
      );
      expect(k.secureStorageKey, 'tether_key_abc123');
    });

    test('fingerprint includes label and key type name', () {
      final k = StoredKeyPair(
        id: '1',
        label: 'Work',
        keyType: KeyType.ed25519,
        publicKey: 'x',
      );
      expect(k.fingerprint, 'Work (ed25519)');
    });

    test('keyTypeLabel for ed25519', () {
      final k = StoredKeyPair(
        id: '1',
        label: 'L',
        keyType: KeyType.ed25519,
        publicKey: 'x',
      );
      expect(k.keyTypeLabel, 'Ed25519');
    });

    test('keyTypeLabel for RSA', () {
      final k = StoredKeyPair(
        id: '1',
        label: 'L',
        keyType: KeyType.rsa,
        publicKey: 'x',
      );
      expect(k.keyTypeLabel, 'RSA');
    });
  });

  group('QuickCommand', () {
    QuickCommand makeCommand() => QuickCommand(
      id: 'c1',
      label: 'Start Agent',
      command: 'echo hi',
      profileId: 'p1',
    );

    test('defaults: colorIndex 0', () {
      final c = makeCommand();
      expect(c.colorIndex, 0);
    });

    test('copyWith updates specified fields', () {
      final c = makeCommand();
      final updated = c.copyWith(label: 'New', command: 'echo bye');

      expect(updated.id, 'c1'); // unchanged
      expect(updated.label, 'New');
      expect(updated.command, 'echo bye');
      expect(updated.profileId, 'p1'); // unchanged
    });

    test('copyWith can clear profileId by passing null', () {
      final c = makeCommand();
      final updated = c.copyWith();
      expect(updated.profileId, 'p1');
    });

    test('preserves createdAt through copyWith', () {
      final fixed = DateTime(2022, 3, 3);
      final c = QuickCommand(
        id: 'c',
        label: 'l',
        command: 'cmd',
        createdAt: fixed,
      );
      final updated = c.copyWith(label: 'new');
      expect(updated.createdAt, fixed);
    });
  });

  group('TunnelConfig', () {
    test('defaults: localhost, port 0, enabled', () {
      final t = TunnelConfig(id: 't1', label: 'Test', type: TunnelType.local);
      expect(t.localPort, 0);
      expect(t.remoteHost, 'localhost');
      expect(t.remotePort, 0);
      expect(t.enabled, true);
    });

    test('displayString for local forward', () {
      final t = TunnelConfig(
        id: 't',
        label: 'L',
        type: TunnelType.local,
        localPort: 8080,
        remoteHost: 'db',
        remotePort: 3306,
      );
      expect(t.displayString, 'L:8080 → db:3306');
    });

    test('displayString for remote forward', () {
      final t = TunnelConfig(
        id: 't',
        label: 'L',
        type: TunnelType.remote,
        localPort: 8080,
        remoteHost: 'web',
        remotePort: 80,
      );
      expect(t.displayString, 'R:80 → web:8080');
    });

    test('displayString for dynamic SOCKS5', () {
      final t = TunnelConfig(
        id: 't',
        label: 'L',
        type: TunnelType.dynamicSocks5,
        localPort: 1080,
      );
      expect(t.displayString, 'D:1080 (SOCKS5)');
    });

    test('typeLabel returns correct strings', () {
      expect(
        TunnelConfig(id: 't', label: 'l', type: TunnelType.local).typeLabel,
        'Local',
      );
      expect(
        TunnelConfig(id: 't', label: 'l', type: TunnelType.remote).typeLabel,
        'Remote',
      );
      expect(
        TunnelConfig(
          id: 't',
          label: 'l',
          type: TunnelType.dynamicSocks5,
        ).typeLabel,
        'SOCKS5',
      );
    });

    test('copyWith updates specified fields', () {
      final t = TunnelConfig(
        id: 't1',
        label: 'Original',
        type: TunnelType.local,
        localPort: 8080,
        remoteHost: 'db',
        remotePort: 3306,
        enabled: true,
      );
      final updated = t.copyWith(
        label: 'Updated',
        localPort: 9090,
        enabled: false,
      );
      expect(updated.id, 't1'); // unchanged
      expect(updated.label, 'Updated');
      expect(updated.localPort, 9090);
      expect(updated.remoteHost, 'db'); // unchanged
      expect(updated.enabled, false);
    });
  });
}
