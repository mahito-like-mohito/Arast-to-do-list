import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/app_palette.dart';
import '../../core/constants.dart';
import 'eager_pan_recognizer.dart';

class DelayClock extends StatelessWidget {
  const DelayClock({
    super.key,
    required this.minutes,
    required this.onChanged,
    this.size = AppConstants.delayClockSize,
  });

  final int minutes;

  final ValueChanged<int> onChanged;
  final double size;

  double get _radius => size / 2;

  double get _ringRadius => _radius - 26;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Center(
      child: SizedBox(
        width: size,
        height: size,
        child: RawGestureDetector(
          behavior: HitTestBehavior.opaque,
          gestures: <Type, GestureRecognizerFactory>{
            EagerPanGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<EagerPanGestureRecognizer>(
              EagerPanGestureRecognizer.new,
              (recognizer) => recognizer
                ..onDown = ((details) => _update(details.localPosition))
                ..onUpdate = ((details) => _update(details.localPosition)),
            ),
          },
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _DelayRingPainter(
                    minutes: minutes,
                    palette: palette,
                    ringRadius: _ringRadius,
                  ),
                ),
              ),
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '+$minutes',
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'overtime minutes',
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 11,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _update(Offset position) {
    final vector = position - Offset(_radius, _radius);

    final angle = math.atan2(vector.dy, vector.dx);
    var turns = (angle + math.pi / 2) / (2 * math.pi);
    turns = turns - turns.floorToDouble();

    var value = (turns * 60).round();
    // the top of the dial counts as both 0 and 60
    if (value == 0 && minutes > 45) value = 60;

    if (value != minutes) onChanged(value);
  }
}

class _DelayRingPainter extends CustomPainter {
  _DelayRingPainter({
    required this.minutes,
    required this.palette,
    required this.ringRadius,
  });

  final int minutes;
  final AppPalette palette;
  final double ringRadius;

  static const double _bandWidth = 30;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    canvas.drawCircle(
      center,
      ringRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _bandWidth
        ..color = palette.support.withValues(alpha: 0.14),
    );

    final sweep = (minutes / 60) * 2 * math.pi;
    if (sweep > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: ringRadius),
        -math.pi / 2,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _bandWidth - 8
          ..strokeCap = StrokeCap.round
          ..color = palette.accent,
      );
    }

    for (var m = 0; m < 60; m += 5) {
      final angle = -math.pi / 2 + m * (2 * math.pi / 60);
      final labelPos = center +
          Offset(math.cos(angle), math.sin(angle)) * (ringRadius + 4);
      final painter = TextPainter(
        text: TextSpan(
          text: '$m',
          style: TextStyle(
            color: m <= minutes ? palette.textPrimary : palette.textFaint,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
        canvas,
        labelPos - Offset(painter.width / 2, painter.height / 2),
      );
    }

    final handleAngle = -math.pi / 2 + (minutes / 60) * 2 * math.pi;
    final handlePos = center +
        Offset(math.cos(handleAngle), math.sin(handleAngle)) * ringRadius;
    canvas.drawCircle(handlePos, 14, Paint()..color = palette.surfaceElevated);
    canvas.drawCircle(handlePos, 9, Paint()..color = palette.accent);
  }

  @override
  bool shouldRepaint(_DelayRingPainter oldDelegate) {
    return oldDelegate.minutes != minutes || oldDelegate.palette != palette;
  }
}
