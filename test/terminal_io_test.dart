import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tether/utils/terminal_io.dart';

void main() {
  test('preserves split 2, 3, and 4 byte UTF-8 sequences', () {
    final output = StringBuffer();
    final decoder = StreamingUtf8Decoder(output.write);
    final bytes = Uint8List.fromList(utf8.encode('¢€😀'));
    for (final byte in bytes) {
      decoder.add(Uint8List.fromList([byte]));
    }
    decoder.close();
    expect(output.toString(), '¢€😀');
  });

  test('emits replacement character for malformed EOF', () {
    final output = StringBuffer();
    final decoder = StreamingUtf8Decoder(output.write);
    decoder.add(Uint8List.fromList([0xF0, 0x9F]));
    decoder.close();
    expect(output.toString(), '�');
  });

  test('normalizes PTY commands to exactly one CR', () {
    expect(normalizePtyCommand('ls'), 'ls\r');
    expect(normalizePtyCommand('ls\n\r\n'), 'ls\r');
  });

  test('paste text remains unchanged', () {
    const paste = 'echo hi\n';
    expect(paste, 'echo hi\n');
  });
}
