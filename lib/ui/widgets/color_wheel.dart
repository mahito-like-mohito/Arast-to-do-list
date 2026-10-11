import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/constants.dart';
import 'eager_pan_recognizer.dart';

class ColorWheel extends StatefulWidget {
  const ColorWheel({
    super.key,
    required this.color,
    required this.onChanged,
    this.onChangeEnd,
    this.size = AppConstants.colorWheelSize,
  });

  final Color color;
  final ValueChanged<Color> onChanged;
  final ValueChanged<Color>? onChangeEnd;
  final double size;

  @override
  State<ColorWheel> createState() => _ColorWheelState();
}

class _ColorWheelState extends State<ColorWheel> {
  double get _radius => widget.size / 2;

  // freeze the starting colour against later prop changes
  late Color _current;

  @override
  void initState() {
    super.initState();
    _current = widget.color;
  }

  @override
  void didUpdateWidget(ColorWheel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.color != oldWidget.color) _current = widget.color;
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: <Type, GestureRecognizerFactory>{
          EagerPanGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<EagerPanGestureRecognizer>(
            EagerPanGestureRecognizer.new,
            (recognizer) => recognizer
              ..onDown = ((details) => _update(details.localPosition))
              ..onUpdate = ((details) => _update(details.localPosition))
              ..onEnd = ((_) => widget.onChangeEnd?.call(_current))
              ..onCancel = (() => widget.onChangeEnd?.call(_current)),
          ),
        },
        child: CustomPaint(
          size: Size.square(widget.size),
          painter: _WheelPainter(selectedColor: _current),
        ),
      ),
    );
  }

  void _update(Offset position) {
    final vector = position - Offset(_radius, _radius);

    var hue = math.atan2(vector.dy, vector.dx) * 180 / math.pi;
    if (hue < 0) hue += 360;

    final saturation = (vector.distance / _radius).clamp(0.0, 1.0);

    final next = HSVColor.fromAHSV(1, hue, saturation, 1).toColor();
    if (next == _current) return;
    setState(() => _current = next);
    widget.onChanged(next);
  }
}

class _WheelPainter extends CustomPainter {
  _WheelPainter({required this.selectedColor});

  final Color selectedColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    const hueColors = [
      Color(0xFFFF0000),
      Color(0xFFFFFF00),
      Color(0xFF00FF00),
      Color(0xFF00FFFF),
      Color(0xFF0000FF),
      Color(0xFFFF00FF),
      Color(0xFFFF0000),
    ];
    canvas.drawCircle(
      center,
      radius,
      Paint()..shader = const SweepGradient(colors: hueColors).createShader(rect),
    );

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white,
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(rect),
    );

    canvas.drawCircle(
      center,
      radius - 1,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFF7A5B41).withValues(alpha: 0.45),
    );

    _paintSelectionIndicator(canvas, center, radius);
  }

  void _paintSelectionIndicator(Canvas canvas, Offset center, double radius) {
    final hsv = HSVColor.fromColor(selectedColor);
    final angle = hsv.hue * math.pi / 180;
    final distance = hsv.saturation * radius;
    final position =
        center + Offset(math.cos(angle), math.sin(angle)) * distance;

    canvas.drawCircle(
      position,
      12,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = Colors.white,
    );
    canvas.drawCircle(
      position,
      12,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.black.withValues(alpha: 0.35),
    );
    canvas.drawCircle(position, 8, Paint()..color = selectedColor);
  }

  @override
  bool shouldRepaint(_WheelPainter oldDelegate) {
    return oldDelegate.selectedColor != selectedColor;
  }
}
