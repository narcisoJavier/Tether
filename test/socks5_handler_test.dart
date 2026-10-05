import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tether/services/socks5_handler.dart';

void main() {
  group('Socks5Parser', () {
    test('parses IPv4 CONNECT', () {
      final request = Socks5Parser.parseConnect([
        5,
        1,
        0,
        1,
        192,
        0,
        2,
        7,
        0x01,
        0xbb,
      ]);
      expect(request.host, '192.0.2.7');
      expect(request.port, 443);
    });

    test('parses domain CONNECT', () {
      final host = 'example.test'.codeUnits;
      final request = Socks5Parser.parseConnect([
        5,
        1,
        0,
        3,
        host.length,
        ...host,
        0x23,
        0x82,
      ]);
      expect(request.host, 'example.test');
      expect(request.port, 9090);
    });

    test('parses IPv6 CONNECT', () {
      final request = Socks5Parser.parseConnect([
        5,
        1,
        0,
        4,
        0x20,
        0x01,
        0x0d,
        0xb8,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        1,
        0x01,
        0xbb,
      ]);
      expect(request.host, '2001:db8:0:0:0:0:0:1');
      expect(request.port, 443);
    });

    test('rejects malformed and unsupported requests', () {
      final invalid = <List<int>>[
        [4, 1, 0, 1, 127, 0, 0, 1, 0, 80],
        [5, 1, 1, 1, 127, 0, 0, 1, 0, 80],
        [5, 1, 0, 1, 127, 0, 0, 1, 0],
        [5, 1, 0, 3, 0, 0, 80],
        [5, 1, 0, 4, ...List<int>.filled(16, 0), 0],
        [5, 1, 0, 5, 0, 0],
      ];
      for (final bytes in invalid) {
        expect(() => Socks5Parser.parseConnect(bytes), throwsFormatException);
      }
    });
  });

  test(
    'handles fragmented greeting/request and preserves coalesced payload',
    () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final connected = Completer<Socket>();
      final target = Completer<Socks5Request>();
      final forwarded = StreamController<Uint8List>.broadcast();
      final payload = <int>[];
      final payloadReady = Completer<void>();
      forwarded.stream.listen((bytes) {
        payload.addAll(bytes);
        if (payload.length >= 6 && !payloadReady.isCompleted) {
          payloadReady.complete();
        }
      });
      final handlerDone = Completer<void>();
      server.listen((socket) async {
        connected.complete(socket);
        await const Socks5Handler(timeout: Duration(seconds: 2)).handle(
          socket,
          (host, port) async {
            target.complete(Socks5Request(host, port));
            return forwarded;
          },
        );
        handlerDone.complete();
      });

      final client = await Socket.connect(
        InternetAddress.loopbackIPv4,
        server.port,
      );
      final response = <int>[];
      final responseReady = Completer<void>();
      client.listen((data) {
        response.addAll(data);
        if (response.length >= 12 && !responseReady.isCompleted) {
          responseReady.complete();
        }
      });
      client.add([5]);
      await Future<void>.delayed(Duration.zero);
      client.add([1, 0]);
      client.add([5, 1]);
      await Future<void>.delayed(Duration.zero);
      client.add([0, 3, 'example.test'.length, ...'example.test'.codeUnits]);
      client.add([0x01, 0xbb, 9, 8, 7]);

      await responseReady.future.timeout(const Duration(seconds: 2));
      final request = await target.future.timeout(const Duration(seconds: 2));
      expect(response.take(2), [5, 0]);
      expect(response.skip(2).take(10), [5, 0, 0, 1, 0, 0, 0, 0, 0, 0]);
      expect(request.host, 'example.test');
      expect(request.port, 443);
      client.add([6, 5, 4]);
      await payloadReady.future.timeout(const Duration(seconds: 2));
      expect(payload, [9, 8, 7, 6, 5, 4]);

      client.destroy();
      await handlerDone.future.timeout(const Duration(seconds: 2));
      await server.close();
    },
  );

  test(
    'returns no-acceptable-methods response when auth is unsupported',
    () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final response = Completer<List<int>>();
      final done = Completer<void>();
      server.listen((socket) async {
        await const Socks5Handler().handle(socket, (_, _) async {
          throw StateError('forward must not be called');
        });
        done.complete();
      });
      final client = await Socket.connect(
        InternetAddress.loopbackIPv4,
        server.port,
      );
      final bytes = <int>[];
      client.listen((data) {
        bytes.addAll(data);
        if (bytes.length >= 2 && !response.isCompleted) {
          response.complete(bytes.sublist(0, 2));
        }
      });
      client.add([5, 1, 2]);
      expect(await response.future.timeout(const Duration(seconds: 2)), [
        5,
        255,
      ]);
      client.destroy();
      await done.future.timeout(const Duration(seconds: 2));
      await server.close();
    },
  );
}
