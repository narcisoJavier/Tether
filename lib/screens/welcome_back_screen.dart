import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/onboarding_service.dart';


class _HexContourPainter extends CustomPainter {
  final double pulse;
  final double scale;

  _HexContourPainter({required this.pulse, required this.scale});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const hexRadius = 100.0;
    final radius = hexRadius * scale;

    // 3 circular ripple rings expanding from hexagon
    for (var i = 0; i < 3; i++) {
      final ringPhase = (pulse + i / 3) % 1.0;
      final ringRadius = radius + 20.0 + ringPhase * 80.0;
      final opacity = (1.0 - ringPhase) * 0.25;

      final ringPaint = Paint()
        ..color = const Color(0xFF00E676).withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      canvas.drawCircle(center, ringRadius, ringPaint);
    }

    // Pulsing hexagon stroke opacity 0.55-0.85
    final pulseOpacity = 0.55 + 0.30 * (0.5 + 0.5 * sin(pulse * 2 * pi));
    final borderPaint = Paint()
      ..color = const Color(0xFF00E676).withValues(alpha: pulseOpacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    _drawHexagon(canvas, center, radius, borderPaint);

    // Glow
    final glowPaint = Paint()
      ..color = const Color(0xFF00E676).withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    _drawHexagon(canvas, center, radius, glowPaint);

    // Subtle fill
    final fillPaint = Paint()
      ..color = const Color(0xFF00E676).withValues(alpha: 0.03)
      ..style = PaintingStyle.fill;
    _drawHexagon(canvas, center, radius, fillPaint);
  }

