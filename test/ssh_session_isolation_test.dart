import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart' as ssh;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tether/models/connection_profile.dart';
import 'package:tether/models/terminal_tab.dart';
import 'package:tether/services/host_key_verifier.dart';
import 'package:tether/services/sftp_service.dart';
import 'package:tether/services/ssh_connection_factory.dart';
import 'package:tether/services/ssh_service.dart';
import 'package:tether/services/tab_manager.dart';
import 'package:tether/utils/terminal_io.dart';

final _profile = ConnectionProfile(
  id: 'shared-profile',
  label: 'Server',
  host: 'server.example',
  port: 22,
  username: 'user',
  authType: AuthType.password,
);

Future<HostKeyTrustDecision> _reject(HostKeyChallenge _) async =>
    HostKeyTrustDecision.reject;

void main() {
  test(
    'same-profile tabs have distinct clients, shells, input and resize',
    () async {
      final harness = _Harness();
      final container = harness.container();
      addTearDown(container.dispose);
      final leaseA = container.listen(
        sshServiceProvider('session-a'),
        (_, _) {},
      );
      final leaseB = container.listen(
        sshServiceProvider('session-b'),
        (_, _) {},
      );
      final a = leaseA.read();
      final b = leaseB.read();
      final manager = container.read(tabManagerProvider.notifier);
      manager.addTab(
        const TerminalTab(
          tabId: 'tab-a',
          sessionId: 'session-a',
          profileId: 'shared-profile',
          label: 'A',
        ),
      );
      manager.addTab(
        const TerminalTab(
          tabId: 'tab-b',
          sessionId: 'session-b',
          profileId: 'shared-profile',
          label: 'B',
        ),
      );
      await harness.connect(a);
      await harness.connect(b);
      final shellA = await a.startShell(cols: 80, rows: 24);
      final shellB = await b.startShell(cols: 100, rows: 40);
      expect(a, isNot(same(b)));
      expect(a.client, isNot(same(b.client)));
      expect(shellA.session, isNot(same(shellB.session)));
      final target = manager.tabsForProfile(_profile.id).last;
      container
          .read(sshServiceProvider(target.sessionId))
          .writeStdin(
            Uint8List.fromList(utf8.encode(normalizePtyCommand('echo target'))),
          );
      b.resizeShell(cols: 120, rows: 45);
      expect((shellA.session as _Session).input.values, isEmpty);
      expect((shellB.session as _Session).input.text, 'echo target\r');
      expect((shellA.session as _Session).sizes, isEmpty);
      expect((shellB.session as _Session).sizes, [(120, 45)]);
      expect(target.copyWith(isConnected: true).sessionId, 'session-b');
    },
  );

  test(
    'retrying and closing A preserves B and closes each client once',
    () async {
      final harness = _Harness();
      final container = harness.container();
      addTearDown(container.dispose);
      final leaseA = container.listen(sshServiceProvider('a'), (_, _) {});
      final leaseB = container.listen(sshServiceProvider('b'), (_, _) {});
      final a = leaseA.read();
      final b = leaseB.read();
      await harness.connect(a);
      await harness.connect(b);
      final oldA = a.client! as _Client;
      final clientB = b.client! as _Client;
      await b.startShell(cols: 80, rows: 24);
      await a.disconnect();
      await harness.connect(a);
      final retriedA = a.client! as _Client;
      expect(retriedA, isNot(same(oldA)));
      expect(b.client, same(clientB));
      expect(b.isConnected, isTrue);
      expect(oldA.closeCount, 1);
      a.dispose();
      leaseA.close();
      await container.pump();
      expect(retriedA.closeCount, 1);
      expect(clientB.closeCount, 0);
      b.writeStdin(Uint8List.fromList(utf8.encode('still here')));
      expect(clientB.shells.single.input.text, 'still here');
      leaseB.close();
      await container.pump();
      expect(clientB.closeCount, 1);
    },
  );

  test(
    'one-shot success and failure use private connections and always close',
    () async {
      final harness = _Harness();
      final terminal = harness.factory.createService();
      addTearDown(terminal.dispose);
      await harness.connect(terminal);
      final client = terminal.client! as _Client;
      await terminal.startShell(cols: 80, rows: 24);
      expect(
        await harness.factory.executeOnce(
          profile: _profile,
          command: 'status',
          onHostKeyDecision: _reject,
        ),
        'output: status',
      );
      final successful = harness.clients.last;
      expect(successful, isNot(same(client)));
      expect(successful.closeCount, 1);
      await expectLater(
        harness.factory.executeOnce(
          profile: _profile,
          command: 'fail',
          onHostKeyDecision: _reject,
        ),
        throwsStateError,
      );
      expect(harness.clients.last.closeCount, 1);
      expect(client.closeCount, 0);
      expect(terminal.client, same(client));
      expect(terminal.isConnected, isTrue);
    },
  );

  test(
    'credential failure still disposes a private one-shot service',
    () async {
      final harness = _Harness();
      late SshService service;
      final factory = SshConnectionFactory(
        createService: () => service = harness.createService(),
        loadPrivateKey: (_) async => null,
        loadPassword: (_) async => throw StateError('Keystore locked'),
        openSocket: (_) async => _Socket(),
        keepalive: const Duration(seconds: 30),
      );
      await expectLater(
        factory.executeOnce(
          profile: _profile,
          command: 'status',
          onHostKeyDecision: _reject,
        ),
        throwsStateError,
      );
      expect(service.isDisposed, isTrue);
      expect(harness.clients, isEmpty);
    },
  );

  test(
    'SFTP disconnect and dedicated service disposal leave terminal open',
    () async {
      final harness = _Harness();
      final terminal = harness.factory.createService();
      final browser = harness.factory.createService();
      addTearDown(terminal.dispose);
      await harness.connect(terminal);
      await harness.connect(browser);
      final terminalClient = terminal.client! as _Client;
      final browserClient = browser.client! as _Client;
      final sftp = SftpService();
      await sftp.connect(browserClient);
      await sftp.disconnect();
      sftp.dispose();
      browser.dispose();
      browser.dispose();
      expect(browserClient.files.closeCount, 1);
      expect(browserClient.closeCount, 1);
      expect(terminalClient.closeCount, 0);
      expect(terminal.isConnected, isTrue);
    },
  );

  test(
    'SFTP closes a channel that finishes opening after browser disposal',
    () async {
      final client = _Client();
      final pending = Completer<ssh.SftpClient>();
      client.pendingSftp = pending.future;
      final service = SftpService();
      final connection = service.connect(client);
      final failed = expectLater(connection, throwsStateError);
      service.dispose();
      pending.complete(client.files);
      await failed;
      expect(client.files.closeCount, 1);
      expect(client.closeCount, 0);
    },
  );

  test(
    'closing during transport setup closes the late socket without connecting',
    () async {
      final harness = _Harness();
      final service = harness.createService();
      final pending = Completer<ssh.SSHSocket?>();
      final started = Completer<void>();
      final socket = _Socket();
      final factory = SshConnectionFactory(
        createService: harness.createService,
        loadPrivateKey: (_) async => null,
        loadPassword: (_) async => null,
        openSocket: (_) {
          started.complete();
          return pending.future;
        },
        keepalive: const Duration(seconds: 30),
      );
      final connection = factory.connect(
        service: service,
        profile: _profile,
        onHostKeyDecision: _reject,
      );
      final failed = expectLater(connection, throwsStateError);
      await started.future;
      service.dispose();
      pending.complete(socket);
      await failed;
      expect(socket.closeCount, 1);
      expect(harness.clients, isEmpty);
    },
  );

  test('closing during shell creation closes the late shell', () async {
    final harness = _Harness();
    final service = harness.createService();
    await harness.connect(service);
    final client = service.client! as _Client;
    final pending = Completer<ssh.SSHSession>();
    client.pendingShell = pending.future;
    final opening = service.startShell(cols: 80, rows: 24);
    final failed = expectLater(opening, throwsStateError);
    service.dispose();
    final shell = _Session();
    pending.complete(shell);
    await failed;
    expect(shell.closeCount, 1);
    expect(client.closeCount, 1);
  });

  test('bad private key releases the socket before client ownership', () async {
    final service = _Harness().createService();
    addTearDown(service.dispose);
    final socket = _Socket();
    await expectLater(
      service.connect(
        profile: _profile,
        privateKey: 'invalid key',
        socket: socket,
        onHostKeyDecision: _reject,
      ),
      throwsA(isA<Exception>()),
    );
    expect(socket.closeCount, 1);
  });
}

