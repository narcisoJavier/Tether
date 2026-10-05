import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// A parsed SOCKS5 CONNECT target.
class Socks5Request {
  const Socks5Request(this.host, this.port);
  final String host;
  final int port;
}

/// SOCKS5 framing and CONNECT request parser.
class Socks5Parser {
  const Socks5Parser._();

  static Socks5Request parseConnect(List<int> bytes) {
    if (bytes.length < 4 || bytes[0] != 5 || bytes[1] != 1 || bytes[2] != 0) {
      throw const FormatException('Invalid SOCKS5 CONNECT request');
    }
    final type = bytes[3];
    var offset = 4;
    String host;
    if (type == 1) {
      if (bytes.length != 10) {
        throw const FormatException('Invalid IPv4 request');
      }
      host = '${bytes[4]}.${bytes[5]}.${bytes[6]}.${bytes[7]}';
      offset = 8;
    } else if (type == 3) {
      if (bytes.length < 5) {
        throw const FormatException('Invalid domain request');
      }
      final length = bytes[4];
      if (length == 0 || bytes.length != 7 + length) {
        throw const FormatException('Invalid domain request');
      }
      host = String.fromCharCodes(bytes.sublist(5, 5 + length));
      offset = 5 + length;
    } else if (type == 4) {
      if (bytes.length != 22) {
        throw const FormatException('Invalid IPv6 request');
      }
      final groups = <String>[];
      for (var i = 0; i < 16; i += 2) {
        groups.add(((bytes[4 + i] << 8) | bytes[5 + i]).toRadixString(16));
      }
      host = groups.join(':');
      offset = 20;
    } else {
      throw const FormatException('Unsupported address type');
    }
    return Socks5Request(host, (bytes[offset] << 8) | bytes[offset + 1]);
  }
}

/// Handles one SOCKS5 client using an SSH forwarding callback.
class Socks5Handler {
  const Socks5Handler({this.timeout = const Duration(seconds: 10)});
  final Duration timeout;

  Future<void> handle(
    Socket socket,
    Future<dynamic> Function(String host, int port) forward,
  ) async {
    final reader = _BufferedReader(socket, timeout);
    try {
      final greeting = await reader.readExact(2);
      if (greeting[0] != 5) throw const FormatException('Invalid version');
      final methods = await reader.readExact(greeting[1]);
      if (!methods.contains(0)) {
        socket.add(const [5, 255]);
        await socket.flush();
        await reader.detach();
        socket.destroy();
        return;
      }
      socket.add(const [5, 0]);
      final head = await reader.readExact(4);
      if (head[0] != 5 ||
          head[1] != 1 ||
          head[2] != 0 ||
          !const [1, 3, 4].contains(head[3])) {
        throw const FormatException('Unsupported SOCKS5 request');
      }
      final length = head[3] == 1
          ? 4
          : (head[3] == 3 ? (await reader.readExact(1))[0] : 16);
      final address = await reader.readExact(length);
      final port = await reader.readExact(2);
      final request = Socks5Parser.parseConnect([
        ...head,
        if (head[3] == 3) length,
        ...address,
        ...port,
      ]);
      if (head[1] != 1) {
        throw const FormatException('Only CONNECT is supported');
      }
      final channel = await forward(request.host, request.port);
      socket.add(const [5, 0, 0, 1, 0, 0, 0, 0, 0, 0]);
      await Future.wait<void>([
        channel.stream.cast<List<int>>().pipe(socket).then<void>((_) {}),
        reader.remaining().pipe(channel.sink).then<void>((_) {}),
      ], eagerError: true);
    } catch (_) {
      try {
        await reader.detach();
      } catch (_) {}
      try {
        socket.add(const [5, 1, 0, 1, 0, 0, 0, 0, 0, 0]);
        await socket.flush();
      } catch (_) {}
    } finally {
      await reader.detach();
      socket.destroy();
    }
  }
}

class _BufferedReader {
  _BufferedReader(Socket socket, this.timeout)
    : _iterator = StreamIterator(socket);
  final Duration timeout;
  final _buffer = <int>[];
  final StreamIterator<Uint8List> _iterator;

  Future<List<int>> readExact(int count) async {
    while (_buffer.length < count) {
      if (!await _iterator.moveNext().timeout(timeout)) {
        throw const FormatException('Truncated SOCKS5 request');
      }
      _buffer.addAll(_iterator.current);
    }
    final result = _buffer.sublist(0, count);
    _buffer.removeRange(0, count);
    return result;
  }

  Stream<Uint8List> remaining() async* {
    if (_buffer.isNotEmpty) {
      final buffered = Uint8List.fromList(_buffer);
      _buffer.clear();
      yield buffered;
    }
    while (await _iterator.moveNext()) {
      yield _iterator.current;
    }
  }

  Future<void> detach() => _iterator.cancel();
}