  void _drawHexagon(Canvas canvas, Offset center, double radius, Paint paint) {
    final path = Path();
    for (var i = 0; i < 6; i++) {
      final angle = (pi / 3) * i - pi / 2;
      final point = Offset(
        center.dx + radius * cos(angle),
        center.dy + radius * sin(angle),
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_HexContourPainter old) =>
      old.pulse != pulse || old.scale != scale;
}

/// A single matrix character floating at a random screen position.
class _MatrixChar {
  final double x;
  final double y;
  final String char;
  double life;

  _MatrixChar({
    required this.x,
    required this.y,
    required this.char,
  }) : life = 0.0;

}

/// Paints the matrix-style characters across the full screen.
/// Characters fade in during the first 20% of their life, hold, then fade
/// out during the final 40%.
class _MatrixPainter extends CustomPainter {
  final List<_MatrixChar> chars;

  _MatrixPainter({required this.chars});

  @override
  void paint(Canvas canvas, Size size) {
    for (final c in chars) {
      if (c.life >= 1.0 || c.life < 0.0) continue;

      double opacity;
      if (c.life < 0.2) {
        opacity = c.life / 0.2;
      } else if (c.life > 0.6) {
        opacity = (1.0 - c.life) / 0.4;
      } else {
        opacity = 1.0;
      }

      if (opacity <= 0.01) continue;

      final textStyle = TextStyle(
        color: const Color(0xFF00E676).withValues(alpha: opacity * 0.12),
        fontSize: 11,
        fontFamily: 'JetBrains Mono',
      );
      final tp = TextPainter(
        text: TextSpan(text: c.char, style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(c.x * size.width, c.y * size.height));
    }
  }

  @override
  bool shouldRepaint(_MatrixPainter old) => true;
}

class WelcomeBackScreen extends StatefulWidget {
  const WelcomeBackScreen({super.key});

  @override
  State<WelcomeBackScreen> createState() => _WelcomeBackScreenState();
}

class _WelcomeBackScreenState extends State<WelcomeBackScreen>
    with TickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final AnimationController _scaleCtrl;
  late final AnimationController _progressCtrl;
  late final Ticker _matrixTicker;
  final List<_MatrixChar> _matrixChars = [];
  final Random _matrixRandom = Random();

  static const _matrixCharset = [
    '0', '1', 'O', 'A', 'P', '#', '*', '+', '-', '=',
    '>', '<', ':', ';', '.', ',', '{', '}', '(', ')',
    '[', ']', '|', '&', '^', '%', '@', '!', '~',
  ];

  @override
  void initState() {
    super.initState();


    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat();

    _scaleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();

    _progressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _matrixTicker = createTicker(_onMatrixTick)..start();

    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) _progressCtrl.forward();
    });

    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) {
        final container = ProviderScope.containerOf(context);
        container.read(onboardingServiceProvider).markWelcomeShown();
        context.go('/');
      }
    });
  }

  /// Called every frame to advance matrix character life, remove dead chars,
  /// and spawn new ones at random positions.
  void _onMatrixTick(Duration elapsed) {
    for (final c in _matrixChars) {
      c.life += 0.016;
    }

    _matrixChars.removeWhere((c) => c.life >= 1.0);

    if (_matrixRandom.nextDouble() < 0.35) {
      _matrixChars.add(_MatrixChar(
        x: _matrixRandom.nextDouble(),
        y: _matrixRandom.nextDouble(),
        char: _matrixCharset[_matrixRandom.nextInt(_matrixCharset.length)],
      ));
    }

    while (_matrixChars.length > 100) {
      _matrixChars.removeAt(0);
    }

    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _matrixTicker.dispose();
    _pulseCtrl.dispose();
    _scaleCtrl.dispose();
    _progressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E17),
      body: Stack(
        children: [
          // â”€â”€ Layer 1: Matrix text background â”€â”€
          Positioned.fill(
            child: CustomPaint(
              painter: _MatrixPainter(chars: _matrixChars),
            ),
          ),

          // â”€â”€ Layer 2: Hexagon + ASCII art centered â”€â”€
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
width: 220,
height: 220,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned.fill(
                        child: AnimatedBuilder(
                          animation:
                              Listenable.merge([_pulseCtrl, _scaleCtrl]),
                          builder: (context, _) {
                            return CustomPaint(
                              painter: _HexContourPainter(
                                pulse: _pulseCtrl.value,
                                scale: 0.8 +
                                    0.2 *
                                        Curves.easeOutBack
                                            .transform(_scaleCtrl.value),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox.shrink(),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                Text(
                  'Welcome back',
                  style: GoogleFonts.inter(
                    fontSize: 26,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.85),
                    letterSpacing: 0.5,
                  ),
                )
                    .animate()
                    .fadeIn(
                      duration: 400.ms,
                      delay: 600.ms,
                      curve: Curves.easeOut,
                    )
                    .slideY(
                      begin: 0.15,
                      end: 0,
                      duration: 400.ms,
                      delay: 600.ms,
                      curve: Curves.easeOut,
                    ),

                const SizedBox(height: 8),

                Text(
                  'OPA \u2014 OpenSSH Pocket Agent',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: Colors.white.withValues(alpha: 0.4),
                    letterSpacing: 0.3,
                  ),
                )
                    .animate()
                    .fadeIn(
                      duration: 400.ms,
                      delay: 800.ms,
                      curve: Curves.easeOut,
                    ),
              ],
            ),
          ),

          // â”€â”€ Layer 4: Progress bar at bottom â”€â”€
          Positioned(
            left: 0,
            right: 0,
            bottom: 80,
            child: Center(
              child: SizedBox(
                width: 180,
                height: 2,
                child: AnimatedBuilder(
                  animation: _progressCtrl,
                  builder: (context, _) {
                    return LinearProgressIndicator(
                      value: _progressCtrl.value,
                      backgroundColor:
                          const Color(0xFF00E676).withValues(alpha: 0.15),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        const Color(0xFF00E676).withValues(alpha: 0.85),
                      ),
                    );
                  },
                ),
              ),
            ),
          ).animate().fadeIn(
            duration: 200.ms,
            delay: 900.ms,
            curve: Curves.easeOut,
          ),
        ],
      ),
    );
  }
}



