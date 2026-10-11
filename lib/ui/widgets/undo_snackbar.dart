import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/app_palette.dart';
import '../../core/constants.dart';

void showUndoDeleteSnackBar(
  BuildContext context, {
  required String taskTitle,
  required VoidCallback onUndo,
}) {
  final palette = AppPalette.of(context);
  final messenger = ScaffoldMessenger.of(context);

  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      duration: const Duration(seconds: 30),
      backgroundColor: palette.inverseSurface,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      content: Row(
        children: [
          UndoCountdownRing(
            duration: AppConstants.undoGracePeriod,
            onComplete: () => messenger.hideCurrentSnackBar(),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              'Deleted "$taskTitle"',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: palette.onInverseSurface),
            ),
          ),
        ],
      ),
      action: SnackBarAction(
        label: 'Undo',
        textColor: palette.accent,
        onPressed: onUndo,
      ),
    ),
  );
}

class UndoCountdownRing extends StatefulWidget {
  const UndoCountdownRing({
    super.key,
    required this.duration,
    this.size = 30,
    this.onComplete,
  });

  final Duration duration;
  final double size;

  final VoidCallback? onComplete;

  @override
  State<UndoCountdownRing> createState() => _UndoCountdownRingState();
}

class _UndoCountdownRingState extends State<UndoCountdownRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) widget.onComplete?.call();
      })
      ..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final remainingFraction = 1 - _controller.value;
          final remainingSeconds =
              (widget.duration.inMilliseconds * remainingFraction / 1000)
                  .ceil();
          return CustomPaint(
            size: Size.square(widget.size),
            painter: _CountdownRingPainter(fraction: remainingFraction),
            child: SizedBox.square(
              dimension: widget.size,
              child: Center(
                child: Text(
                  '$remainingSeconds',
                  style: TextStyle(
                    color: AppPalette.of(context).onInverseSurface,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CountdownRingPainter extends CustomPainter {
  _CountdownRingPainter({required this.fraction});

  final double fraction;

  static const double _strokeWidth = 3;

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
        ..color = AppPalette.brown,
    );

    if (fraction > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        fraction * 2 * math.pi,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _strokeWidth
          ..strokeCap = StrokeCap.round
          ..color = AppPalette.lightBlue,
      );
    }
  }

  @override
  bool shouldRepaint(_CountdownRingPainter oldDelegate) {
    return oldDelegate.fraction != fraction;
  }
}
