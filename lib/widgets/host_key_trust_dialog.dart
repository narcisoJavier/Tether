import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/host_key_record.dart';
import '../services/host_key_verifier.dart';
import '../utils/constants.dart';

/// Result of reviewing a changed SSH host key.
enum HostKeyReplacementResult { cancelled, replaced }

/// Shows the explicit first-use host-key trust prompt.
Future<HostKeyTrustDecision> showHostKeyTrustDialog({
  required BuildContext context,
  required HostKeyChallenge challenge,
  required Duration timeout,
}) async {
  if (!context.mounted) return HostKeyTrustDecision.reject;
  final result = await showDialog<HostKeyTrustDecision>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    builder: (context) =>
        HostKeyTrustDialog(challenge: challenge, timeout: timeout),
  );
  return result ?? HostKeyTrustDecision.reject;
}

/// Shows a blocking changed-key warning with a separate replacement action.
Future<HostKeyReplacementResult> showHostKeyChangedDialog({
  required BuildContext context,
  required HostKeyChangedException change,
  required HostKeyVerifier verifier,
}) async {
  if (!context.mounted) return HostKeyReplacementResult.cancelled;
  final result = await showDialog<HostKeyReplacementResult>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    builder: (context) =>
        HostKeyChangedDialog(change: change, verifier: verifier),
  );
  return result ?? HostKeyReplacementResult.cancelled;
}

/// Dialog for a previously unseen SSH host key.
class HostKeyTrustDialog extends StatefulWidget {
  const HostKeyTrustDialog({
    super.key,
    required this.challenge,
    required this.timeout,
  });

  final HostKeyChallenge challenge;
  final Duration timeout;

  @override
  State<HostKeyTrustDialog> createState() => _HostKeyTrustDialogState();
}

class _HostKeyTrustDialogState extends State<HostKeyTrustDialog> {
  Timer? _timer;
  bool _resolved = false;
  String? _copiedLabel;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.timeout, () {
      if (mounted) _resolve(HostKeyTrustDecision.reject);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _copyFingerprint(String label, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    setState(() => _copiedLabel = label);
  }

  void _resolve(HostKeyTrustDecision decision) {
    if (_resolved || !mounted) return;
    _resolved = true;
    _timer?.cancel();
    Navigator.of(context).pop(decision);
  }

  @override
  Widget build(BuildContext context) {
    final record = widget.challenge.presented;
    final theme = Theme.of(context);
    return PopScope<HostKeyTrustDecision>(
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) return;
        _resolved = true;
        _timer?.cancel();
      },
      child: AlertDialog(
        semanticLabel: 'Unknown SSH host key warning',
        backgroundColor: AppConstants.surfaceDark,
        icon: Icon(
          Icons.shield_outlined,
          color: theme.colorScheme.primary,
          semanticLabel: 'Security verification',
        ),
        title: const Text('Verify new SSH host'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'This host has not been trusted on this device. Compare the '
                'fingerprint with a trusted source before continuing.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              _EndpointDetails(record: record),
              const SizedBox(height: 12),
              _FingerprintPanel(
                semanticPrefix: 'New host key',
                fingerprint: record.fingerprint,
                onCopy: () =>
                    _copyFingerprint('Fingerprint copied', record.fingerprint),
              ),
              const SizedBox(height: 12),
              Text(
                'The connection will be rejected automatically if no decision '
                'is made within ${widget.timeout.inSeconds} seconds.',
                style: theme.textTheme.bodySmall,
              ),
              if (_copiedLabel != null) ...[
                const SizedBox(height: 8),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _copiedLabel!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => _resolve(HostKeyTrustDecision.reject),
            child: const Text('Reject'),
          ),
          FilledButton.icon(
            onPressed: () => _resolve(HostKeyTrustDecision.trust),
            icon: const Icon(Icons.verified_user_outlined),
            label: const Text('Trust host'),
          ),
        ],
      ),
    );
  }
}

/// Dialog shown after a trusted endpoint presents a different key.
class HostKeyChangedDialog extends StatefulWidget {
  const HostKeyChangedDialog({
    super.key,
    required this.change,
    required this.verifier,
  });

  final HostKeyChangedException change;
  final HostKeyVerifier verifier;

  @override
  State<HostKeyChangedDialog> createState() => _HostKeyChangedDialogState();
}

