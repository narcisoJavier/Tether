import 'dart:convert';
import 'dart:typed_data';

/// Incrementally decodes UTF-8 bytes while preserving incomplete sequences.
class StreamingUtf8Decoder {
  StreamingUtf8Decoder(this.onText)
    : _sink = const Utf8Decoder(
        allowMalformed: true,
      ).startChunkedConversion(_StringSinkProxy(onText));

  final void Function(String text) onText;
  late final ByteConversionSink _sink;

  void add(Uint8List bytes) => _sink.add(bytes);

  void close() => _sink.close();
}

class _StringSinkProxy implements Sink<String> {
  _StringSinkProxy(this.onText);
  final void Function(String text) onText;
  @override
  void add(String data) => onText(data);
  @override
  void close() {}
}

/// Normalizes a command for PTY execution, using exactly one carriage return.
String normalizePtyCommand(String command) {
  return '${command.replaceFirst(RegExp(r'[\r\n]+$'), '')}\r';
}
