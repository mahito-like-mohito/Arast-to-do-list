import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/settings_controller.dart';
import '../../core/app_palette.dart';
import '../../core/constants.dart';
import '../../core/time_formatting.dart';
import '../../data/models/subtask.dart';
import '../../data/models/task.dart';
import 'active_task_ring.dart';
import 'frosted_surface.dart';
import 'note_reveal.dart';
import 'task_progress_bar.dart';

class TaskTile extends StatefulWidget {
  const TaskTile({
    super.key,
    required this.task,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleCompleted,
    this.onChecklistChanged,
    this.animateEntrance = false,
    this.clock,
  });

  final Task task;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggleCompleted;

  final ValueChanged<Task>? onChecklistChanged;

  final bool animateEntrance;

  final DateTime Function()? clock;

  @override
  State<TaskTile> createState() => _TaskTileState();
}

class _TaskTileState extends State<TaskTile> {
  Timer? _holdTimer;
  Timer? _overlayTimer;
  OverlayEntry? _overlayEntry;
  Offset? _pointerDownPosition;

  late final bool _playEntrance;

  static const double _holdMoveTolerance = 18;

  @override
  void initState() {
    super.initState();
    _playEntrance = widget.animateEntrance;
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _overlayTimer?.cancel();
    _removeOverlay();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final task = widget.task;
    final swapped = context.watch<SettingsController>().swipeSwapped;

    final editBackground = _SwipeBackground(
      color: palette.accent,
      foreground: palette.onAccent,
      icon: Icons.edit_outlined,
      label: 'Edit',
      alignment: swapped ? Alignment.centerRight : Alignment.centerLeft,
    );
    final deleteBackground = _SwipeBackground(
      color: palette.danger,
      foreground: Colors.white,
      icon: Icons.delete_outline,
      label: 'Delete',
      alignment: swapped ? Alignment.centerLeft : Alignment.centerRight,
    );

    Widget tile = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      // raw touch so long press works alongside swipe
      child: Listener(
        onPointerDown: _handlePointerDown,
        onPointerMove: _handlePointerMove,
        onPointerUp: (_) => _cancelHold(),
        onPointerCancel: (_) => _cancelHold(),
        child: Dismissible(
          key: ValueKey('task-tile-${task.id}'),
          background: swapped ? deleteBackground : editBackground,
          secondaryBackground: swapped ? editBackground : deleteBackground,
          confirmDismiss: (direction) async {
            final isEdit = swapped
                ? direction == DismissDirection.endToStart
                : direction == DismissDirection.startToEnd;
            if (isEdit) {
              widget.onEdit();
              return false;
            }
            return true;
          },
          onDismissed: (_) => widget.onDelete(),
          child: _buildCard(context, palette),
        ),
      ),
    );

