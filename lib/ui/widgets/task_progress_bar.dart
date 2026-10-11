import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_palette.dart';
import '../../core/task_time_colors.dart';
import '../../core/time_formatting.dart';
import '../../data/models/task.dart';

class TaskProgressBar extends StatefulWidget {
  const TaskProgressBar({
    super.key,
    required this.task,
    this.clock,
  });

  final Task task;

  final DateTime Function()? clock;

  static const double _barWidth = 80;
  static const double _barHeight = 4;

  static const Duration redWindow = Duration(minutes: 5);

  static const Color solidRed = TaskTimeColors.endRed;

  static const Color startColor = TaskTimeColors.startGreen;

  @visibleForTesting
  static Duration redHoldFor(Duration total) {
    if (total <= Duration.zero) return Duration.zero;
    final tenPercent =
        Duration(milliseconds: (total.inMilliseconds * 0.10).round());
    return tenPercent < redWindow ? tenPercent : redWindow;
  }

  @visibleForTesting
  static Color resolveColor({
    required Duration elapsed,
    required Duration total,
  }) {
    const end = TaskTimeColors.endRed;
    if (total <= Duration.zero) return end;
    final hold = redHoldFor(total);
    final ramp = total - hold;
    if (ramp <= Duration.zero) return end;
    if (elapsed >= ramp) return end;
    if (elapsed <= Duration.zero) return startColor;
    final t = (elapsed.inMilliseconds / ramp.inMilliseconds).clamp(0.0, 1.0);
    return HSLColor.lerp(
      HSLColor.fromColor(startColor),
      HSLColor.fromColor(end),
      t,
    )!
        .toColor();
  }

  @visibleForTesting
  static double resolveRemainingFraction({
    required Duration elapsed,
    required Duration total,
  }) {
    if (total <= Duration.zero) return 0;
    final ratio = 1 - elapsed.inMilliseconds / total.inMilliseconds;
    return ratio.clamp(0.0, 1.0);
  }

  @override
  State<TaskProgressBar> createState() => _TaskProgressBarState();
}

class _TaskProgressBarState extends State<TaskProgressBar> {
  Timer? _wakeTimer;
  Timer? _tickTimer;

  final ValueNotifier<Duration> _elapsed = ValueNotifier(Duration.zero);

  bool _running = false;

  DateTime get _now => (widget.clock ?? DateTime.now)();

  DateTime get _start => widget.task.startDateTime;

  DateTime get _end => widget.task.endDateTime;

  Duration get _total => _end.difference(_start);

  @override
  void initState() {
    super.initState();
    _syncToClock(notify: false);
  }

  @override
  void didUpdateWidget(TaskProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.task != widget.task) {
      _syncToClock();
    }
  }

  @override
  void dispose() {
    _wakeTimer?.cancel();
    _tickTimer?.cancel();
    _elapsed.dispose();
    super.dispose();
  }

  void _syncToClock({bool notify = true}) {
    _wakeTimer?.cancel();
    _tickTimer?.cancel();

    final now = _now;
    final running = !widget.task.isCompleted &&
        _total > Duration.zero &&
        !now.isBefore(_start) &&
        now.isBefore(_end);

    if (running) {
      _elapsed.value = now.difference(_start);
      _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    } else if (!widget.task.isCompleted && now.isBefore(_start)) {
      _wakeTimer = Timer(_start.difference(now), _syncToClock);
    }

    if (running == _running) return;
    _running = running;
    if (notify && mounted) setState(() {});
  }

  void _tick() {
    final now = _now;
    if (!now.isBefore(_end)) {
      _syncToClock();
      return;
    }
    _elapsed.value = now.difference(_start);
  }

  @override
  Widget build(BuildContext context) {
    if (!_running) return const SizedBox.shrink();

    final palette = AppPalette.of(context);
    final total = _total;

    return ValueListenableBuilder<Duration>(
      valueListenable: _elapsed,
      builder: (context, elapsed, _) {
        final color = TaskProgressBar.resolveColor(
          elapsed: elapsed,
          total: total,
        );
        final fraction = TaskProgressBar.resolveRemainingFraction(
          elapsed: elapsed,
          total: total,
        );

        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            RepaintBoundary(
              child: CustomPaint(
                size: const Size(
                    TaskProgressBar._barWidth, TaskProgressBar._barHeight),
                painter: _MiniProgressPainter(
                  fraction: fraction,
                  fillColor: color,
                  trackColor: TaskTimeColors.backing.withValues(alpha: 0.18),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // the strip can end up narrower than bar and label
            Flexible(
              child: Text(
                '${TimeFormatting.durationLabel(total - elapsed)} left',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MiniProgressPainter extends CustomPainter {
  const _MiniProgressPainter({
    required this.fraction,
    required this.fillColor,
    required this.trackColor,
  });

  final double fraction;
  final Color fillColor;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = Radius.circular(size.height / 2);

    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, radius),
      Paint()..color = trackColor,
    );

    if (fraction <= 0) return;

    final fillWidth = size.width * fraction;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width - fillWidth, 0, fillWidth, size.height),
        radius,
      ),
      Paint()..color = fillColor,
    );
  }

  @override
  bool shouldRepaint(_MiniProgressPainter oldDelegate) {
    return oldDelegate.fraction != fraction ||
        oldDelegate.fillColor != fillColor ||
        oldDelegate.trackColor != trackColor;
  }
}