class _Harness {
  final clients = <_Client>[];
  late final factory = SshConnectionFactory(
    createService: createService,
    loadPrivateKey: (_) async => null,
    loadPassword: (_) async => null,
    openSocket: (_) async => _Socket(),
    keepalive: const Duration(seconds: 30),
  );

  ProviderContainer container() => ProviderContainer(
    overrides: [sshServiceFactoryProvider.overrideWithValue(createService)],
  );

  SshService createService() => SshService(
    hostKeyVerifier: _Verifier(),
    clientFactory:
        (
          socket, {
          required username,
          required keepAliveInterval,
          required identities,
          required onPasswordRequest,
          required onVerifyHostKey,
        }) {
          final client = _Client();
          clients.add(client);
          return client;
        },
  );

  Future<ssh.SSHClient> connect(SshService service) => factory.connect(
    service: service,
    profile: _profile,
    onHostKeyDecision: _reject,
  );
}

class _Verifier implements HostKeyVerifier {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client implements ssh.SSHClient {
  int closeCount = 0;
  final shells = <_Session>[];
  final files = _Files();
  Future<ssh.SftpClient>? pendingSftp;
  Future<ssh.SSHSession>? pendingShell;

  @override
  Future<ssh.SSHSession> execute(
    String command, {
    ssh.SSHPtyConfig? pty,
    ssh.SSHX11Config? x11,
    Map<String, String>? environment,
  }) async {
    if (command == 'fail') throw StateError('Command failed');
    return _Session(output: command == 'true' ? '' : 'output: $command');
  }

