import 'dart:async';
import 'dart:math' as math;

import 'package:arast_haptics/arast_haptics.dart';
import 'package:flutter/material.dart';

import '../../core/task_time_colors.dart';
import '../../data/models/task.dart';

class ActiveTaskRing extends StatefulWidget {
  const ActiveTaskRing({
    super.key,
    required this.task,
    this.size = 46,
    this.clock,
    this.warningWindow = defaultUrgentWindow,
    this.vibrationEnabled = true,
    this.vibrationPattern = const [0, 200, 120, 200, 120, 200],
  });

  final Task task;

  final double size;

  final DateTime Function()? clock;

  final Duration warningWindow;

  final bool vibrationEnabled;

  final List<int> vibrationPattern;

  static const Duration defaultUrgentWindow = Duration(seconds: 30);

  @visibleForTesting
  static Color resolveRingColor({
    required Duration remaining,
    required Color baseColor,
    required double flashPhase,
    Duration urgentWindow = defaultUrgentWindow,
  }) {
    if (remaining <= Duration.zero) return baseColor;
    if (remaining >= urgentWindow) return baseColor;
    return flashPhase < 0.5
        ? TaskTimeColors.imminentGreen
        : TaskTimeColors.flashWhite;
  }

  @override
  State<ActiveTaskRing> createState() => _ActiveTaskRingState();
}

enum _TrackPhase { pending, imminent, main, extra, done }

class _ActiveTaskRingState extends State<ActiveTaskRing>
    with TickerProviderStateMixin {
  late final AnimationController _flashController;

  Timer? _wakeTimer;
  Timer? _startTimer;
  Timer? _progressTimer;

  final ValueNotifier<double> _progressNotifier = ValueNotifier(0);

  _TrackPhase _phase = _TrackPhase.pending;

  DateTime get _now => (widget.clock ?? DateTime.now)();

  DateTime get _start => widget.task.startDateTime;

  DateTime get _mainEnd => widget.task.endDateTime
      .subtract(Duration(minutes: widget.task.delayMinutes));

  DateTime get _effectiveEnd => widget.task.endDateTime;

  bool get _hasExtraTime => widget.task.delayMinutes > 0;

  @override
  void initState() {
    super.initState();

    _flashController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );

    _syncToClock();
  }

  @override
  void didUpdateWidget(ActiveTaskRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.task != widget.task ||
        oldWidget.warningWindow != widget.warningWindow) {
      _syncToClock();
    }
  }

  @override
  void dispose() {
    _wakeTimer?.cancel();
    _wakeTimer = null;
    _startTimer?.cancel();
    _startTimer = null;
    _progressTimer?.cancel();
    _progressTimer = null;
    _flashController.dispose();
    _progressNotifier.dispose();
    super.dispose();
  }

  void _syncToClock() {
    _wakeTimer?.cancel();
    _startTimer?.cancel();
    _progressTimer?.cancel();

    final now = _now;
    final warnAt = _start.subtract(widget.warningWindow);
    final _TrackPhase phase;
    if (widget.task.isCompleted) {
      phase = _TrackPhase.done;
    } else if (now.isBefore(warnAt)) {
      phase = _TrackPhase.pending;
    } else if (now.isBefore(_start)) {
      phase = _TrackPhase.imminent;
    } else if (now.isBefore(_mainEnd)) {
      phase = _TrackPhase.main;
    } else if (_hasExtraTime && now.isBefore(_effectiveEnd)) {
      phase = _TrackPhase.extra;
    } else {
      phase = _TrackPhase.done;
    }

    if (phase == _TrackPhase.pending) {
      _wakeTimer = Timer(warnAt.difference(now), _syncToClock);
    } else if (phase == _TrackPhase.imminent) {
      final toStart = _start.difference(now);
      if (toStart > Duration.zero) {
        _startTimer = Timer(toStart, _syncToClock);
      }
      _progressTimer = Timer.periodic(
        const Duration(milliseconds: 500),
        (_) => _onTick(),
      );
      if (_phase != _TrackPhase.imminent && widget.vibrationEnabled) {
        unawaited(ArastHaptics.vibrate(widget.vibrationPattern));
      }
    }

    _progressNotifier.value = _computeProgress();
    if (_phase != phase) {
      setState(() => _phase = phase);
    }
    _updateFlashState();
  }

  void _onTick() {
    final now = _now;

    if (_phase == _TrackPhase.imminent && !now.isBefore(_start)) {
      _syncToClock();
      return;
    }

    _updateFlashState();
    _progressNotifier.value = _computeProgress();
  }

  Duration get _remaining {
    final left = _start.difference(_now);
    return left.isNegative ? Duration.zero : left;
  }

  void _updateFlashState() {
    final urgent = _phase == _TrackPhase.imminent;

    if (urgent && !_flashController.isAnimating) {
      _flashController.repeat();
    } else if (!urgent && _flashController.isAnimating) {
      _flashController.stop();
      _flashController.value = 0;
    }
  }

  double _computeProgress() {
    if (_phase != _TrackPhase.imminent) return 0;
    final total = widget.warningWindow.inMilliseconds;
    if (total <= 0) return 1;
    final elapsed = total - _start.difference(_now).inMilliseconds;
    return (elapsed / total).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    if (_phase != _TrackPhase.imminent || widget.task.isCompleted) {
      if (_phase == _TrackPhase.pending || _phase == _TrackPhase.done) {
        return const SizedBox.shrink();
      }
      // keep the space so the row never jumps
      return SizedBox(width: widget.size + 8, height: widget.size + 4);
    }

    const baseColor = TaskTimeColors.imminentGreen;

    return SizedBox(
      width: widget.size + 8,
      height: widget.size + 4,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomLeft,
        children: [
          RepaintBoundary(
            child: AnimatedBuilder(
              animation:
                  Listenable.merge([_flashController, _progressNotifier]),
              builder: (context, _) {
                final ringColor = ActiveTaskRing.resolveRingColor(
                  remaining: _remaining,
                  baseColor: baseColor,
                  flashPhase: _flashController.value,
                  urgentWindow: widget.warningWindow,
                );
                return CustomPaint(
                  size: Size.square(widget.size),
                  painter: _StopwatchRingPainter(
                    progress: _progressNotifier.value,
                    ringColor: ringColor,
                    backingColor:
                        TaskTimeColors.backing.withValues(alpha: 0.18),
                  ),
                  child: SizedBox.square(
                    dimension: widget.size,
                    child: Icon(
                      Icons.notifications_active_outlined,
                      size: widget.size * 0.44,
                      color: baseColor,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _StopwatchRingPainter extends CustomPainter {
  _StopwatchRingPainter({
    required this.progress,
    required this.ringColor,
    required this.backingColor,
  });

  final double progress;
  final Color ringColor;
  final Color backingColor;

  static const double _strokeWidth = 3.5;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - _strokeWidth) / 2;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _strokeWidth
        ..color = backingColor,
    );

    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        progress * 2 * math.pi,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _strokeWidth
          ..strokeCap = StrokeCap.round
          ..color = ringColor,
      );
    }
  }

  @override
  bool shouldRepaint(_StopwatchRingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.ringColor != ringColor ||
        oldDelegate.backingColor != backingColor;
  }
}