class _HostKeyChangedDialogState extends State<HostKeyChangedDialog> {
  bool _isReplacing = false;
  String? _error;
  String? _copiedLabel;

  Future<void> _copyFingerprint(String label, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    setState(() => _copiedLabel = label);
  }

  Future<void> _replace() async {
    setState(() {
      _isReplacing = true;
      _error = null;
    });
    try {
      await widget.verifier.replace(widget.change);
      if (!mounted) return;
      Navigator.of(context).pop(HostKeyReplacementResult.replaced);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isReplacing = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final errorColor = theme.colorScheme.error;
    return PopScope<HostKeyReplacementResult>(
      canPop: !_isReplacing,
      child: AlertDialog(
        semanticLabel: 'Critical SSH host key changed warning',
        backgroundColor: AppConstants.surfaceDark,
        icon: Icon(
          Icons.gpp_bad_outlined,
          color: errorColor,
          semanticLabel: 'Critical security warning',
        ),
        title: const Text('SSH host key changed'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'The connection was blocked before authentication. This may '
                'indicate a rebuilt server or a person-in-the-middle attack.',
                style: theme.textTheme.bodyMedium?.copyWith(color: errorColor),
              ),
              const SizedBox(height: 16),
              _EndpointDetails(record: widget.change.presented),
              const SizedBox(height: 12),
              Text(
                'Previously trusted (${widget.change.trusted.algorithm})',
                style: theme.textTheme.labelLarge,
              ),
              const SizedBox(height: 6),
              _FingerprintPanel(
                semanticPrefix: 'Previously trusted host key',
                fingerprint: widget.change.trusted.fingerprint,
                onCopy: () => _copyFingerprint(
                  'Old fingerprint copied',
                  widget.change.trusted.fingerprint,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Presented now (${widget.change.presented.algorithm})',
                style: theme.textTheme.labelLarge?.copyWith(color: errorColor),
              ),
              const SizedBox(height: 6),
              _FingerprintPanel(
                semanticPrefix: 'New untrusted host key',
                fingerprint: widget.change.presented.fingerprint,
                onCopy: () => _copyFingerprint(
                  'New fingerprint copied',
                  widget.change.presented.fingerprint,
                ),
                isCritical: true,
              ),
              const SizedBox(height: 12),
              Text(
                'Only replace the trusted key after verifying the new '
                'fingerprint through another trusted channel. You must connect '
                'again after replacement.',
                style: theme.textTheme.bodySmall,
              ),
              if (_copiedLabel != null) ...[
                const SizedBox(height: 8),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _copiedLabel!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    'Replacement failed: $_error',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: errorColor,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _isReplacing
                ? null
                : () => Navigator.of(
                    context,
                  ).pop(HostKeyReplacementResult.cancelled),
            child: const Text('Keep existing key'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: errorColor,
              foregroundColor: theme.colorScheme.onError,
            ),
            onPressed: _isReplacing ? null : _replace,
            icon: _isReplacing
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync_lock_outlined),
            label: Text(
              _isReplacing ? 'Replacing key…' : 'Replace trusted key',
            ),
          ),
        ],
      ),
    );
  }
}

class _EndpointDetails extends StatelessWidget {
  const _EndpointDetails({required this.record});

  final HostKeyRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label:
          'SSH endpoint ${record.endpoint.displayName}, algorithm '
          '${record.algorithm}',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(
                record.endpoint.displayName,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 4),
              Text(record.algorithm, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _FingerprintPanel extends StatelessWidget {
  const _FingerprintPanel({
    required this.semanticPrefix,
    required this.fingerprint,
    required this.onCopy,
    this.isCritical = false,
  });

  final String semanticPrefix;
  final String fingerprint;
  final VoidCallback onCopy;
  final bool isCritical;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isCritical
        ? theme.colorScheme.error
        : theme.colorScheme.primary;
    return Semantics(
      label: '$semanticPrefix fingerprint $fingerprint',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          border: Border.all(color: color.withValues(alpha: 0.35)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
          child: Row(
            children: [
              Expanded(
                child: SelectableText(
                  fingerprint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    color: color,
                  ),
                ),
              ),
              IconButton(
                onPressed: onCopy,
                tooltip: 'Copy fingerprint',
                icon: const Icon(Icons.copy_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
