import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:hive/hive.dart';
import 'package:pinenacl/key_derivation.dart';
import 'package:pinenacl/x25519.dart' show EncryptedMessage, SecretBox;
import 'package:pinenacl/tweetnacl.dart' show TweetNaCl;
import '../models/connection_profile.dart';
import '../models/quick_command.dart';
import '../models/tunnel_config.dart';
import '../utils/constants.dart';

/// Data envelope for export/import.
class ExportData {
  final int version;
  final String exportedAt;
  final List<ConnectionProfile> profiles;
  final List<QuickCommand> commands;

  ExportData({
    required this.version,
    required this.exportedAt,
    required this.profiles,
    required this.commands,
  });
}

/// Service for exporting and importing connection profiles and commands.
class ExportService {
  ExportService._();

  static const int _maxBytes = 1024 * 1024;
  static const int _pbkdf2Iterations = 120000;
  static Future<void> _restoreQueue = Future<void>.value();
  static const String backupScope =
      'Includes profiles, environment tags, tunnels, and quick commands. '
      'Excludes SSH passwords, private keys, trusted host keys, Tailscale '
      'identity, and app preferences. Re-enter credentials on a new device.';

  /// Create an authenticated, password-protected backup envelope.
  static Future<String> exportEncrypted({required String password}) async {
    _validatePassword(password);
    final plain = await _exportPayload();
    if (utf8.encode(plain).length > _maxBytes - 40) {
      throw const FormatException('Backup exceeds the 1 MiB limit.');
    }
    _parsePayload(plain);
    return Isolate.run(() {
      final salt = TweetNaCl.randombytes(16);
      final key = PBKDF2.hmac_sha256(
        Uint8List.fromList(utf8.encode(password)),
        salt,
        _pbkdf2Iterations,
        32,
      );
      final encrypted = SecretBox(
        key,
      ).encrypt(Uint8List.fromList(utf8.encode(plain)));
      return jsonEncode({
        'format': 'tether-backup',
        'version': 2,
        'kdf': 'PBKDF2-HMAC-SHA256',
        'iterations': _pbkdf2Iterations,
        'salt': base64Encode(salt),
        'ciphertext': base64Encode(encrypted.toList()),
      });
    });
  }

  static Future<String> _exportPayload() async {
    final profilesBox = Hive.box<ConnectionProfile>(AppConstants.profilesBox);
    final commandsBox = Hive.box<QuickCommand>(AppConstants.commandsBox);
    return jsonEncode({
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'profiles': profilesBox.values.map(_profileToJson).toList(),
      'commands': commandsBox.values.map(_commandToJson).toList(),
    });
  }

  /// Export all profiles and commands to a JSON string.
  static Future<String> exportToJson() async {
    throw UnsupportedError('Use a password-protected encrypted backup.');
  }

  /// Export and copy to clipboard. Returns the JSON string.
  static Future<String> exportToClipboard() async {
    throw UnsupportedError(
      'Plaintext clipboard export is disabled. Use exportEncrypted.',
    );
  }

  /// Decrypt and import only after the complete payload has been validated.
  static Future<ImportResult> importEncrypted(
    String input, {
    required String password,
    ImportMode mode = ImportMode.merge,
  }) async {
    if (input.length > _maxBytes * 2) {
      return const ImportResult(
        success: false,
        message: 'Backup is too large.',
      );
    }
    try {
      _validatePassword(password);
      final env = jsonDecode(input) as Map<String, dynamic>;
      if (env['version'] == 1 && env['format'] == null) {
        return importFromJson(input);
      }
      if (env['format'] != 'tether-backup' ||
          env['version'] != 2 ||
          env['kdf'] != 'PBKDF2-HMAC-SHA256') {
        throw const FormatException('Unsupported backup format.');
      }
      final iterations = _integer(env, 'iterations', 100000, 600000);
      final salt = base64Decode(_string(env, 'salt', max: 24));
      final cipher = base64Decode(
        _string(env, 'ciphertext', max: ((_maxBytes + 2) ~/ 3) * 4),
      );
      if (salt.length != 16 ||
          cipher.length < 40 ||
          cipher.length > _maxBytes) {
        throw const FormatException('Malformed backup.');
      }
      final plain = await Isolate.run(() {
        final key = PBKDF2.hmac_sha256(
          Uint8List.fromList(utf8.encode(password)),
          salt,
          iterations,
          32,
        );
        return SecretBox(
          key,
        ).decrypt(EncryptedMessage.fromList(Uint8List.fromList(cipher)));
      });
      final data = _parsePayload(utf8.decode(plain));
      final previous = _restoreQueue;
      final completed = Completer<void>();
      _restoreQueue = completed.future;
      try {
        await previous;
        return await _importValidated(data, mode);
      } finally {
        completed.complete();
      }
    } catch (_) {
      return const ImportResult(
        success: false,
        message: 'Backup password, integrity, or format is invalid.',
      );
    }
  }

