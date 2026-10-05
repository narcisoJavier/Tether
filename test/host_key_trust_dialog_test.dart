import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tether/models/connection_profile.dart';
import 'package:tether/models/host_key_record.dart';
import 'package:tether/services/host_key_verifier.dart';
import 'package:tether/widgets/host_key_trust_dialog.dart';

void main() {
  testWidgets(
    'unknown-key dialog exposes accessible trust details and reject',
    (tester) async {
      final semantics = tester.ensureSemantics();
      HostKeyTrustDecision? result;
      final challenge = HostKeyChallenge(
        presented: _record(fingerprint: 'SHA256:unknown'),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showHostKeyTrustDialog(
                    context: context,
                    challenge: challenge,
                    timeout: const Duration(minutes: 1),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsLabel('Unknown SSH host key warning'),
        findsOneWidget,
      );
      expect(find.text('Verify new SSH host'), findsOneWidget);
      expect(find.text('direct://host.example:22'), findsOneWidget);
      expect(find.text('SHA256:unknown'), findsOneWidget);
      expect(find.byTooltip('Copy fingerprint'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Reject'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Trust host'), findsOneWidget);

      await tester.tap(find.text('Reject'));
      await tester.pumpAndSettle();
      expect(result, HostKeyTrustDecision.reject);
      semantics.dispose();
    },
  );

  testWidgets('unknown-key trust action returns explicit acceptance', (
    tester,
  ) async {
    HostKeyTrustDecision? result;
    final challenge = HostKeyChallenge(
      presented: _record(fingerprint: 'SHA256:unknown'),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showHostKeyTrustDialog(
                  context: context,
                  challenge: challenge,
                  timeout: const Duration(minutes: 1),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trust host'));
    await tester.pumpAndSettle();

    expect(result, HostKeyTrustDecision.trust);
  });

  testWidgets('unknown-key dialog timeout rejects the connection', (
    tester,
  ) async {
    HostKeyTrustDecision? result;
    final challenge = HostKeyChallenge(
      presented: _record(fingerprint: 'SHA256:unknown'),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showHostKeyTrustDialog(
                  context: context,
                  challenge: challenge,
                  timeout: const Duration(seconds: 1),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(result, HostKeyTrustDecision.reject);
    expect(find.text('Verify new SSH host'), findsNothing);
  });

  testWidgets('changed-key dialog distinguishes fingerprints and replaces', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final verifier = _FakeHostKeyVerifier();
    final change = HostKeyChangedException(
      trusted: _record(fingerprint: 'SHA256:old'),
      presented: _record(fingerprint: 'SHA256:new'),
    );
    HostKeyReplacementResult? result;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showHostKeyChangedDialog(
                  context: context,
                  change: change,
                  verifier: verifier,
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsLabel('Critical SSH host key changed warning'),
      findsOneWidget,
    );
    expect(find.text('SSH host key changed'), findsOneWidget);
    expect(find.text('SHA256:old'), findsOneWidget);
    expect(find.text('SHA256:new'), findsOneWidget);
    expect(find.text('Keep existing key'), findsOneWidget);
    expect(find.text('Replace trusted key'), findsOneWidget);

    await tester.tap(find.text('Replace trusted key'));
    await tester.pumpAndSettle();

    expect(verifier.replaced, same(change));
    expect(result, HostKeyReplacementResult.replaced);
    semantics.dispose();
  });

  testWidgets('changed-key replacement cannot be dismissed while writing', (
    tester,
  ) async {
    final replacement = Completer<void>();
    final verifier = _FakeHostKeyVerifier(replacement: replacement);
    final change = HostKeyChangedException(
      trusted: _record(fingerprint: 'SHA256:old'),
      presented: _record(fingerprint: 'SHA256:new'),
    );
    HostKeyReplacementResult? result;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showHostKeyChangedDialog(
                  context: context,
                  change: change,
                  verifier: verifier,
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Replace trusted key'));
    await tester.pump();

    expect(find.text('Replacing key…'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(result, isNull);
    expect(find.text('SSH host key changed'), findsOneWidget);

    replacement.complete();
    await tester.pumpAndSettle();
    expect(result, HostKeyReplacementResult.replaced);
  });

  testWidgets(
    'changed-key replacement failure stays blocked and reports error',
    (tester) async {
      final verifier = _FakeHostKeyVerifier(
        replacementError: StateError('storage unavailable'),
      );
      final change = HostKeyChangedException(
        trusted: _record(fingerprint: 'SHA256:old'),
        presented: _record(fingerprint: 'SHA256:new'),
      );
      HostKeyReplacementResult? result;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showHostKeyChangedDialog(
                    context: context,
                    change: change,
                    verifier: verifier,
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Replace trusted key'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Replacement failed:'), findsOneWidget);
      expect(result, isNull);
      expect(find.text('Replace trusted key'), findsOneWidget);

      await tester.tap(find.text('Keep existing key'));
      await tester.pumpAndSettle();
      expect(result, HostKeyReplacementResult.cancelled);
    },
  );

  testWidgets('changed-key keep action leaves trust unchanged', (tester) async {
    final verifier = _FakeHostKeyVerifier();
    final change = HostKeyChangedException(
      trusted: _record(fingerprint: 'SHA256:old'),
      presented: _record(fingerprint: 'SHA256:new'),
    );
    HostKeyReplacementResult? result;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showHostKeyChangedDialog(
                  context: context,
                  change: change,
                  verifier: verifier,
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep existing key'));
    await tester.pumpAndSettle();

    expect(result, HostKeyReplacementResult.cancelled);
    expect(verifier.replaced, isNull);
  });
}

HostKeyRecord _record({required String fingerprint}) {
  final observed = DateTime.utc(2026, 10, 4);
  return HostKeyRecord(
    endpoint: HostEndpoint(
      host: 'host.example',
      port: 22,
      connectionMethod: ConnectionMethod.direct,
    ),
    algorithm: 'ssh-ed25519',
    fingerprint: fingerprint,
    firstSeen: observed,
    lastSeen: observed,
  );
}

class _FakeHostKeyVerifier implements HostKeyVerifier {
  _FakeHostKeyVerifier({this.replacement, this.replacementError});

  final Completer<void>? replacement;
  final Object? replacementError;
  HostKeyChangedException? replaced;

  @override
  Duration get decisionTimeout => const Duration(minutes: 1);

  @override
  Future<void> replace(HostKeyChangedException change) async {
    replaced = change;
    if (replacementError case final error?) throw error;
    await replacement?.future;
  }

  @override
  Future<bool> verify({
    required HostEndpoint endpoint,
    required String algorithm,
    required String fingerprint,
    required HostKeyDecisionHandler onDecision,
  }) => throw UnimplementedError();
}