    if (_playEntrance) {
      tile = TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) => Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 10 * (1 - value)),
            child: child,
          ),
        ),
        child: tile,
      );
    }

    return tile;
  }

  Widget _buildCard(BuildContext context, AppPalette palette) {
    final task = widget.task;
    final settings = context.watch<SettingsController>();
    final fontScale = settings.taskFontScale;
    // parse once for the badge instead of on every access
    final subtasks = task.subtasks;
    final doneSubtasks = subtasks.where((subtask) => subtask.isDone).length;

    return NoteReveal(
      note: task.notes,
      fontScale: fontScale,
      onChecklistChanged: widget.onChecklistChanged == null
          ? null
          : (notes) => widget.onChecklistChanged!(
                task.copyWith(notes: notes),
              ),
      child: FrostedSurface(
        color: palette.surface,
        borderRadius: BorderRadius.circular(AppConstants.cornerRadius),
        border: Border.all(color: palette.outline),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
          child: Row(
            children: [
              _CompletionRing(
                isCompleted: task.isCompleted,
                palette: palette,
                onTap: widget.onToggleCompleted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: task.isCompleted
                            ? palette.textFaint
                            : palette.textPrimary,
                        fontSize: 15.5 * fontScale,
                        fontWeight: FontWeight.w600,
                        decoration: task.isCompleted
                            ? TextDecoration.lineThrough
                            : TextDecoration.none,
                        decorationColor: palette.textFaint,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.schedule,
                          size: 13,
                          color: palette.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            TimeFormatting.rangeLabel(
                                task.startMinutes, task.endMinutes),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: palette.textSecondary,
                              fontSize: 12 * fontScale,
                            ),
                          ),
                        ),
                        if (task.delayMinutes > 0) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: palette.support.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '+${task.delayMinutes} min',
                              style: TextStyle(
                                color: palette.textPrimary,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                        if (task.alarmEnabled) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.alarm_on,
                            size: 13,
                            color: palette.support,
                          ),
                        ],
                        if (subtasks.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: palette.support.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '✓ $doneSubtasks'
                              '/${subtasks.length}',
                              style: TextStyle(
                                color: palette.textPrimary,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 16,
                      width: double.infinity,
                      child: IgnorePointer(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child:
                              TaskProgressBar(task: task, clock: widget.clock),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              ActiveTaskRing(
                task: task,
                clock: widget.clock,
                warningWindow: Duration(seconds: settings.alarmLeadSeconds),
                vibrationEnabled: settings.preTaskVibration,
                vibrationPattern: settings.vibrationStyle.pattern,
              ),
              PopupMenuButton<_TileAction>(
                icon: Icon(
                  Icons.more_vert,
                  color: palette.textSecondary,
                ),
                onSelected: (action) {
                  switch (action) {
                    case _TileAction.edit:
                      widget.onEdit();
                    case _TileAction.delete:
                      widget.onDelete();
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: _TileAction.edit,
                    child: _MenuRow(icon: Icons.edit_outlined, label: 'Edit'),
                  ),
                  PopupMenuItem(
                    value: _TileAction.delete,
                    child:
                        _MenuRow(icon: Icons.delete_outline, label: 'Delete'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handlePointerDown(PointerDownEvent event) {
    _pointerDownPosition = event.position;
    _holdTimer?.cancel();
    _holdTimer = Timer(AppConstants.longPressDuration, _showRemainingOverlay);
  }

  void _handlePointerMove(PointerMoveEvent event) {
    final origin = _pointerDownPosition;
    if (origin == null) return;
    if ((event.position - origin).distance > _holdMoveTolerance) {
      _cancelHold();
    }
  }

  void _cancelHold() {
    _holdTimer?.cancel();
    _holdTimer = null;
    _pointerDownPosition = null;
  }

  void _showRemainingOverlay() {
    if (!mounted) return;

    final palette = AppPalette.of(context);
    final overlay = Overlay.of(context);
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return;

    final tileTopCenter = box.localToGlobal(Offset(box.size.width / 2, 0));

    _removeOverlay();
    _overlayEntry = OverlayEntry(
      builder: (context) => _RemainingTimeOverlay(
        anchor: tileTopCenter,
        message: _remainingMessage(),
        palette: palette,
      ),
    );
    overlay.insert(_overlayEntry!);

    _overlayTimer?.cancel();
    _overlayTimer =
        Timer(AppConstants.remainingOverlayDuration, _removeOverlay);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  String _remainingMessage() {
    final task = widget.task;
    if (task.isCompleted) {
      return 'This task is already completed';
    }

    final now = DateTime.now();
    final start = task.startDateTime;
    final end = task.endDateTime;

    if (now.isBefore(start)) {
      final label = TimeFormatting.durationLabel(start.difference(now));
      return 'Starts in $label';
    }
    if (now.isBefore(end)) {
      final label = TimeFormatting.durationLabel(end.difference(now));
      return '$label remaining until this task concludes';
    }
    final label = TimeFormatting.durationLabel(now.difference(end));
    return 'Concluded $label ago';
  }
}

enum _TileAction { edit, delete }

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Row(
      children: [
        Icon(icon, size: 18, color: palette.textSecondary),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(color: palette.textPrimary)),
      ],
    );
  }
}

class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground({
    required this.color,
    required this.foreground,
    required this.icon,
    required this.label,
    required this.alignment,
  });

  final Color color;
  final Color foreground;
  final IconData icon;
  final String label;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppConstants.cornerRadius),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: foreground),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: foreground,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _CompletionRing extends StatelessWidget {
  const _CompletionRing({
    required this.isCompleted,
    required this.palette,
    required this.onTap,
  });

  final bool isCompleted;
  final AppPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isCompleted ? palette.accent : Colors.transparent,
          border: Border.all(
            color: isCompleted ? palette.accent : palette.textFaint,
            width: 2,
          ),
        ),
        child: isCompleted
            ? Icon(Icons.check, size: 16, color: palette.onAccent)
            : null,
      ),
    );
  }
}

class _RemainingTimeOverlay extends StatelessWidget {
  const _RemainingTimeOverlay({
    required this.anchor,
    required this.message,
    required this.palette,
  });

  final Offset anchor;

  final String message;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    const overlayWidth = 260.0;
    final screenWidth = MediaQuery.of(context).size.width;
    final left = (anchor.dx - overlayWidth / 2)
        .clamp(12.0, screenWidth - overlayWidth - 12.0);
    final top = (anchor.dy - 64).clamp(12.0, double.infinity);

    return Positioned(
      left: left,
      top: top,
      width: overlayWidth,
      child: IgnorePointer(
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: palette.inverseSurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: palette.onInverseSurface.withValues(alpha: 0.2),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(
                  Icons.hourglass_bottom,
                  size: 18,
                  color: palette.onInverseSurface.withValues(alpha: 0.8),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    message,
                    style: TextStyle(
                      color: palette.onInverseSurface,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
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
}