  @override
  Future<ssh.SSHSession> shell({
    ssh.SSHPtyConfig? pty = const ssh.SSHPtyConfig(),
    ssh.SSHX11Config? x11,
    Map<String, String>? environment,
  }) async {
    if (pendingShell != null) return pendingShell!;
    final session = _Session();
    shells.add(session);
    return session;
  }

  @override
  Future<ssh.SftpClient> sftp() async => pendingSftp ?? files;

  @override
  void close() {
    closeCount++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Session implements ssh.SSHSession {
  _Session({this.output = ''});
  final String output;
  final input = _Sink();
  final sizes = <(int, int)>[];
  int closeCount = 0;

  @override
  StreamSink<Uint8List> get stdin => input;

  @override
  Stream<Uint8List> get stdout =>
      Stream.value(Uint8List.fromList(utf8.encode(output)));

  @override
  Future<void> get done async {}

  @override
  void resizeTerminal(
    int width,
    int height, [
    int pixelWidth = 0,
    int pixelHeight = 0,
  ]) {
    sizes.add((width, height));
  }

  @override
  void close() {
    closeCount++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Sink implements StreamSink<Uint8List> {
  final values = <Uint8List>[];
  String get text => utf8.decode(values.expand((bytes) => bytes).toList());

  @override
  void add(Uint8List data) => values.add(data);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Files implements ssh.SftpClient {
  int closeCount = 0;

  @override
  void close() {
    closeCount++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Socket implements ssh.SSHSocket {
  int closeCount = 0;

  @override
  Future<void> close() async {
    closeCount++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
