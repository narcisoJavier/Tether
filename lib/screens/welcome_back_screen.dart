import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/onboarding_service.dart';

/// OLED terminal boot screen with per-line typewriter animation.
///
/// Each boot line types out character-by-character (~55ms/char) before the
/// next line begins. When all lines are typed, a progress bar fills and
/// the app auto-navigates to home.
class WelcomeBackScreen extends StatefulWidget {
  const WelcomeBackScreen({super.key});

  @override
  State<WelcomeBackScreen> createState() => _WelcomeBackScreenState();
}

class _WelcomeBackScreenState extends State<WelcomeBackScreen>
    with SingleTickerProviderStateMixin {
  static const _bootLines = [
    '> Initializing Tether core...             [OK]',
    '> Establishing secure tunnel...          [OK]',
    '> Syncing connection profiles...         [OK]',
    '> Terminal active.',
  ];

  // ── Typewriter state ──────────────────────────────────────────────────
  int _currentLine = 0;
  int _charCount = 0;
  bool _allTyped = false;

  Timer? _typeTimer;

  // ── Progress bar ──────────────────────────────────────────────────────
  late final AnimationController _progressCtrl;

  @override
  void initState() {
    super.initState();

    _progressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    // Start typing the first line.
    _typeLine(0);
  }

  // ── Typewriter logic ─────────────────────────────────────────────────

  void _typeLine(int lineIndex) {
    final line = _bootLines[lineIndex];
    _charCount = 0;
    _currentLine = lineIndex;

    _typeTimer = Timer.periodic(const Duration(milliseconds: 8), (t) {
      if (_charCount < line.length) {
        setState(() => _charCount++);
      } else {
        t.cancel();
        _onLineComplete(lineIndex);
      }
    });
  }

  void _onLineComplete(int lineIndex) {
    if (lineIndex < _bootLines.length - 1) {
      // Next line starts immediately.
      _typeLine(lineIndex + 1);
    } else {
      // All lines done → mark complete, start progress bar, navigate.
      setState(() => _allTyped = true);

      Timer(const Duration(milliseconds: 80), () {
        if (mounted) _progressCtrl.forward();
      });

      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) {
          final container = ProviderScope.containerOf(context);
          container.read(onboardingServiceProvider).markWelcomeShown();
          context.go('/');
        }
      });
    }
  }

  @override
  void dispose() {
    _typeTimer?.cancel();
    _progressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF0A84FF);

    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      body: SafeArea(
        child: GestureDetector(
          onTap: () {
            final container = ProviderScope.containerOf(context);
            container.read(onboardingServiceProvider).markWelcomeShown();
            context.go('/');
          },
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Boot lines (with typewriter) ──────────────────────
                for (var i = 0; i < _bootLines.length; i++)
                  _buildLine(i, accent),
                const SizedBox(height: 20),
                // ── Progress bar ──────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: SizedBox(
                    height: 1,
                    child: AnimatedBuilder(
                      animation: _progressCtrl,
                      builder: (context, _) {
                        return LinearProgressIndicator(
                          value: _progressCtrl.value,
                          backgroundColor: accent.withValues(alpha: 0.15),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            accent,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Renders a boot line: completed lines show full text, the active line
  /// shows its typed prefix with a blinking block caret, future lines are
  /// hidden.
  Widget _buildLine(int index, Color accent) {
    final line = _bootLines[index];
    final isReady = line == '> Ready.';
    final isActive = index == _currentLine && !_allTyped;
    final isDone = index < _currentLine || _allTyped;

    String display;
    bool showCaret = false;

    if (isDone) {
      display = line;
    } else if (isActive) {
      display = line.substring(0, _charCount);
      // Caret blinks only when the full line is typed.
      showCaret = _charCount == line.length;
    } else {
      // Future lines are invisible but occupy layout space.
      display = '';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 5),
      child: AnimatedOpacity(
        opacity: (isDone || isActive) ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 100),
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: display,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 12,
                  color: isReady
                      ? accent
                      : Colors.white.withValues(alpha: 0.85),
                  height: 1.5,
                ),
              ),
              if (showCaret)
                TextSpan(
                  text: '█',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 12,
                    color: accent.withValues(alpha: 0.85),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
