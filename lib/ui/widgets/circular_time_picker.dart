import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/app_palette.dart';
import '../../core/constants.dart';
import '../../core/time_formatting.dart';
import 'eager_pan_recognizer.dart';

class CircularTimePicker extends StatefulWidget {
  const CircularTimePicker({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.size = AppConstants.timePickerSize,
  });

  final String label;

  final TimeOfDay value;
  final ValueChanged<TimeOfDay> onChanged;
  final double size;

  @override
  State<CircularTimePicker> createState() => _CircularTimePickerState();
}

enum _DialRing { none, hour, minute }

class _CircularTimePickerState extends State<CircularTimePicker> {
  _DialRing _activeRing = _DialRing.none;

  double get _radius => widget.size / 2;

  double get _hourRingRadius => _radius - 30;

  double get _minuteRingRadius => _radius - 82;

  double get _centerRadius => 36;

  int get _hour12 {
    final hourOfPeriod = widget.value.hourOfPeriod;
    return hourOfPeriod == 0 ? 12 : hourOfPeriod;
  }

  bool get _isAm => widget.value.period == DayPeriod.am;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(context, palette),
        const SizedBox(height: 12),
        Center(
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: Stack(
              children: [
                Positioned.fill(
                  child: RawGestureDetector(
                    behavior: HitTestBehavior.opaque,
                    gestures: <Type, GestureRecognizerFactory>{
                      EagerPanGestureRecognizer:
                          GestureRecognizerFactoryWithHandlers<
                              EagerPanGestureRecognizer>(
                        EagerPanGestureRecognizer.new,
                        (recognizer) => recognizer
                          ..onDown = _handlePanDown
                          ..onUpdate = _handlePanUpdate
                          ..onEnd = ((_) => _activeRing = _DialRing.none)
                          ..onCancel = (() => _activeRing = _DialRing.none),
                      ),
                    },
                    child: CustomPaint(
                      painter: _DialPainter(
                        hour12: _hour12,
                        minute: widget.value.minute,
                        palette: palette,
                        hourRingRadius: _hourRingRadius,
                        minuteRingRadius: _minuteRingRadius,
                        centerRadius: _centerRadius,
                      ),
                    ),
                  ),
                ),
                // the eager pan would swallow the toggle tap
                Center(child: _buildAmPmToggle(palette)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context, AppPalette palette) {
    final formatted = TimeFormatting.minutesLabel(
      widget.value.hour * 60 + widget.value.minute,
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          widget.label,
          style: TextStyle(
            color: palette.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: palette.accent.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: palette.accent.withValues(alpha: 0.7)),
          ),
          child: Text(
            formatted,
            style: TextStyle(
              color: palette.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 15,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAmPmToggle(AppPalette palette) {
    return Material(
      color: palette.accent,
      shape: const CircleBorder(),
      elevation: 4,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: _togglePeriod,
        child: SizedBox(
          width: _centerRadius * 2,
          height: _centerRadius * 2,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _isAm ? 'AM' : 'PM',
                style: TextStyle(
                  color: palette.onAccent,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  letterSpacing: 1.2,
                ),
              ),
              Icon(
                Icons.swap_vert,
                size: 14,
                color: palette.onAccent.withValues(alpha: 0.75),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _togglePeriod() {
    final flippedHour = (widget.value.hour + 12) % 24;
    widget.onChanged(
      TimeOfDay(hour: flippedHour, minute: widget.value.minute),
    );
  }

  void _handlePanDown(DragDownDetails details) {
    final ring = _ringAt(details.localPosition);
    _activeRing = ring;
    if (ring != _DialRing.none) {
      _updateFromPosition(details.localPosition, ring);
    }
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    if (_activeRing == _DialRing.none) return;
    _updateFromPosition(details.localPosition, _activeRing);
  }

  _DialRing _ringAt(Offset position) {
    final distance = (position - Offset(_radius, _radius)).distance;
    if (distance <= _centerRadius + 6) return _DialRing.none;
    final splitRadius = (_hourRingRadius + _minuteRingRadius) / 2;
    return distance >= splitRadius ? _DialRing.hour : _DialRing.minute;
  }

  void _updateFromPosition(Offset position, _DialRing ring) {
    final center = Offset(_radius, _radius);
    final vector = position - center;

    final angle = math.atan2(vector.dy, vector.dx);
    var turns = (angle + math.pi / 2) / (2 * math.pi);
    turns = turns - turns.floorToDouble();

    if (ring == _DialRing.hour) {
      final hourIndex = (turns * 12).round() % 12;
      final hour12 = hourIndex == 0 ? 12 : hourIndex;
      final hour24 = (hour12 % 12) + (_isAm ? 0 : 12);
      _emit(TimeOfDay(hour: hour24, minute: widget.value.minute));
    } else {
      final minute = (turns * 60).round() % 60;
      _emit(TimeOfDay(hour: widget.value.hour, minute: minute));
    }
  }

  void _emit(TimeOfDay next) {
    if (next != widget.value) widget.onChanged(next);
  }
}

class _DialPainter extends CustomPainter {
  _DialPainter({
    required this.hour12,
    required this.minute,
    required this.palette,
    required this.hourRingRadius,
    required this.minuteRingRadius,
    required this.centerRadius,
  });

  final int hour12;
  final int minute;
  final AppPalette palette;
  final double hourRingRadius;
  final double minuteRingRadius;
  final double centerRadius;

  static const double _hourBandWidth = 44;
  static const double _minuteBandWidth = 38;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    _paintBand(canvas, center, hourRingRadius, _hourBandWidth, 0.10);
    _paintBand(canvas, center, minuteRingRadius, _minuteBandWidth, 0.16);

    _paintIndicatorLine(
        canvas, center, _angleFor(hour12, 12), hourRingRadius, 0.9);
    _paintIndicatorLine(
        canvas, center, _angleFor(minute, 60), minuteRingRadius, 0.5);

    _paintHandle(canvas, center, _angleFor(hour12, 12), hourRingRadius, 17);
    _paintHandle(canvas, center, _angleFor(minute, 60), minuteRingRadius, 14);

    for (var h = 1; h <= 12; h++) {
      _paintLabel(
        canvas,
        center,
        _angleFor(h, 12),
        hourRingRadius,
        '$h',
        isSelected: h == hour12,
        fontSize: 15,
      );
    }

    for (var m = 0; m < 60; m += 5) {
      _paintLabel(
        canvas,
        center,
        _angleFor(m, 60),
        minuteRingRadius,
        m.toString().padLeft(2, '0'),
        isSelected: (minute - m).abs() <= 2 || (m == 0 && minute >= 58),
        fontSize: 11,
      );
    }
  }

  double _angleFor(int value, int count) {
    return -math.pi / 2 + (value % count) * (2 * math.pi / count);
  }

  Offset _pointOn(Offset center, double angle, double ringRadius) {
    return center +
        Offset(math.cos(angle), math.sin(angle)) * ringRadius;
  }

  void _paintBand(Canvas canvas, Offset center, double ringRadius,
      double bandWidth, double alpha) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = bandWidth
      ..color = palette.support.withValues(alpha: alpha);
    canvas.drawCircle(center, ringRadius, paint);
  }

  void _paintIndicatorLine(Canvas canvas, Offset center, double angle,
      double ringRadius, double alpha) {
    final paint = Paint()
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = palette.accent.withValues(alpha: alpha);
    final from = _pointOn(center, angle, centerRadius + 4);
    final to = _pointOn(center, angle, ringRadius);
    canvas.drawLine(from, to, paint);
  }

  void _paintHandle(Canvas canvas, Offset center, double angle,
      double ringRadius, double handleRadius) {
    final position = _pointOn(center, angle, ringRadius);
    canvas.drawCircle(
      position,
      handleRadius + 3,
      Paint()..color = palette.accent.withValues(alpha: 0.30),
    );
    canvas.drawCircle(position, handleRadius, Paint()..color = palette.accent);
  }

  void _paintLabel(Canvas canvas, Offset center, double angle,
      double ringRadius, String text,
      {required bool isSelected, required double fontSize}) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: isSelected ? palette.onAccent : palette.textSecondary,
          fontSize: fontSize,
          fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final position = _pointOn(center, angle, ringRadius);
    painter.paint(
      canvas,
      position - Offset(painter.width / 2, painter.height / 2),
    );
  }

  @override
  bool shouldRepaint(_DialPainter oldDelegate) {
    return oldDelegate.hour12 != hour12 ||
        oldDelegate.minute != minute ||
        oldDelegate.palette != palette;
  }
}
