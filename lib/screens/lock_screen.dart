import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/biometric_service.dart';
import '../services/biometric_provider.dart';
import '../utils/constants.dart';

/// State of the lock screen's auth flow.
enum _LockState {
  checking, // Initial — checking if biometrics are available
  ready, // Waiting for user to tap authenticate
  authenticating, // Auth in progress
  success, // Auth succeeded (should trigger app switch)
  error, // Auth error (platform issue, lockout)
  unavailable, // No biometric hardware at all
}

/// Full-screen biometric lock gate shown before the main app.
///
/// Matches the dark glassmorphism aesthetic of the rest of Tether.
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  final BiometricService _biometricService = BiometricService();
  _LockState _lockState = _LockState.checking;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _checkBiometrics();
  }

  Future<void> _checkBiometrics() async {
    final available = await _biometricService.canAuthenticate();
    if (!mounted) return;
    setState(() {
      _lockState = available ? _LockState.ready : _LockState.unavailable;
    });
  }

  Future<void> _authenticate() async {
    setState(() {
      _lockState = _LockState.authenticating;
      _errorMessage = null;
    });

    try {
      final success = await _biometricService.authenticate(
        reason: 'Authenticate to open Tether',
        biometricOnly: false, // allow PIN/pattern fallback
      );

      if (!mounted) return;

      if (success) {
        setState(() => _lockState = _LockState.success);
        // Mark the session as authenticated — the gate widget in main.dart
        // watches authSessionProvider and will swap to TetherApp.
        ref.read(authSessionProvider.notifier).state = true;
      } else {
        // User cancelled or failed (OS handles retry; false = user gave up).
        setState(() => _lockState = _LockState.ready);
      }
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() {
        _lockState = _LockState.error;
        _errorMessage = _describePlatformException(e);
      });
    }
  }

  // PlatformException codes documented by local_auth plugin.
  static const _lockoutCodes = {'LockedOut', 'PermanentlyLockedOut'};

  String _describePlatformException(PlatformException e) {
    if (e.code == 'NotAvailable') {
      return 'No biometric hardware found';
    }
    if (_lockoutCodes.contains(e.code)) {
      return 'Too many attempts. Biometric authentication is locked. '
          'Use your device PIN or try again later.';
    }
    return 'Authentication error: ${e.message ?? "Unknown"}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.backgroundDark,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 48),
                _buildLogo(),
                const SizedBox(height: 40),
                _buildTitle(),
                const SizedBox(height: 8),
                _buildSubtitle(),
                const SizedBox(height: 48),
                _buildAuthSection(),
                const SizedBox(height: 48),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.15),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: AppConstants.primaryGreen.withValues(alpha: 0.15),
                blurRadius: 24,
                spreadRadius: 2,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Image.asset(
              'assets/logo.png',
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const Icon(
                Icons.terminal_rounded,
                size: 44,
                color: AppConstants.primaryGreen,
              ),
            ),
          ),
        )
        .animate()
        .fadeIn(duration: 600.ms, curve: Curves.easeOut)
        .scale(
          begin: const Offset(0.85, 0.85),
          end: const Offset(1, 1),
          duration: 600.ms,
          curve: Curves.easeOutBack,
        );
  }

  Widget _buildTitle() {
    return Text(
          'Tether',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 32,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            letterSpacing: 2,
          ),
        )
        .animate()
        .fadeIn(duration: 500.ms, delay: 200.ms, curve: Curves.easeOut)
        .slideY(begin: 0.1, end: 0, duration: 400.ms, curve: Curves.easeOut);
  }

  Widget _buildSubtitle() {
    return Text(
      'Pocket SSH & Mesh Terminal',
      style: GoogleFonts.inter(
        fontSize: 14,
        color: Colors.white.withValues(alpha: 0.4),
        letterSpacing: 1,
      ),
    ).animate().fadeIn(duration: 500.ms, delay: 300.ms, curve: Curves.easeOut);
  }

  Widget _buildAuthSection() {
    switch (_lockState) {
      case _LockState.checking:
        return _buildCheckingState();
      case _LockState.ready:
        return _buildReadyState();
      case _LockState.authenticating:
        return _buildAuthenticatingState();
      case _LockState.success:
        return _buildSuccessState();
      case _LockState.error:
        return _buildErrorState();
      case _LockState.unavailable:
        return _buildUnavailableState();
    }
  }

  Widget _buildCheckingState() {
    return const Column(
      children: [
        SizedBox(
          width: 36,
          height: 36,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: AppConstants.primaryGreen,
          ),
        ),
        SizedBox(height: 16),
        Text(
          'Checking device...',
          style: TextStyle(color: Colors.white38, fontSize: 13),
        ),
      ],
    );
  }

  Widget _buildReadyState() {
    return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: const Icon(
                Icons.fingerprint_rounded,
                size: 32,
                color: Colors.white38,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _authenticate,
                icon: const Icon(Icons.lock_open_rounded),
                label: Text(
                  'Authenticate',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        )
        .animate()
        .fadeIn(duration: 400.ms, curve: Curves.easeOut)
        .slideY(begin: 0.08, end: 0, duration: 350.ms, curve: Curves.easeOut);
  }

  Widget _buildAuthenticatingState() {
    return Column(
      children: [
        Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppConstants.primaryGreen.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: AppConstants.primaryGreen.withValues(alpha: 0.2),
                ),
              ),
              child: const Icon(
                Icons.fingerprint_rounded,
                size: 32,
                color: AppConstants.primaryGreen,
              ),
            )
            .animate(onPlay: (c) => c.repeat())
            .shimmer(
              duration: 1500.ms,
              color: AppConstants.primaryGreen.withValues(alpha: 0.2),
            ),
        const SizedBox(height: 20),
        const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppConstants.primaryGreen,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Authenticating...',
          style: GoogleFonts.inter(
            fontSize: 13,
            color: Colors.white.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }

  Widget _buildSuccessState() {
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: AppConstants.primaryGreen.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: AppConstants.primaryGreen.withValues(alpha: 0.2),
            ),
          ),
          child: const Icon(
            Icons.check_rounded,
            size: 36,
            color: AppConstants.primaryGreen,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Unlocked',
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppConstants.primaryGreen,
          ),
        ),
      ],
    );
  }

  Widget _buildErrorState() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.red.withValues(alpha: 0.15)),
          ),
          child: const Icon(
            Icons.error_outline_rounded,
            size: 32,
            color: Colors.redAccent,
          ),
        ),
        const SizedBox(height: 16),
        if (_errorMessage != null)
          Text(
            _errorMessage!,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.6),
            ),
            textAlign: TextAlign.center,
          ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _checkBiometrics,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text(
              'Retry',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white.withValues(alpha: 0.7),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUnavailableState() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: const Color(0xFFFFAB40).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: const Color(0xFFFFAB40).withValues(alpha: 0.15),
            ),
          ),
          child: const Icon(
            Icons.smartphone_rounded,
            size: 32,
            color: Color(0xFFFFAB40),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Biometrics not available',
          style: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Colors.white.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'This device does not support fingerprint\nor face unlock.',
          style: GoogleFonts.inter(
            fontSize: 13,
            color: Colors.white.withValues(alpha: 0.35),
            height: 1.5,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () {
              // Bypass: mark session authenticated even without biometrics.
              ref.read(authSessionProvider.notifier).state = true;
            },
            icon: const Icon(Icons.arrow_forward_rounded),
            label: Text(
              'Open Tether',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    ).animate().fadeIn(duration: 400.ms, curve: Curves.easeOut);
  }
}
