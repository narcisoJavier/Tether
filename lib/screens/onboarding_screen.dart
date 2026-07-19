import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/onboarding_service.dart';
import '../utils/constants.dart';

/// Four-slide onboarding screen shown on first launch.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  static const _totalPages = 4;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _completeOnboarding() async {
    await ref.read(onboardingServiceProvider).completeOnboarding();
    if (mounted) context.go('/');
  }

  void _skip() => _completeOnboarding();

  void _nextPage() {
    if (_currentPage < _totalPages - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    } else {
      _completeOnboarding();
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: AppConstants.backgroundDark,
      body: SafeArea(
        child: Stack(
          children: [
            // Page view
            PageView(
              controller: _pageController,
              onPageChanged: (index) => setState(() => _currentPage = index),
              children: [
                _buildWelcomeSlide(size),
                _buildConnectSlide(size),
                _buildKeysSlide(size),
                _buildCommandsSlide(size),
              ],
            ),

            // Skip button (top-right)
            if (_currentPage < _totalPages - 1)
              Positioned(
                top: 8,
                right: 16,
                child: TextButton(
                  onPressed: _skip,
                  child: Text(
                    'Skip',
                    style: GoogleFonts.inter(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),

            // Dot indicators + Next/Get Started button (bottom)
            Positioned(
              left: 24,
              right: 24,
              bottom: 24,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Dot indicators
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_totalPages, (index) {
                      final isActive = index == _currentPage;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: isActive ? 28 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: isActive
                              ? AppConstants.primaryGreen
                              : Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 28),
                  // Action button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _nextPage,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppConstants.primaryGreen,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        textStyle: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      child: Text(
                        _currentPage < _totalPages - 1 ? 'Next' : 'Get Started',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Slide 1: Welcome ──────────────────────────────────────────────

  Widget _buildWelcomeSlide(Size size) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Terminal icon
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppConstants.primaryGreen.withValues(alpha: 0.08),
                border: Border.all(
                  color: AppConstants.primaryGreen.withValues(alpha: 0.2),
                ),
              ),
              child: const Icon(
                Icons.terminal_rounded,
                size: 56,
                color: AppConstants.primaryGreen,
              ),
            ),
            const SizedBox(height: 48),
            // Title
            Text(
              'OPA',
              style: GoogleFonts.inter(
                fontSize: 48,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: 4,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'OpenSSH Pocket Agent',
              style: GoogleFonts.inter(
                fontSize: 16,
                color: AppConstants.primaryGreen.withValues(alpha: 0.8),
                fontWeight: FontWeight.w500,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'Your SSH terminal, in your pocket.',
              style: GoogleFonts.inter(
                fontSize: 18,
                color: Colors.white.withValues(alpha: 0.6),
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              'No telemetry. No cloud. Fully open source.',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.3),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ── Slide 2: Connect ────────────────────────────────────────────

  Widget _buildConnectSlide(Size size) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 3-step visual
            _buildStepCircle(
              icon: Icons.add_circle_outline,
              label: 'Save Host',
              color: AppConstants.primaryGreen,
              delay: 0.ms,
            ),
            _buildStepConnector(),
            _buildStepCircle(
              icon: Icons.touch_app,
              label: 'Connect',
              color: const Color(0xFF448AFF),
              delay: 200.ms,
            ),
            _buildStepConnector(),
            _buildStepCircle(
              icon: Icons.terminal_rounded,
              label: 'Terminal',
              color: AppConstants.accentAmber,
              delay: 400.ms,
            ),
            const SizedBox(height: 48),
            Text(
              'Save your servers,\nconnect instantly',
              style: GoogleFonts.inter(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                height: 1.3,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              'Save host, port, and credentials for one-tap SSH connections. '
              'Supports password, key-based, or both.',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: Colors.white.withValues(alpha: 0.5),
                height: 1.6,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepCircle({
    required IconData icon,
    required String label,
    required Color color,
    required Duration delay,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.1),
            border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
          ),
          child: Icon(icon, color: color, size: 28),
        )
            .animate()
            .fadeIn(duration: 500.ms, delay: delay, curve: Curves.easeOut)
            .scale(
              begin: const Offset(0.8, 0.8),
              duration: 500.ms,
              delay: delay,
              curve: Curves.easeOutBack,
            ),
        const SizedBox(width: 16),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: color.withValues(alpha: 0.9),
          ),
        )
            .animate()
            .fadeIn(duration: 400.ms, delay: delay + 100.ms, curve: Curves.easeOut)
            .slideX(begin: 0.1, end: 0, duration: 400.ms, delay: delay + 100.ms),
      ],
    );
  }

  Widget _buildStepConnector() {
    return Container(
      width: 2,
      height: 20,
      margin: const EdgeInsets.only(left: 31),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(1),
      ),
    );
  }

  // ── Slide 3: SSH Keys ───────────────────────────────────────────

  Widget _buildKeysSlide(Size size) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Key + shield icon
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppConstants.primaryGreen.withValues(alpha: 0.08),
                border: Border.all(
                  color: AppConstants.primaryGreen.withValues(alpha: 0.2),
                ),
              ),
              child: const Icon(
                Icons.vpn_key_rounded,
                size: 44,
                color: AppConstants.primaryGreen,
              ),
            )
                .animate()
                .fadeIn(duration: 600.ms, curve: Curves.easeOut)
                .scale(
                  begin: const Offset(0.8, 0.8),
                  duration: 600.ms,
                  curve: Curves.easeOutBack,
                ),
            const SizedBox(height: 40),
            Text(
              'Generate or import\nSSH keys',
              style: GoogleFonts.inter(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                height: 1.3,
              ),
              textAlign: TextAlign.center,
            )
                .animate()
                .fadeIn(duration: 500.ms, delay: 200.ms),
            const SizedBox(height: 16),
            Text(
              'Private keys are encrypted and stored in your device\'s '
              'secure keystore. They never leave your phone.',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: Colors.white.withValues(alpha: 0.5),
                height: 1.6,
              ),
              textAlign: TextAlign.center,
            )
                .animate()
                .fadeIn(duration: 500.ms, delay: 300.ms),
            const SizedBox(height: 24),
            // Ed25519 badge
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppConstants.primaryGreen.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppConstants.primaryGreen.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.star_rounded,
                    size: 14,
                    color: AppConstants.primaryGreen,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Ed25519 Recommended',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppConstants.primaryGreen,
                    ),
                  ),
                ],
              ),
            )
                .animate()
                .fadeIn(duration: 400.ms, delay: 500.ms, curve: Curves.easeOut)
                .scale(
                  begin: const Offset(0.9, 0.9),
                  duration: 400.ms,
                  delay: 500.ms,
                  curve: Curves.easeOutBack,
                ),
          ],
        ),
      ),
    );
  }

  // ── Slide 4: Quick Commands ─────────────────────────────────────

  Widget _buildCommandsSlide(Size size) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Lightning bolt + terminal
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFFF9F0A).withValues(alpha: 0.08),
                border: Border.all(
                  color: const Color(0xFFFF9F0A).withValues(alpha: 0.2),
                ),
              ),
              child: const Icon(
                Icons.flash_on_rounded,
                size: 44,
                color: Color(0xFFFF9F0A),
              ),
            )
                .animate()
                .fadeIn(duration: 600.ms, curve: Curves.easeOut)
                .scale(
                  begin: const Offset(0.8, 0.8),
                  duration: 600.ms,
                  curve: Curves.easeOutBack,
                ),
            const SizedBox(height: 40),
            Text(
              'One-tap\ncommand execution',
              style: GoogleFonts.inter(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                height: 1.3,
              ),
              textAlign: TextAlign.center,
            )
                .animate()
                .fadeIn(duration: 500.ms, delay: 200.ms),
            const SizedBox(height: 16),
            Text(
              'Save frequently-run scripts for quick access. '
              'Great for launching agent harnesses or automation tasks.',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: Colors.white.withValues(alpha: 0.5),
                height: 1.6,
              ),
              textAlign: TextAlign.center,
            )
                .animate()
                .fadeIn(duration: 500.ms, delay: 300.ms),
            const SizedBox(height: 24),
            // Terminal command preview
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppConstants.surfaceDark.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppConstants.border0,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '\$ python ~/agents/start.py --auto',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 12,
                      color: AppConstants.primaryGreen.withValues(alpha: 0.8),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppConstants.accentAmber,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Agent running on port 8080',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.4),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            )
                .animate()
                .fadeIn(duration: 500.ms, delay: 500.ms, curve: Curves.easeOut)
                .slideY(begin: 0.1, end: 0, duration: 500.ms, delay: 500.ms),
          ],
        ),
      ),
    );
  }
}
