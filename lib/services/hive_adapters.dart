import 'package:hive/hive.dart';

import '../models/connection_profile.dart';
import '../models/stored_key_pair.dart';
import '../models/quick_command.dart';
import '../models/tunnel_config.dart';

/// Registers all Hive type adapters.
///
/// Call this before opening any boxes.
void registerHiveAdapters() {
  if (!Hive.isAdapterRegistered(0)) {
    Hive.registerAdapter(ConnectionProfileAdapter());
  }
  if (!Hive.isAdapterRegistered(1)) {
    Hive.registerAdapter(StoredKeyPairAdapter());
  }
  if (!Hive.isAdapterRegistered(2)) {
    Hive.registerAdapter(QuickCommandAdapter());
  }
  if (!Hive.isAdapterRegistered(3)) {
    Hive.registerAdapter(TunnelConfigAdapter());
  }
}

// --- ConnectionProfile TypeAdapter ---

class ConnectionProfileAdapter extends TypeAdapter<ConnectionProfile> {
  @override
  final typeId = 0;

  @override
  ConnectionProfile read(BinaryReader reader) {
    return ConnectionProfile(
      id: reader.read(),
      label: reader.read(),
      host: reader.read(),
      port: reader.read(),
      username: reader.read(),
      authType: AuthType.values[reader.readByte()],
      password: reader.read() as String?,
      keyId: reader.read() as String?,
      colorIndex: reader.read(),
      createdAt: DateTime.fromMillisecondsSinceEpoch(reader.readInt()),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(reader.readInt()),
      lastConnectionSuccess: reader.readBool(),
      connectionMethod: _readConnectionMethod(reader),
      tunnels: _readTunnels(reader),
      environment: _readEnvironment(reader),
    );
  }

  @override
  void write(BinaryWriter writer, ConnectionProfile obj) {
    writer.write(obj.id);
    writer.write(obj.label);
    writer.write(obj.host);
    writer.write(obj.port);
    writer.write(obj.username);
    writer.writeByte(obj.authType.index);
    writer.write(obj.password);
    writer.write(obj.keyId);
    writer.write(obj.colorIndex);
    writer.writeInt(obj.createdAt.millisecondsSinceEpoch);
    writer.writeInt(obj.updatedAt.millisecondsSinceEpoch);
    writer.writeBool(obj.lastConnectionSuccess);
    writer.writeByte(obj.connectionMethod.index);
    _writeTunnels(writer, obj.tunnels);
    writer.write(obj.environment);
  }

  /// Reads [ConnectionMethod] from a Hive binary reader with backward
  /// compatibility for profiles saved before this field existed.
  ConnectionMethod _readConnectionMethod(BinaryReader reader) {
    try {
      if (reader.availableBytes > 0) {
        final index = reader.readByte();
        if (index >= 0 && index < ConnectionMethod.values.length) {
          return ConnectionMethod.values[index];
        }
      }
    } catch (_) {}
    return ConnectionMethod.direct;
  }

  /// Reads the tunnel list with backward compatibility for profiles saved
  /// before tunnels existed (pre-v0.4).
  List<TunnelConfig> _readTunnels(BinaryReader reader) {
    try {
      if (reader.availableBytes > 0) {
        final count = reader.readInt();
        final tunnels = <TunnelConfig>[];
        final adapter = TunnelConfigAdapter();
        for (var i = 0; i < count; i++) {
          tunnels.add(adapter.read(reader));
        }
        return tunnels;
      }
    } catch (_) {}
    return [];
  }

  /// Writes the tunnel list.
  void _writeTunnels(BinaryWriter writer, List<TunnelConfig> tunnels) {
    writer.writeInt(tunnels.length);
    final adapter = TunnelConfigAdapter();
    for (final tunnel in tunnels) {
      adapter.write(writer, tunnel);
    }
  }

  /// Reads [environment] with backward compatibility for older profiles.
  String? _readEnvironment(BinaryReader reader) {
    try {
      if (reader.availableBytes > 0) {
        return reader.read() as String?;
      }
    } catch (_) {}
    return null;
  }
}

// --- StoredKeyPair TypeAdapter ---

class StoredKeyPairAdapter extends TypeAdapter<StoredKeyPair> {
  @override
  final typeId = 1;

  @override
  StoredKeyPair read(BinaryReader reader) {
    return StoredKeyPair(
      id: reader.read(),
      label: reader.read(),
      keyType: KeyType.values[reader.readByte()],
      publicKey: reader.read(),
      createdAt: DateTime.fromMillisecondsSinceEpoch(reader.readInt()),
    );
  }

  @override
  void write(BinaryWriter writer, StoredKeyPair obj) {
    writer.write(obj.id);
    writer.write(obj.label);
    writer.writeByte(obj.keyType.index);
    writer.write(obj.publicKey);
    writer.writeInt(obj.createdAt.millisecondsSinceEpoch);
  }
}

// --- QuickCommand TypeAdapter ---

class QuickCommandAdapter extends TypeAdapter<QuickCommand> {
  @override
  final typeId = 2;

  @override
  QuickCommand read(BinaryReader reader) {
    final id = reader.read() as String;
    final label = reader.read() as String;
    final command = reader.read() as String;
    final profileId = reader.read() as String?;
    final colorIndex = reader.read() as int;
    final createdAt =
        DateTime.fromMillisecondsSinceEpoch(reader.readInt());

    // presetId was added later — guard against older entries that don't
    // contain it so existing data still deserializes cleanly.
    String? presetId;
    try {
      if (reader.availableBytes > 0) {
        presetId = reader.read() as String?;
      }
    } catch (_) {
      presetId = null;
    }

    return QuickCommand(
      id: id,
      label: label,
      command: command,
      profileId: profileId,
      colorIndex: colorIndex,
      createdAt: createdAt,
      presetId: presetId,
    );
  }

  @override
  void write(BinaryWriter writer, QuickCommand obj) {
    writer.write(obj.id);
    writer.write(obj.label);
    writer.write(obj.command);
    writer.write(obj.profileId);
    writer.write(obj.colorIndex);
    writer.writeInt(obj.createdAt.millisecondsSinceEpoch);
    writer.write(obj.presetId);
  }
}

// --- TunnelConfig TypeAdapter ---

class TunnelConfigAdapter extends TypeAdapter<TunnelConfig> {
  @override
  final typeId = 3;

  @override
  TunnelConfig read(BinaryReader reader) {
    return TunnelConfig(
      id: reader.read() as String,
      label: reader.read() as String,
      type: TunnelType.values[reader.readByte()],
      localPort: reader.readInt(),
      remoteHost: reader.read() as String,
      remotePort: reader.readInt(),
      enabled: reader.readBool(),
    );
  }

  @override
  void write(BinaryWriter writer, TunnelConfig obj) {
    writer.write(obj.id);
    writer.write(obj.label);
    writer.writeByte(obj.type.index);
    writer.writeInt(obj.localPort);
    writer.write(obj.remoteHost);
    writer.writeInt(obj.remotePort);
    writer.writeBool(obj.enabled);
  }
}
