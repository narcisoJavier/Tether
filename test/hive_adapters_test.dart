import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:hive/src/binary/binary_reader_impl.dart';
import 'package:hive/src/binary/binary_writer_impl.dart';
import 'package:hive/src/registry/type_registry_impl.dart';
import 'package:opa/models/connection_profile.dart';
import 'package:opa/models/quick_command.dart';
import 'package:opa/models/stored_key_pair.dart';
import 'package:opa/models/tunnel_config.dart';
import 'package:opa/services/hive_adapters.dart';

void main() {
  setUpAll(() {
    registerHiveAdapters();
  });

  group('ConnectionProfileAdapter', () {
    test('round-trips a complete profile', () {
      final original = ConnectionProfile(
        id: 'profile-1',
        label: 'My PC',
        host: '192.168.1.100',
        port: 2222,
        username: 'admin',
        authType: AuthType.publicKey,
        password: 's3cret',
        keyId: 'key-1',
        colorIndex: 3,
        lastConnectionSuccess: true,
      );

      final restored = _roundTrip(original, ConnectionProfileAdapter());

      expect(restored.id, 'profile-1');
      expect(restored.label, 'My PC');
      expect(restored.host, '192.168.1.100');
      expect(restored.port, 2222);
      expect(restored.username, 'admin');
      expect(restored.authType, AuthType.publicKey);
      expect(restored.password, 's3cret');
      expect(restored.keyId, 'key-1');
      expect(restored.colorIndex, 3);
      expect(restored.lastConnectionSuccess, true);
    });

    test('round-trips null optional fields (password-only auth)', () {
      final original = ConnectionProfile(
        id: 'p2',
        label: 'Server',
        host: 'example.com',
        port: 22,
        username: 'root',
        authType: AuthType.password,
      );

      final restored = _roundTrip(original, ConnectionProfileAdapter());

      expect(restored.password, isNull);
      expect(restored.keyId, isNull);
      expect(restored.authType, AuthType.password);
    });

    test('round-trips all AuthType enum values', () {
      for (final authType in AuthType.values) {
        final original = ConnectionProfile(
          id: 'auth-test',
          label: 'L',
          host: 'h',
          port: 22,
          username: 'u',
          authType: authType,
        );
        final restored = _roundTrip(original, ConnectionProfileAdapter());
        expect(restored.authType, authType);
      }
    });

    test('preserves timestamps', () {
      final created = DateTime(2024, 1, 15, 10, 30);
      final updated = DateTime(2024, 6, 20, 14, 45);
      final original = ConnectionProfile(
        id: 'ts',
        label: 'l',
        host: 'h',
        port: 22,
        username: 'u',
        authType: AuthType.password,
        createdAt: created,
        updatedAt: updated,
      );

      final restored = _roundTrip(original, ConnectionProfileAdapter());

      expect(restored.createdAt, created);
      expect(restored.updatedAt, updated);
    });

    test('typeId is 0', () {
      expect(ConnectionProfileAdapter().typeId, 0);
    });
  });

  group('StoredKeyPairAdapter', () {
    test('round-trips an ed25519 key', () {
      final original = StoredKeyPair(
        id: 'key-1',
        label: 'Work Key',
        keyType: KeyType.ed25519,
        publicKey: 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIexample work',
      );

      final restored = _roundTrip(original, StoredKeyPairAdapter());

      expect(restored.id, 'key-1');
      expect(restored.label, 'Work Key');
      expect(restored.keyType, KeyType.ed25519);
      expect(restored.publicKey, startsWith('ssh-ed25519 '));
    });

    test('round-trips an RSA key', () {
      final original = StoredKeyPair(
        id: 'key-2',
        label: 'Legacy RSA',
        keyType: KeyType.rsa,
        publicKey: 'ssh-rsa AAAAB3NzaC1yc2E... rsa',
      );

      final restored = _roundTrip(original, StoredKeyPairAdapter());

      expect(restored.keyType, KeyType.rsa);
      expect(restored.label, 'Legacy RSA');
    });

    test('typeId is 1', () {
      expect(StoredKeyPairAdapter().typeId, 1);
    });
  });

  group('QuickCommandAdapter', () {
    test('round-trips a command linked to a profile', () {
      final original = QuickCommand(
        id: 'cmd-1',
        label: 'Start Agent',
        command: 'python ~/agents/start.py',
        profileId: 'profile-1',
        colorIndex: 2,
      );

      final restored = _roundTrip(original, QuickCommandAdapter());

      expect(restored.id, 'cmd-1');
      expect(restored.label, 'Start Agent');
      expect(restored.command, 'python ~/agents/start.py');
      expect(restored.profileId, 'profile-1');
      expect(restored.colorIndex, 2);
    });

    test('round-trips a command with no profile link', () {
      final original = QuickCommand(
        id: 'cmd-2',
        label: 'Free Agent',
        command: 'uptime',
      );

      final restored = _roundTrip(original, QuickCommandAdapter());

      expect(restored.profileId, isNull);
    });

    test('round-trips multi-line commands', () {
      const multiLine = 'cd ~/project\n&& git pull\n&& ./deploy.sh';
      final original = QuickCommand(
        id: 'cmd-3',
        label: 'Deploy',
        command: multiLine,
      );

      final restored = _roundTrip(original, QuickCommandAdapter());

      expect(restored.command, multiLine);
    });

    test('typeId is 2', () {
      expect(QuickCommandAdapter().typeId, 2);
    });
  });

  group('registerHiveAdapters', () {
    test('registers all four adapters (idempotent)', () {
      registerHiveAdapters();
      expect(Hive.isAdapterRegistered(0), isTrue);
      expect(Hive.isAdapterRegistered(1), isTrue);
      expect(Hive.isAdapterRegistered(2), isTrue);
      expect(Hive.isAdapterRegistered(3), isTrue);
    });
  });

  group('TunnelConfigAdapter', () {
    test('round-trips a local forward tunnel', () {
      final original = TunnelConfig(
        id: 'tun-1',
        label: 'MySQL Local',
        type: TunnelType.local,
        localPort: 3306,
        remoteHost: 'db.internal',
        remotePort: 3306,
        enabled: true,
      );

      final restored = _roundTrip(original, TunnelConfigAdapter());

      expect(restored.id, 'tun-1');
      expect(restored.label, 'MySQL Local');
      expect(restored.type, TunnelType.local);
      expect(restored.localPort, 3306);
      expect(restored.remoteHost, 'db.internal');
      expect(restored.remotePort, 3306);
      expect(restored.enabled, true);
    });

    test('round-trips a remote forward tunnel', () {
      final original = TunnelConfig(
        id: 'tun-2',
        label: 'Web Remote',
        type: TunnelType.remote,
        localPort: 8080,
        remoteHost: 'localhost',
        remotePort: 80,
        enabled: false,
      );

      final restored = _roundTrip(original, TunnelConfigAdapter());

      expect(restored.type, TunnelType.remote);
      expect(restored.enabled, false);
      expect(restored.localPort, 8080);
      expect(restored.remotePort, 80);
    });

    test('round-trips a dynamic SOCKS5 tunnel', () {
      final original = TunnelConfig(
        id: 'tun-3',
        label: 'SOCKS Proxy',
        type: TunnelType.dynamicSocks5,
        localPort: 1080,
      );

      final restored = _roundTrip(original, TunnelConfigAdapter());

      expect(restored.type, TunnelType.dynamicSocks5);
      expect(restored.localPort, 1080);
    });

    test('round-trips all TunnelType enum values', () {
      for (final type in TunnelType.values) {
        final original = TunnelConfig(
          id: 'type-test',
          label: 'L',
          type: type,
        );
        final restored = _roundTrip(original, TunnelConfigAdapter());
        expect(restored.type, type);
      }
    });

    test('typeId is 3', () {
      expect(TunnelConfigAdapter().typeId, 3);
    });
  });

  group('ConnectionProfileAdapter with tunnels', () {
    test('round-trips a profile with tunnels', () {
      final original = ConnectionProfile(
        id: 'profile-tun',
        label: 'Tunnel Test',
        host: '10.0.0.1',
        port: 22,
        username: 'admin',
        authType: AuthType.publicKey,
        tunnels: [
          TunnelConfig(
            id: 'tun-a',
            label: 'DB',
            type: TunnelType.local,
            localPort: 5432,
            remoteHost: 'db.internal',
            remotePort: 5432,
          ),
          TunnelConfig(
            id: 'tun-b',
            label: 'SOCKS',
            type: TunnelType.dynamicSocks5,
            localPort: 1080,
          ),
        ],
      );

      // For profiles with tunnels, we need a registry with both adapters.
      final registry = TypeRegistryImpl();
      final profileAdapter = ConnectionProfileAdapter();
      final tunnelAdapter = TunnelConfigAdapter();
      registry.registerAdapter(profileAdapter, internal: true);
      registry.registerAdapter(tunnelAdapter, internal: true);

      final writer = BinaryWriterImpl(registry);
      writer.writeByte(profileAdapter.typeId);
      profileAdapter.write(writer, original);
      final bytes = writer.toBytes();

      final reader = BinaryReaderImpl(bytes, registry);
      reader.readByte();
      final restored = profileAdapter.read(reader);

      expect(restored.tunnels.length, 2);
      expect(restored.tunnels[0].id, 'tun-a');
      expect(restored.tunnels[0].type, TunnelType.local);
      expect(restored.tunnels[0].localPort, 5432);
      expect(restored.tunnels[1].id, 'tun-b');
      expect(restored.tunnels[1].type, TunnelType.dynamicSocks5);
    });

    test('round-trips a profile with empty tunnels list', () {
      final original = ConnectionProfile(
        id: 'no-tun',
        label: 'No Tunnels',
        host: 'h',
        port: 22,
        username: 'u',
        authType: AuthType.password,
      );

      final registry = TypeRegistryImpl();
      final profileAdapter = ConnectionProfileAdapter();
      final tunnelAdapter = TunnelConfigAdapter();
      registry.registerAdapter(profileAdapter, internal: true);
      registry.registerAdapter(tunnelAdapter, internal: true);

      final writer = BinaryWriterImpl(registry);
      writer.writeByte(profileAdapter.typeId);
      profileAdapter.write(writer, original);
      final bytes = writer.toBytes();

      final reader = BinaryReaderImpl(bytes, registry);
      reader.readByte();
      final restored = profileAdapter.read(reader);

      expect(restored.tunnels, isEmpty);
    });
  });
}

/// Serialize [value] through a Hive [TypeAdapter] and read it back.
T _roundTrip<T>(T value, TypeAdapter<T> adapter) {
  final registry = TypeRegistryImpl();
  registry.registerAdapter(adapter, internal: true);

  final writer = BinaryWriterImpl(registry);
  writer.writeByte(adapter.typeId);
  adapter.write(writer, value);
  final bytes = writer.toBytes();

  final reader = BinaryReaderImpl(bytes, registry);
  reader.readByte(); // consume the typeId
  return adapter.read(reader);
}
