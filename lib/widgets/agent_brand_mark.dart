import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Small vector brand marks used by the built-in AI agent presets.
///
/// These are drawn locally so the command deck stays usable offline and does
/// not depend on remote logo images.
class AgentBrandMark extends StatelessWidget {
  const AgentBrandMark({
    super.key,
    required this.presetId,
    required this.color,
    this.size = 18,
  });

  final String presetId;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final painter = switch (presetId) {
      'claude-code' => _ClaudeMarkPainter(color),
      'opencode' => _OpenCodeMarkPainter(color),
      'aider' => _AiderMarkPainter(color),
      'cursor-agent' => _CursorMarkPainter(color),
      'gemini-cli' => _GeminiMarkPainter(color),
      'codex' => _CodexMarkPainter(color),
      _ => null,
    };

    if (painter != null) {
      return CustomPaint(size: Size.square(size), painter: painter);
    }

    if (presetId == 'qwen-code' || presetId == 'goose') {
      return SizedBox(
        width: size,
        height: size,
        child: Center(
          child: Text(
            presetId == 'qwen-code' ? 'Q' : 'G',
            style: TextStyle(
              color: color,
              fontSize: size * 0.82,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
        ),
      );
    }

    return Icon(Icons.smart_toy_rounded, size: size, color: color);
  }
}

Paint _markPaint(Color color, {double width = 1.8}) {
  return Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
}

class _ClaudeMarkPainter extends CustomPainter {
  _ClaudeMarkPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = _markPaint(color, width: size.shortestSide * 0.12);
    final center = size.center(Offset.zero);
    final radius = size.shortestSide * 0.37;
    for (var index = 0; index < 6; index++) {
      final angle = index * math.pi / 3;
      final start = center + Offset(math.cos(angle), math.sin(angle)) * 1.5;
      final end = center + Offset(math.cos(angle), math.sin(angle)) * radius;
      canvas.drawLine(start, end, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ClaudeMarkPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _OpenCodeMarkPainter extends CustomPainter {
  _OpenCodeMarkPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = _markPaint(color, width: size.shortestSide * 0.13);
    final side = size.shortestSide;
    final center = side / 2;
    final path = Path()
      ..moveTo(side * 0.35, side * 0.2)
      ..lineTo(side * 0.12, center)
      ..lineTo(side * 0.35, side * 0.8)
      ..moveTo(side * 0.65, side * 0.2)
      ..lineTo(side * 0.88, center)
      ..lineTo(side * 0.65, side * 0.8)
      ..moveTo(side * 0.57, side * 0.16)
      ..lineTo(side * 0.43, side * 0.84);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _OpenCodeMarkPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _AiderMarkPainter extends CustomPainter {
  _AiderMarkPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = _markPaint(color, width: size.shortestSide * 0.1);
    final side = size.shortestSide;
    final first = Path()
      ..moveTo(side * 0.2, side * 0.5)
      ..lineTo(side * 0.42, side * 0.22)
      ..lineTo(side * 0.64, side * 0.5)
      ..lineTo(side * 0.42, side * 0.78)
      ..close();
    final second = Path()
      ..moveTo(side * 0.45, side * 0.5)
      ..lineTo(side * 0.67, side * 0.22)
      ..lineTo(side * 0.89, side * 0.5)
      ..lineTo(side * 0.67, side * 0.78)
      ..close();
    canvas.drawPath(first, paint);
    canvas.drawPath(second, paint);
  }

  @override
  bool shouldRepaint(covariant _AiderMarkPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _CursorMarkPainter extends CustomPainter {
  _CursorMarkPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    final paint = _markPaint(color, width: side * 0.14);
    canvas.drawArc(
      Rect.fromLTWH(side * 0.16, side * 0.16, side * 0.68, side * 0.68),
      -math.pi * 0.78,
      math.pi * 1.58,
      false,
      paint,
    );
    canvas.drawCircle(
      Offset(side * 0.73, side * 0.28),
      side * 0.07,
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _CursorMarkPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _GeminiMarkPainter extends CustomPainter {
  _GeminiMarkPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final side = size.shortestSide;
    final center = side / 2;
    final path = Path()
      ..moveTo(center, side * 0.04)
      ..lineTo(side * 0.62, side * 0.38)
      ..lineTo(side * 0.96, center)
      ..lineTo(side * 0.62, side * 0.62)
      ..lineTo(center, side * 0.96)
      ..lineTo(side * 0.38, side * 0.62)
      ..lineTo(side * 0.04, center)
      ..lineTo(side * 0.38, side * 0.38)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _GeminiMarkPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _CodexMarkPainter extends CustomPainter {
  _CodexMarkPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    final paint = _markPaint(color, width: side * 0.11);
    final rect = Rect.fromLTWH(
      side * 0.18,
      side * 0.18,
      side * 0.64,
      side * 0.64,
    );
    canvas.drawArc(rect, -math.pi * 0.9, math.pi * 0.95, false, paint);
    canvas.drawArc(rect, math.pi * 0.1, math.pi * 0.95, false, paint);
    canvas.drawCircle(
      Offset(side * 0.5, side * 0.5),
      side * 0.08,
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _CodexMarkPainter oldDelegate) =>
      oldDelegate.color != color;
}