  static ExportData _parsePayload(String json) {
    final data = jsonDecode(json) as Map<String, dynamic>;
    if (data['version'] != 1 ||
        data['profiles'] is! List ||
        data['commands'] is! List ||
        (data['profiles'] as List).length > 1000 ||
        (data['commands'] as List).length > 1000) {
      throw const FormatException('Malformed payload.');
    }
    _date(data, 'exportedAt');
    final profiles = (data['profiles'] as List)
        .map((e) => _profileFromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    final commands = (data['commands'] as List)
        .map((e) => _commandFromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    _unique(profiles.map((p) => p.id));
    _unique(commands.map((c) => c.id));
    return ExportData(
      version: 1,
      exportedAt: data['exportedAt'] as String,
      profiles: profiles,
      commands: commands,
    );
  }

  static Future<ImportResult> _importValidated(
    ExportData data,
    ImportMode mode,
  ) async {
    final pb = Hive.box<ConnectionProfile>(AppConstants.profilesBox);
    final cb = Hive.box<QuickCommand>(AppConstants.commandsBox);
    final oldProfiles = pb.toMap();
    final oldCommands = cb.toMap();
    final availableProfileIds = data.profiles.map((p) => p.id).toSet();
    if (mode != ImportMode.replace) {
      availableProfileIds.addAll(pb.keys.whereType<String>());
    }
    for (final command in data.commands) {
      if (command.profileId != null &&
          !availableProfileIds.contains(command.profileId)) {
        throw const FormatException('Command refers to a missing profile.');
      }
    }
    final profileWrites = {
      for (final p in data.profiles)
        if (mode != ImportMode.skipExisting || !oldProfiles.containsKey(p.id))
          p.id: p,
    };
    final commandWrites = {
      for (final c in data.commands)
        if (mode != ImportMode.skipExisting || !oldCommands.containsKey(c.id))
          c.id: c,
    };
    try {
      if (mode == ImportMode.replace) {
        await pb.clear();
        await cb.clear();
      }
      await pb.putAll(profileWrites);
      await cb.putAll(commandWrites);
      await pb.flush();
      await cb.flush();
    } catch (_) {
      final restored = await Future.wait([
        _rollback(pb, oldProfiles),
        _rollback(cb, oldCommands),
      ]);
      return ImportResult(
        success: false,
        message: restored.every((ok) => ok)
            ? 'Restore failed. Previous profiles and commands were restored.'
            : 'Restore failed and storage rollback could not finish. Local data '
                  'may be incomplete; keep your backup and retry after resolving '
                  'the storage error.',
      );
    }
    final skipped =
        data.profiles.length +
        data.commands.length -
        profileWrites.length -
        commandWrites.length;
    return ImportResult(
      success: true,
      message:
          'Imported ${profileWrites.length} profiles and ${commandWrites.length} '
          'commands; skipped $skipped existing records.',
      profilesImported: profileWrites.length,
      commandsImported: commandWrites.length,
      recordsSkipped: skipped,
    );
  }

  /// Import data from a JSON string. Returns a result summary.
  static Future<ImportResult> importFromJson(String json) async {
    return const ImportResult(
      success: false,
      message:
          'Plaintext legacy backups are unsupported. Use an encrypted v2 '
          'backup; recreate legacy profiles manually.',
    );
  }

  static Map<String, dynamic> _profileToJson(ConnectionProfile p) {
    return {
      'id': p.id,
      'label': p.label,
      'host': p.host,
      'port': p.port,
      'username': p.username,
      'authType': p.authType.name,
      'keyId': p.keyId,
      'colorIndex': p.colorIndex,
      'createdAt': p.createdAt.toIso8601String(),
      'updatedAt': p.updatedAt.toIso8601String(),
      'lastConnectionSuccess': p.lastConnectionSuccess,
      'connectionMethod': p.connectionMethod.name,
      'environment': canonicalizeEnvironment(p.environment),
      'tunnels': p.tunnels.map((t) => _tunnelToJson(t)).toList(),
    };
  }

  static ConnectionProfile _profileFromJson(Map<String, dynamic> map) {
    if (map.containsKey('password')) {
      throw const FormatException('Credentials are outside backup scope.');
    }
    final tunnelsList = map['tunnels'] as List<dynamic>?;
    if (tunnelsList != null && tunnelsList.length > 100) {
      throw const FormatException('Too many tunnels.');
    }
    final tunnels =
        tunnelsList
            ?.map((t) => _tunnelFromJson(t as Map<String, dynamic>))
            .toList() ??
        <TunnelConfig>[];
    _unique(tunnels.map((t) => t.id));
    return ConnectionProfile(
      id: _string(map, 'id', max: 255),
      label: _string(map, 'label', max: 255, allowEmpty: true),
      host: _string(map, 'host', max: 253),
      port: _integer(map, 'port', 1, 65535),
      username: _string(map, 'username', max: 255),
      authType: _parseAuthType(map['authType'] as String?),
      // Passwords are handled separately by importFromJson and are never
      // persisted in the Hive profile object.
      password: null,
      keyId: _optionalString(map, 'keyId', max: 255),
      colorIndex: _color(map),
      createdAt: _date(map, 'createdAt'),
      updatedAt: _date(map, 'updatedAt'),
      lastConnectionSuccess: map['lastConnectionSuccess'] as bool? ?? false,
      connectionMethod: _parseConnectionMethod(
        map['connectionMethod'] as String?,
      ),
      environment: _optionalString(map, 'environment', max: 255),
      tunnels: tunnels,
    );
  }

  static Map<String, dynamic> _commandToJson(QuickCommand c) {
    return {
      'id': c.id,
      'label': c.label,
      'command': c.command,
      'profileId': c.profileId,
      'colorIndex': c.colorIndex,
      'createdAt': c.createdAt.toIso8601String(),
      'presetId': c.presetId,
    };
  }

  static QuickCommand _commandFromJson(Map<String, dynamic> map) {
    return QuickCommand(
      id: _string(map, 'id', max: 255),
      label: _string(map, 'label', max: 255),
      command: _string(map, 'command', max: 65536),
      profileId: _optionalString(map, 'profileId', max: 255),
      colorIndex: _color(map),
      createdAt: _date(map, 'createdAt'),
      presetId: _optionalString(map, 'presetId', max: 255),
    );
  }

  static AuthType _parseAuthType(String? name) {
    return AuthType.values.firstWhere(
      (a) => a.name == name,
      orElse: () => throw const FormatException('Invalid authentication type.'),
    );
  }

  static ConnectionMethod _parseConnectionMethod(String? name) {
    if (name == null) return ConnectionMethod.direct;
    return ConnectionMethod.values.firstWhere(
      (m) => m.name == name,
      orElse: () => throw const FormatException('Invalid connection method.'),
    );
  }

  static DateTime _date(Map<String, dynamic> map, String key) {
    final value = DateTime.tryParse(_string(map, key, max: 64));
    if (value == null) throw FormatException('Invalid $key.');
    return value;
  }

  static Map<String, dynamic> _tunnelToJson(TunnelConfig t) {
    return {
      'id': t.id,
      'label': t.label,
      'type': t.type.name,
      'localPort': t.localPort,
      'remoteHost': t.remoteHost,
      'remotePort': t.remotePort,
      'enabled': t.enabled,
    };
  }

  static TunnelConfig _tunnelFromJson(Map<String, dynamic> map) {
    final type = _parseTunnelType(map['type'] as String?);
    return TunnelConfig(
      id: _string(map, 'id', max: 255),
      label: _string(map, 'label', max: 255, allowEmpty: true),
      type: type,
      localPort: _integer(map, 'localPort', 1, 65535),
      remoteHost: _string(map, 'remoteHost', max: 253),
      remotePort: _integer(
        map,
        'remotePort',
        type == TunnelType.dynamicSocks5 ? 0 : 1,
        65535,
      ),
      enabled: map['enabled'] as bool? ?? true,
    );
  }

  static TunnelType _parseTunnelType(String? name) {
    return TunnelType.values.firstWhere(
      (t) => t.name == name,
      orElse: () => throw const FormatException('Invalid tunnel type.'),
    );
  }

  static void _validatePassword(String password) {
    if (password.length < 8 || password.length > 1024) {
      throw const FormatException(
        'Use a backup password of 8–1024 characters.',
      );
    }
  }

  static Future<bool> _rollback<T>(Box<T> box, Map<dynamic, T> values) async {
    try {
      await box.clear();
      await box.putAll(values);
      await box.flush();
      return true;
    } catch (_) {
      return false;
    }
  }

  static String _string(
    Map<String, dynamic> map,
    String key, {
    int max = 1024,
    bool allowEmpty = false,
  }) {
    final value = map[key];
    if (value is! String ||
        value.length > max ||
        (!allowEmpty && value.trim().isEmpty) ||
        value.contains('\u0000')) {
      throw FormatException('Invalid $key.');
    }
    return value;
  }

  static String? _optionalString(
    Map<String, dynamic> map,
    String key, {
    int max = 1024,
  }) => map[key] == null ? null : _string(map, key, max: max);

  static int _integer(Map<String, dynamic> map, String key, int min, int max) {
    final value = map[key];
    if (value is! int || value < min || value > max) {
      throw FormatException('Invalid $key.');
    }
    return value;
  }

  static int _color(Map<String, dynamic> map) => _integer(
    {...map, 'colorIndex': map['colorIndex'] ?? 0},
    'colorIndex',
    0,
    ProfileColors.palette.length - 1,
  );

  static void _unique(Iterable<String> ids) {
    final seen = <String>{};
    if (ids.any((id) => !seen.add(id))) {
      throw const FormatException('Duplicate record ID.');
    }
  }
}

/// Result of an import operation.
class ImportResult {
  final bool success;
  final String message;
  final int profilesImported;
  final int commandsImported;
  final int recordsSkipped;

  const ImportResult({
    required this.success,
    required this.message,
    this.profilesImported = 0,
    this.commandsImported = 0,
    this.recordsSkipped = 0,
  });
}

/// Collision behavior for encrypted backup restoration.
enum ImportMode { merge, replace, skipExisting }
