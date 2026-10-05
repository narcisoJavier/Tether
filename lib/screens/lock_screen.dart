import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/biometric_provider.dart';
import '../utils/constants.dart';

/// Keeps mounted routes and SSH sessions inaccessible while app access is locked.
class AppLockGate extends ConsumerWidget {
  final Widget child;

  const AppLockGate({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lock = ref.watch(appLockProvider);
    final hidden = lock.requiresAuthentication || lock.obscured;
    return Stack(
      fit: StackFit.expand,
      children: [
        ExcludeFocus(
          excluding: hidden,
          child: ExcludeSemantics(
            excluding: hidden,
            child: Offstage(
              offstage: hidden,
              child: TickerMode(enabled: !hidden, child: child),
            ),
          ),
        ),
        if (lock.requiresAuthentication)
          const Positioned.fill(child: LockScreen())
        else if (lock.obscured)
          const Positioned.fill(
            child: ColoredBox(
              color: AppConstants.backgroundDark,
              child: Center(
                child: Icon(
                  Icons.lock_outline_rounded,
                  semanticLabel: 'Tether is hidden while in the background',
                  color: AppConstants.primaryGreen,
                  size: 48,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Fail-closed device-authentication gate with accessible recovery instructions.
class LockScreen extends ConsumerWidget {
  const LockScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lock = ref.watch(appLockProvider);
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final title = switch (lock.status) {
      AppLockStatus.authenticating => 'Authenticating',
      AppLockStatus.unavailable => 'Authentication unavailable',
      AppLockStatus.temporaryLockout => 'Try again later',
      AppLockStatus.permanentLockout => 'Unlock your device first',
      _ => 'Tether is locked',
    };
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppConstants.backgroundDark,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(
                      Icons.lock_outline_rounded,
                      size: 56,
                      color: AppConstants.primaryGreen,
                    ),
                    const SizedBox(height: 24),
                    Semantics(
                      header: true,
                      liveRegion: true,
                      child: Text(
                        title,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Use your device fingerprint, face, PIN, pattern, or '
                      'password to unlock Tether.',
                      textAlign: TextAlign.center,
                    ),
                    if (lock.message != null) ...[
                      const SizedBox(height: 20),
                      Semantics(
                        liveRegion: true,
                        child: Text(lock.message!, textAlign: TextAlign.center),
                      ),
                    ],
                    if (lock.busy) ...[
                      const SizedBox(height: 24),
                      Center(
                        child: reducedMotion
                            ? const Icon(Icons.more_horiz, size: 32)
                            : const SizedBox(
                                height: 28,
                                width: 28,
                                child: CircularProgressIndicator(
                                  semanticsLabel:
                                      'Waiting for device authentication',
                                ),
                              ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: lock.busy ? null : lock.unlock,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        padding: const EdgeInsets.all(16),
                      ),
                      child: Text(
                        lock.busy
                            ? 'Authentication in progress'
                            : lock.status == AppLockStatus.locked &&
                                  lock.message == null
                            ? 'Unlock Tether'
                            : 'Retry authentication',
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ExpansionTile(
                      expansionAnimationStyle: reducedMotion
                          ? AnimationStyle.noAnimation
                          : null,
                      title: const Text('Device settings and recovery'),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      children: const [
                        Text(
                          'Open Android Settings and find Security or Screen lock. '
                          'Set up or restore your device PIN, pattern, password, '
                          'or biometrics. If biometrics are locked, unlock the '
                          'phone with its screen lock first. Return here and '
                          'retry authentication.\n\n'
                          'Tether stays locked until device authentication succeeds.',
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'App lock is required on restart and after 30 seconds '
                      'in the background.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
