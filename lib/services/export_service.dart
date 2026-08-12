import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import '../models/connection_profile.dart';
import '../models/quick_command.dart';
import '../models/tunnel_config.dart';
import '../utils/constants.dart';
import 'profile_storage_service.dart';

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

  static const int _currentVersion = 1;

  /// Export all profiles and commands to a JSON string.
  static Future<String> exportToJson() async {
    final profilesBox = Hive.box<ConnectionProfile>(AppConstants.profilesBox);
    final commandsBox = Hive.box<QuickCommand>(AppConstants.commandsBox);

    final profiles = profilesBox.values.map((p) => _profileToJson(p)).toList();
    final commands = commandsBox.values.map((c) => _commandToJson(c)).toList();

    final envelope = {
      'version': _currentVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'profiles': profiles,
      'commands': commands,
    };

    return const JsonEncoder.withIndent('  ').convert(envelope);
  }

  /// Export and copy to clipboard. Returns the JSON string.
  static Future<String> exportToClipboard() async {
    final json = await exportToJson();
    await Clipboard.setData(ClipboardData(text: json));
    return json;
  }

  /// Import data from a JSON string. Returns a result summary.
  static Future<ImportResult> importFromJson(String json) async {
    final Map<String, dynamic> data;
    try {
      data = jsonDecode(json) as Map<String, dynamic>;
    } catch (_) {
      return const ImportResult(success: false, message: 'Invalid JSON.');
    }

    final version = data['version'] as int?;
    if (version == null || version < 1 || version > _currentVersion) {
      return const ImportResult(
        success: false,
        message: 'Unsupported format version.',
      );
    }

    final profilesBox = Hive.box<ConnectionProfile>(AppConstants.profilesBox);
    final commandsBox = Hive.box<QuickCommand>(AppConstants.commandsBox);
    final storage = ProfileStorageService(profilesBox, commandsBox);

    int profilesImported = 0;
    int commandsImported = 0;

    final profilesList = data['profiles'] as List<dynamic>?;
    if (profilesList != null) {
      for (final p in profilesList) {
        final map = p as Map<String, dynamic>;
        if (map['id'] == null || map['label'] == null) continue;
        final profile = _profileFromJson(map);
        await profilesBox.put(profile.id, profile);

        // Older exports may contain a legacy plaintext password. Store it in
        // secure storage during import, then keep it out of Hive. New exports
        // intentionally omit passwords entirely.
        final importedPassword = map['password'] as String?;
        if (importedPassword != null && importedPassword.isNotEmpty) {
          await storage.savePassword(profile.id, importedPassword);
        }
        profilesImported++;
      }
    }

    final commandsList = data['commands'] as List<dynamic>?;
    if (commandsList != null) {
      for (final c in commandsList) {
        final map = c as Map<String, dynamic>;
        if (map['id'] == null ||
            map['label'] == null ||
            map['command'] == null) {
          continue;
        }
        final command = _commandFromJson(map);
        await commandsBox.put(command.id, command);
        commandsImported++;
      }
    }

    return ImportResult(
      success: true,
      message:
          'Imported $profilesImported profiles and '
          '$commandsImported commands.',
      profilesImported: profilesImported,
      commandsImported: commandsImported,
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
      'tunnels': p.tunnels.map((t) => _tunnelToJson(t)).toList(),
    };
  }

  static ConnectionProfile _profileFromJson(Map<String, dynamic> map) {
    final tunnelsList = map['tunnels'] as List<dynamic>?;
    return ConnectionProfile(
      id: map['id'] as String,
      label: map['label'] as String,
      host: map['host'] as String,
      port: map['port'] as int,
      username: map['username'] as String,
      authType: _parseAuthType(map['authType'] as String?),
      // Passwords are handled separately by importFromJson and are never
      // persisted in the Hive profile object.
      password: null,
      keyId: map['keyId'] as String?,
      colorIndex: map['colorIndex'] as int? ?? 0,
      createdAt: _parseDateTime(map['createdAt']),
      updatedAt: _parseDateTime(map['updatedAt']),
      lastConnectionSuccess: map['lastConnectionSuccess'] as bool? ?? false,
      connectionMethod: _parseConnectionMethod(
        map['connectionMethod'] as String?,
      ),
      tunnels:
          tunnelsList
              ?.map((t) => _tunnelFromJson(t as Map<String, dynamic>))
              .toList() ??
          [],
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
      id: map['id'] as String,
      label: map['label'] as String,
      command: map['command'] as String,
      profileId: map['profileId'] as String?,
      colorIndex: map['colorIndex'] as int? ?? 0,
      createdAt: _parseDateTime(map['createdAt']),
      presetId: map['presetId'] as String?,
    );
  }

  static AuthType _parseAuthType(String? name) {
    return AuthType.values.firstWhere(
      (a) => a.name == name,
      orElse: () => AuthType.password,
    );
  }

  static ConnectionMethod _parseConnectionMethod(String? name) {
    if (name == null) return ConnectionMethod.direct;
    return ConnectionMethod.values.firstWhere(
      (m) => m.name == name,
      orElse: () => ConnectionMethod.direct,
    );
  }

  static DateTime _parseDateTime(dynamic value) {
    if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
    return DateTime.now();
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
    return TunnelConfig(
      id: map['id'] as String,
      label: map['label'] as String? ?? '',
      type: _parseTunnelType(map['type'] as String?),
      localPort: map['localPort'] as int? ?? 0,
      remoteHost: map['remoteHost'] as String? ?? 'localhost',
      remotePort: map['remotePort'] as int? ?? 0,
      enabled: map['enabled'] as bool? ?? true,
    );
  }

  static TunnelType _parseTunnelType(String? name) {
    if (name == null) return TunnelType.local;
    return TunnelType.values.firstWhere(
      (t) => t.name == name,
      orElse: () => TunnelType.local,
    );
  }
}

/// Result of an import operation.
class ImportResult {
  final bool success;
  final String message;
  final int profilesImported;
  final int commandsImported;

  const ImportResult({
    required this.success,
    required this.message,
    this.profilesImported = 0,
    this.commandsImported = 0,
  });
}
