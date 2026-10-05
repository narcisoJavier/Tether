import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:pinenacl/key_derivation.dart';
import 'package:pinenacl/x25519.dart' show EncryptedMessage, SecretBox;
import 'package:tether/models/connection_profile.dart';
import 'package:tether/models/quick_command.dart';
import 'package:tether/models/tunnel_config.dart';
import 'package:tether/services/export_service.dart';
import 'package:tether/services/hive_adapters.dart';
import 'package:tether/utils/constants.dart';

const password = 'test-password';

void main() {
  late Directory directory;
  late Box<ConnectionProfile> profiles;
  late Box<QuickCommand> commands;
  late String backup;
  late Map<String, dynamic> envelope;
  late Uint8List key;
  late Map<String, dynamic> payload;

  setUpAll(() {
    Hive.registerAdapter(ConnectionProfileAdapter());
    Hive.registerAdapter(QuickCommandAdapter());
    Hive.registerAdapter(TunnelConfigAdapter());
  });
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('tether-backup-test-');
    Hive.init(directory.path);
    profiles = await Hive.openBox<ConnectionProfile>(AppConstants.profilesBox);
    commands = await Hive.openBox<QuickCommand>(AppConstants.commandsBox);
    await profiles.put(
      'server',
      ConnectionProfile(
        id: 'server',
        label: 'Server',
        host: 'example.test',
        port: 22,
        username: 'alice',
        authType: AuthType.password,
        password: 'excluded-secret',
        environment: 'production',
        tunnels: [
          TunnelConfig(
            id: 'tunnel',
            label: 'Proxy',
            type: TunnelType.dynamicSocks5,
            localPort: 1080,
          ),
        ],
      ),
    );
    await commands.put(
      'command',
      QuickCommand(
        id: 'command',
        label: 'Status',
        command: 'uptime',
        profileId: 'server',
      ),
    );
    backup = await ExportService.exportEncrypted(password: password);
    envelope = jsonDecode(backup) as Map<String, dynamic>;
    key = PBKDF2.hmac_sha256(
      Uint8List.fromList(utf8.encode(password)),
      base64Decode(envelope['salt'] as String),
      envelope['iterations'] as int,
      32,
    );
    payload =
        jsonDecode(
              utf8.decode(
                SecretBox(key).decrypt(
                  EncryptedMessage.fromList(
                    base64Decode(envelope['ciphertext'] as String),
                  ),
                ),
              ),
            )
            as Map<String, dynamic>;
  });
  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  String encodePayload(Map<String, dynamic> value) {
    final encrypted = SecretBox(
      key,
    ).encrypt(Uint8List.fromList(utf8.encode(jsonEncode(value))));
    return jsonEncode({...envelope, 'ciphertext': base64Encode(encrypted)});
  }

  test(
    'encrypted round trip preserves environment, commands and tunnels',
    () async {
      expect(backup, isNot(contains('example.test')));
      expect(jsonEncode(payload), isNot(contains('excluded-secret')));
      final second = jsonDecode(
        await ExportService.exportEncrypted(password: password),
      );
      expect(second['salt'], isNot(envelope['salt']));
      expect(second['ciphertext'], isNot(envelope['ciphertext']));
      await profiles.clear();
      await commands.clear();
      final result = await ExportService.importEncrypted(
        backup,
        password: password,
      );
      expect(result.success, isTrue);
      expect(result.profilesImported, 1);
      expect(result.commandsImported, 1);
      expect(profiles.get('server')!.environment, 'Prod');
      expect(profiles.get('server')!.password, isNull);
      expect(profiles.get('server')!.tunnels.single.localPort, 1080);
      expect(commands.get('command')!.command, 'uptime');
    },
  );

  test(
    'collision counts describe writes and replace removes old entries',
    () async {
      final skipped = await ExportService.importEncrypted(
        backup,
        password: password,
        mode: ImportMode.skipExisting,
      );
      expect(skipped.success, isTrue);
      expect(skipped.profilesImported, 0);
      expect(skipped.commandsImported, 0);
      expect(skipped.recordsSkipped, 2);
      await profiles.put(
        'extra',
        ConnectionProfile(
          id: 'extra',
          label: 'Extra',
          host: 'extra.test',
          port: 22,
          username: 'alice',
          authType: AuthType.password,
        ),
      );
      final result = await ExportService.importEncrypted(
        backup,
        password: password,
        mode: ImportMode.replace,
      );
      expect(result.success, isTrue);
      expect(profiles.keys, ['server']);
    },
  );

  test(
    'wrong password and tampered ciphertext leave storage untouched',
    () async {
      final wrong = await ExportService.importEncrypted(
        backup,
        password: 'wrong-password',
      );
      expect(wrong.success, isFalse);
      final cipher = base64Decode(envelope['ciphertext'] as String);
      cipher[cipher.length - 1] ^= 1;
      final tampered = await ExportService.importEncrypted(
        jsonEncode({...envelope, 'ciphertext': base64Encode(cipher)}),
        password: password,
        mode: ImportMode.replace,
      );
      expect(tampered.success, isFalse);
      expect(profiles.get('server')!.password, 'excluded-secret');
      expect(commands.length, 1);
    },
  );

  test(
    'invalid fields and duplicate IDs are rejected before replace',
    () async {
      final rows = payload['profiles'] as List;
      final original = Map<String, dynamic>.from(rows.single as Map);
      for (final invalid in [
        {...original, 'port': 0},
        {...original, 'authType': 'unknown'},
        {...original, 'colorIndex': -1},
        {...original, 'createdAt': 'invalid'},
        {...original, 'password': 'not-in-scope'},
      ]) {
        final result = await ExportService.importEncrypted(
          encodePayload({
            ...payload,
            'profiles': [invalid],
          }),
          password: password,
          mode: ImportMode.replace,
        );
        expect(result.success, isFalse);
        expect(profiles.get('server')!.password, 'excluded-secret');
      }
      final duplicate = await ExportService.importEncrypted(
        encodePayload({
          ...payload,
          'profiles': [original, original],
        }),
        password: password,
        mode: ImportMode.replace,
      );
      expect(duplicate.success, isFalse);
      expect(profiles.length, 1);
    },
  );

  test(
    'bounded envelope, legacy and plaintext export APIs reject safely',
    () async {
      for (final input in [
        'not json',
        '[]',
        'x' * (2 * 1024 * 1024 + 1),
        jsonEncode({...envelope, 'iterations': 2147483647}),
        jsonEncode({...envelope, 'iterations': 99999}),
        jsonEncode({...envelope, 'salt': 'AAAA'}),
        jsonEncode({...envelope, 'ciphertext': 'AAAA'}),
        jsonEncode({'version': 1, 'profiles': [], 'commands': []}),
      ]) {
        expect(
          (await ExportService.importEncrypted(
            input,
            password: password,
          )).success,
          isFalse,
        );
      }
      expect(ExportService.exportToJson(), throwsUnsupportedError);
      expect(ExportService.exportToClipboard(), throwsUnsupportedError);
      expect(
        ExportService.exportEncrypted(password: 'short'),
        throwsFormatException,
      );
      expect(
        ExportService.exportEncrypted(password: 'x' * 1025),
        throwsFormatException,
      );
      expect(profiles.length, 1);
      expect(commands.length, 1);
    },
  );
}
