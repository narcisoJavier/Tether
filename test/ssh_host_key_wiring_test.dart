import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every SSHClient construction installs host-key verification', () {
    final dartFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    var constructorCount = 0;

    for (final file in dartFiles) {
      final source = file.readAsStringSync();
      final count = RegExp(
        r'\bSSHClient(?:\s*\(|\.new\b)',
      ).allMatches(source).length;
      if (count == 0) continue;
      constructorCount += count;
      expect(
        'onVerifyHostKey:'.allMatches(source).length,
        count,
        reason: '${file.path} constructs SSHClient without a verifier.',
      );
    }

    expect(constructorCount, 1);
  });

  test('host-key verification cannot be omitted by connection callers', () {
    final service = File('lib/services/ssh_service.dart').readAsStringSync();
    expect(
      'required HostKeyDecisionHandler onHostKeyDecision'
          .allMatches(service)
          .length,
      2,
    );
    expect(service, isNot(contains('disableHostkeyVerification: true')));

    for (final path in [
      'lib/screens/tabbed_terminal_screen.dart',
      'lib/screens/quick_commands_screen.dart',
      'lib/screens/sftp_screen.dart',
      'lib/screens/profile_editor_screen.dart',
    ]) {
      expect(
        File(path).readAsStringSync(),
        contains('onHostKeyDecision:'),
        reason: '$path must provide the explicit host-key trust flow.',
      );
    }
  });
}
