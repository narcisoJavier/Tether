import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:tether/screens/cyber_logo_data.dart';

class CyberSplashScreen extends StatefulWidget {
  final VoidCallback? onBootComplete;

  const CyberSplashScreen({
    super.key,
    this.onBootComplete,
  });

  @override
  State<CyberSplashScreen> createState() => _CyberSplashScreenState();
}

class _CyberSplashScreenState extends State<CyberSplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  late final Animation<double> _containerFade;
  late final Animation<double> _containerScale;
  late final Animation<double> _terminalDraw;
  late final Animation<double> _promptShow;
  late final Animation<double> _snakeTrace;
  late final Animation<double> _pulseOffset;
  late final Animation<double> _headSurge;
  late final Animation<double> _tongueFlick;
  late final Animation<double> _settlePulse;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3500),
    );

    _containerFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.20, curve: Curves.easeOut),
    );

    _containerScale = Tween<double>(begin: 0.90, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.25, curve: Curves.easeOutBack),
      ),
    );

    _terminalDraw = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.10, 0.28, curve: Curves.easeInOut),
    );

    _promptShow = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.20, 0.30, curve: Curves.easeIn),
    );

    _snakeTrace = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.23, 0.63, curve: Curves.easeInOutCubic),
    );

    _pulseOffset = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.23, 0.85, curve: Curves.linear),
    );

    _headSurge = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.57, 0.75, curve: Curves.easeInOut),
    );

    _tongueFlick = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.65, 0.82, curve: Curves.easeInOut),
    );

    _settlePulse = Tween<double>(begin: 1.0, end: 1.025).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.80, 1.0, curve: Curves.easeInOutSine),
      ),
    );

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onBootComplete?.call();
      }
    });

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onBootComplete?.call(),
        child: Center(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final settleScale = _settlePulse.value;
              final baseScale = _containerScale.value;

              return Opacity(
                opacity: _containerFade.value.clamp(0.0, 1.0),
                child: Transform.scale(
                  scale: baseScale * settleScale,
                  child: Container(
                    width: 260,
                    height: 260,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F0F11),
                      borderRadius: BorderRadius.circular(56),
                      border: Border.all(
                        color: Colors.white.withValues(
                          alpha: 0.10 + (_headSurge.value * 0.08),
                        ),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.8),
                          blurRadius: 30,
                          offset: const Offset(0, 14),
                        ),
                        if (_headSurge.value > 0.01)
                          BoxShadow(
                            color: Colors.white.withValues(
                              alpha: 0.08 * _headSurge.value,
                            ),
                            blurRadius: 36,
                            spreadRadius: 2,
                          ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(54),
                      child: CustomPaint(
                        painter: _CyberBootLogoPainter(
                          terminalProgress: _terminalDraw.value,
                          promptProgress: _promptShow.value,
                          snakeProgress: _snakeTrace.value,
                          pulseOffset: _pulseOffset.value,
                          headSurge: _headSurge.value,
                          tongueFlick: _tongueFlick.value,
                          totalElapsedMs: (_controller.value * 3500).round(),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CyberBootLogoPainter extends CustomPainter {
  final double terminalProgress;
  final double promptProgress;
  final double snakeProgress;
  final double pulseOffset;
  final double headSurge;
  final double tongueFlick;
  final int totalElapsedMs;

  _CyberBootLogoPainter({
    required this.terminalProgress,
    required this.promptProgress,
    required this.snakeProgress,
    required this.pulseOffset,
    required this.headSurge,
    required this.tongueFlick,
    required this.totalElapsedMs,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawTerminalBox(canvas, size);
    _drawPromptAndCursor(canvas, size);
    _drawSnakeBody(canvas, size);
    _drawSnakeHead(canvas, size);
    _drawTongue(canvas, size);
  }

  void _drawTerminalBox(Canvas canvas, Size size) {
    if (terminalProgress <= 0.0) return;

    const strokes = CyberLogoData.terminalBoxStrokes;
    final visibleCount = (strokes.length * terminalProgress).ceil().clamp(0, strokes.length);

    final strokePaint = Paint()
      ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.90)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * (7.5 / 1024.0)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (var i = 0; i < visibleCount; i++) {
      _drawStroke(canvas, size, strokes[i], strokePaint);
    }
  }

  void _drawPromptAndCursor(Canvas canvas, Size size) {
    if (promptProgress <= 0.0) return;

    final strokeWidth = size.width * (7.5 / 1024.0);
    final promptAlpha = promptProgress.clamp(0.0, 1.0);

    final promptPaint = Paint()
      ..color = const Color(0xFFFFFFFF).withValues(alpha: promptAlpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (final stroke in CyberLogoData.promptStrokes) {
      _drawStroke(canvas, size, stroke, promptPaint);
    }

    final isCursorVisible = (totalElapsedMs ~/ 250) % 2 == 0;
    if (promptProgress >= 0.5 && isCursorVisible) {
      final cursorPaint = Paint()
        ..color = const Color(0xFFFFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      for (final stroke in CyberLogoData.cursorStrokes) {
        _drawStroke(canvas, size, stroke, cursorPaint);
      }
    }
  }

  void _drawSnakeBody(Canvas canvas, Size size) {
    if (snakeProgress <= 0.0) return;

    const strokes = CyberLogoData.snakeBodyStrokes;
    final count = strokes.length;
    final visibleCount = (count * snakeProgress).ceil().clamp(0, count);

    final baseStrokeWidth = size.width * (7.5 / 1024.0);
    final waveCenter = (pulseOffset * 4.0) % 1.0;

    for (var i = 0; i < visibleCount; i++) {
      final s = i / count;
      var dist = (s - waveCenter).abs();
      if (dist > 0.5) dist = 1.0 - dist;

      final wavePulse = dist < 0.12 ? (1.0 - (dist / 0.12)) : 0.0;
      final alpha = (0.85 + (0.15 * wavePulse)).clamp(0.0, 1.0);
      final strokeWidth = baseStrokeWidth * (1.0 + (0.35 * wavePulse));

      final paint = Paint()
        ..color = const Color(0xFFFFFFFF).withValues(alpha: alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      _drawStroke(canvas, size, strokes[i], paint);
    }
  }

  void _drawSnakeHead(Canvas canvas, Size size) {
    if (snakeProgress < 0.88 && headSurge <= 0.0) return;

    final headAlpha = (snakeProgress < 1.0)
        ? ((snakeProgress - 0.88) / 0.12).clamp(0.0, 1.0)
        : 1.0;

    final baseStrokeWidth = size.width * (7.5 / 1024.0);
    final surgeGlow = headSurge.clamp(0.0, 1.0);

    if (surgeGlow > 0.05) {
      final glowPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.35 * surgeGlow)
        ..style = PaintingStyle.stroke
        ..strokeWidth = baseStrokeWidth * 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);

      for (final stroke in CyberLogoData.snakeHeadStrokes) {
        _drawStroke(canvas, size, stroke, glowPaint);
      }
    }

    final headPaint = Paint()
      ..color = const Color(0xFFFFFFFF).withValues(
        alpha: (0.90 * headAlpha + (0.10 * surgeGlow)).clamp(0.0, 1.0),
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = baseStrokeWidth * (1.0 + (0.15 * surgeGlow))
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (final stroke in CyberLogoData.snakeHeadStrokes) {
      _drawStroke(canvas, size, stroke, headPaint);
    }
  }

  void _drawTongue(Canvas canvas, Size size) {
    if (tongueFlick <= 0.0) return;

    final flickOscillation = math.sin(tongueFlick * math.pi * 4.0).abs();
    final flickMagnitude = flickOscillation * 0.018;
    final flickOffset = Offset(
      flickMagnitude * 0.707,
      flickMagnitude * 0.707,
    );

    final baseStrokeWidth = size.width * (7.0 / 1024.0);
    final tonguePaint = Paint()
      ..color = const Color(0xFFFFFFFF).withValues(
        alpha: (0.85 + (0.15 * flickOscillation)).clamp(0.0, 1.0),
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = baseStrokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (final stroke in CyberLogoData.snakeTongueStrokes) {
      final displaced = stroke
          .map((pt) => Offset(pt.dx + flickOffset.dx, pt.dy + flickOffset.dy))
          .toList();
      _drawStroke(canvas, size, displaced, tonguePaint);
    }
  }

  void _drawStroke(
    Canvas canvas,
    Size size,
    List<Offset> stroke,
    Paint paint,
  ) {
    if (stroke.isEmpty) return;

    if (stroke.length == 1) {
      final dot = Offset(stroke[0].dx * size.width, stroke[0].dy * size.height);
      final fillPaint = Paint()
        ..color = paint.color
        ..style = PaintingStyle.fill;
      canvas.drawCircle(dot, paint.strokeWidth / 2, fillPaint);
      return;
    }

    final path = Path();
    path.moveTo(stroke[0].dx * size.width, stroke[0].dy * size.height);
    for (var i = 1; i < stroke.length; i++) {
      path.lineTo(stroke[i].dx * size.width, stroke[i].dy * size.height);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _CyberBootLogoPainter oldDelegate) {
    return oldDelegate.terminalProgress != terminalProgress ||
        oldDelegate.promptProgress != promptProgress ||
        oldDelegate.snakeProgress != snakeProgress ||
        oldDelegate.pulseOffset != pulseOffset ||
        oldDelegate.headSurge != headSurge ||
        oldDelegate.tongueFlick != tongueFlick ||
        oldDelegate.totalElapsedMs != totalElapsedMs;
  }
}
