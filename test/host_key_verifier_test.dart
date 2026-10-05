import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart' as dartssh2;
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:tether/models/connection_profile.dart';
import 'package:tether/models/host_key_record.dart';
import 'package:tether/services/hive_adapters.dart';
import 'package:tether/services/host_key_verifier.dart';
import 'package:tether/services/ssh_service.dart';

void main() {
  group('HostEndpoint', () {
    test('canonicalizes DNS names and IPv6 literals', () {
      final dns = HostEndpoint(
        host: '  SSH.Example.COM. ',
        port: 22,
        connectionMethod: ConnectionMethod.direct,
      );
      final ipv6 = HostEndpoint(
        host: '[2001:DB8::10]',
        port: 2222,
        connectionMethod: ConnectionMethod.direct,
      );

      expect(dns.host, 'ssh.example.com');
      expect(dns.canonicalKey, 'direct|ssh.example.com|22');
      expect(ipv6.host, '2001:db8::10');
      expect(ipv6.displayName, 'direct://[2001:db8::10]:2222');

      final expandedIpv6 = HostEndpoint(
        host: '2001:0db8:0000:0000:0000:0000:0000:0010',
        port: 2222,
        connectionMethod: ConnectionMethod.direct,
      );
      expect(expandedIpv6, ipv6);

      final escaped = HostEndpoint(
        host: 'name|segment',
        port: 22,
        connectionMethod: ConnectionMethod.direct,
      );
      expect(escaped.canonicalKey, 'direct|name%7Csegment|22');
    });

    test('keeps direct and Tailscale trust identities distinct', () {
      final direct = HostEndpoint(
        host: 'server.example',
        port: 22,
        connectionMethod: ConnectionMethod.direct,
      );
      final tailscale = HostEndpoint(
        host: 'server.example',
        port: 22,
        connectionMethod: ConnectionMethod.tailscale,
      );

      expect(direct, isNot(tailscale));
      expect(direct.canonicalKey, isNot(tailscale.canonicalKey));
    });

    test('rejects empty hosts and invalid ports', () {
      expect(
        () => HostEndpoint(
          host: ' ',
          port: 22,
          connectionMethod: ConnectionMethod.direct,
        ),
        throwsArgumentError,
      );
      expect(
        () => HostEndpoint(
          host: 'host',
          port: 0,
          connectionMethod: ConnectionMethod.direct,
        ),
        throwsRangeError,
      );
    });
  });

  group('PersistentHostKeyVerifier', () {
    late _MemoryHostKeyStore store;
    late DateTime now;
    late PersistentHostKeyVerifier verifier;
    late HostEndpoint endpoint;

    setUp(() {
      store = _MemoryHostKeyStore();
      now = DateTime.utc(2026, 10, 4, 1);
      verifier = PersistentHostKeyVerifier(store: store, clock: () => now);
      endpoint = HostEndpoint(
        host: 'host.example',
        port: 22,
        connectionMethod: ConnectionMethod.direct,
      );
    });

    test('unknown key is stored only after explicit acceptance', () async {
      final accepted = await verifier.verify(
        endpoint: endpoint,
        algorithm: 'ssh-ed25519',
        fingerprint: 'SHA256:new',
        onDecision: (challenge) async {
          expect(challenge.presented.endpoint, endpoint);
          return HostKeyTrustDecision.trust;
        },
      );

      expect(accepted, isTrue);
      final stored = await store.read(endpoint);
      expect(stored?.algorithm, 'ssh-ed25519');
      expect(stored?.fingerprint, 'SHA256:new');
      expect(stored?.firstSeen, now);
      expect(stored?.lastSeen, now);
    });

    test('unknown key rejection leaves no trust record', () async {
      final accepted = await verifier.verify(
        endpoint: endpoint,
        algorithm: 'ssh-ed25519',
        fingerprint: 'SHA256:new',
        onDecision: (_) async => HostKeyTrustDecision.reject,
      );

      expect(accepted, isFalse);
      expect(await store.read(endpoint), isNull);
    });

    test('decision handler errors reject without persisting', () async {
      final accepted = await verifier.verify(
        endpoint: endpoint,
        algorithm: 'ssh-ed25519',
        fingerprint: 'SHA256:new',
        onDecision: (_) => throw StateError('Prompt was dismissed.'),
      );

      expect(accepted, isFalse);
      expect(await store.read(endpoint), isNull);
    });

    test(
      'known matching key succeeds without prompting and updates lastSeen',
      () async {
        await verifier.verify(
          endpoint: endpoint,
          algorithm: 'ssh-ed25519',
          fingerprint: 'SHA256:known',
          onDecision: (_) async => HostKeyTrustDecision.trust,
        );
        now = now.add(const Duration(hours: 2));

        final accepted = await verifier.verify(
          endpoint: endpoint,
          algorithm: 'ssh-ed25519',
          fingerprint: 'SHA256:known',
          onDecision: (_) => throw StateError('Known keys must not prompt.'),
        );

        expect(accepted, isTrue);
        final stored = await store.read(endpoint);
        expect(stored?.firstSeen, DateTime.utc(2026, 10, 4, 1));
        expect(stored?.lastSeen, now);
      },
    );

    test('changed key hard-fails and remains unchanged', () async {
      await verifier.verify(
        endpoint: endpoint,
        algorithm: 'ssh-ed25519',
        fingerprint: 'SHA256:old',
        onDecision: (_) async => HostKeyTrustDecision.trust,
      );

      await expectLater(
        verifier.verify(
          endpoint: endpoint,
          algorithm: 'ssh-ed25519',
          fingerprint: 'SHA256:new',
          onDecision: (_) => throw StateError('Mismatch must not prompt.'),
        ),
        throwsA(
          isA<HostKeyChangedException>()
              .having(
                (error) => error.trusted.fingerprint,
                'old fingerprint',
                'SHA256:old',
              )
              .having(
                (error) => error.presented.fingerprint,
                'new fingerprint',
                'SHA256:new',
              ),
        ),
      );
      expect((await store.read(endpoint))?.fingerprint, 'SHA256:old');
    });

    test(
      'changed key replacement is explicit and requires reconnect',
      () async {
        await verifier.verify(
          endpoint: endpoint,
          algorithm: 'ssh-ed25519',
          fingerprint: 'SHA256:old',
          onDecision: (_) async => HostKeyTrustDecision.trust,
        );
        late HostKeyChangedException change;
        try {
          await verifier.verify(
            endpoint: endpoint,
            algorithm: 'ssh-rsa',
            fingerprint: 'SHA256:new',
            onDecision: (_) async => HostKeyTrustDecision.reject,
          );
          fail('A changed key must throw.');
        } on HostKeyChangedException catch (error) {
          change = error;
        }

        now = now.add(const Duration(minutes: 5));
        await verifier.replace(change);
        final replaced = await store.read(endpoint);
        expect(replaced?.algorithm, 'ssh-rsa');
        expect(replaced?.fingerprint, 'SHA256:new');
        expect(replaced?.firstSeen, now);

        final accepted = await verifier.verify(
          endpoint: endpoint,
          algorithm: 'ssh-rsa',
          fingerprint: 'SHA256:new',
          onDecision: (_) => throw StateError('Replacement should now match.'),
        );
        expect(accepted, isTrue);
      },
    );

    test('decision timeout rejects without persisting', () async {
      verifier = PersistentHostKeyVerifier(
        store: store,
        clock: () => now,
        decisionTimeout: const Duration(milliseconds: 10),
      );
      final never = Completer<HostKeyTrustDecision>();

      final accepted = await verifier.verify(
        endpoint: endpoint,
        algorithm: 'ssh-ed25519',
        fingerprint: 'SHA256:new',
        onDecision: (_) => never.future,
      );

      expect(accepted, isFalse);
      expect(await store.read(endpoint), isNull);
    });
  });

  test('dartssh2 authentication wrapper preserves changed-key details', () {
    final observed = DateTime.utc(2026, 10, 4);
    final endpoint = HostEndpoint(
      host: 'host.example',
      port: 22,
      connectionMethod: ConnectionMethod.direct,
    );
    final change = HostKeyChangedException(
      trusted: HostKeyRecord(
        endpoint: endpoint,
        algorithm: 'ssh-ed25519',
        fingerprint: 'SHA256:old',
        firstSeen: observed,
        lastSeen: observed,
      ),
      presented: HostKeyRecord(
        endpoint: endpoint,
        algorithm: 'ssh-ed25519',
        fingerprint: 'SHA256:new',
        firstSeen: observed,
        lastSeen: observed,
      ),
    );
    final wrapped = dartssh2.SSHAuthAbortError(
      'Connection closed before authentication',
      change,
    );

    expect(unwrapHostKeyChangedException(wrapped), same(change));
  });

  group('HiveHostKeyStore', () {
    late Directory directory;

    setUpAll(() async {
      directory = await Directory.systemTemp.createTemp('tether_host_keys_');
      Hive.init(directory.path);
      registerHiveAdapters();
    });

    tearDownAll(() async {
      await Hive.close();
      await directory.delete(recursive: true);
    });

    test('persists records across box reopen', () async {
      var box = await Hive.openBox<HostKeyRecord>('host_key_store_test');
      var store = HiveHostKeyStore(box);
      final endpoint = HostEndpoint(
        host: 'persist.example',
        port: 2222,
        connectionMethod: ConnectionMethod.tailscale,
      );
      final record = HostKeyRecord(
        endpoint: endpoint,
        algorithm: 'ssh-ed25519',
        fingerprint: 'SHA256:persisted',
        firstSeen: DateTime.utc(2026, 1, 1),
        lastSeen: DateTime.utc(2026, 1, 2),
      );

      await store.write(record);
      await box.close();
      box = await Hive.openBox<HostKeyRecord>('host_key_store_test');
      store = HiveHostKeyStore(box);

      final restored = await store.read(endpoint);
      expect(restored?.endpoint, endpoint);
      expect(restored?.algorithm, 'ssh-ed25519');
      expect(restored?.fingerprint, 'SHA256:persisted');
      expect(restored?.firstSeen, DateTime.utc(2026, 1, 1));
      expect(restored?.lastSeen, DateTime.utc(2026, 1, 2));
    });
  });
}

class _MemoryHostKeyStore implements HostKeyStore {
  final Map<String, HostKeyRecord> _records = {};

  @override
  Future<HostKeyRecord?> read(HostEndpoint endpoint) async =>
      _records[endpoint.canonicalKey];

  @override
  Future<void> write(HostKeyRecord record) async {
    _records[record.endpoint.canonicalKey] = record;
  }
}
