import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../../core/app_palette.dart';
import '../../core/constants.dart';
import '../../data/models/subtask.dart';
import 'frosted_surface.dart';
import 'subtask_editor_sheet.dart';

class NoteReveal extends StatefulWidget {
  const NoteReveal({
    super.key,
    required this.child,
    required this.note,
    this.fontScale = 1,
    this.onChecklistChanged,
  });

  final Widget child;

  final String note;

  final ValueChanged<String>? onChecklistChanged;

  final double fontScale;

  static const Key pullStripKey = Key('note-reveal-pull-strip');

  static const Key editSubtasksKey = Key('note-reveal-edit-subtasks');

  static const double pullStripHeight = 26;

  static const double lipHeight = 5;

  static const double _fallbackRevealDistance = 96;

  @override
  State<NoteReveal> createState() => _NoteRevealState();
}

class _NoteRevealState extends State<NoteReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late String _currentNote;

  final GlobalKey _noteKey = GlobalKey();

  double? _measuredHeight;

  bool _tickedOpen = false;

  bool _semanticsOpen = false;

  static final SpringDescription _spring = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 380,
    ratio: 0.9,
  );

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _currentNote = widget.note;
    _controller.addListener(_syncSemanticsState);
  }

  @override
  void didUpdateWidget(covariant NoteReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.note != oldWidget.note) _currentNote = widget.note;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isOpen => _controller.value > 0.5;

  void _syncSemanticsState() {
    if (_isOpen == _semanticsOpen) return;
    setState(() => _semanticsOpen = _isOpen);
  }

  void _handleChecklistChanged(String newNote) {
    setState(() => _currentNote = newNote);
    widget.onChecklistChanged?.call(newNote);
  }

  void _handleChecklistToggle(int index) {
    final items = Subtasks.parse(_currentNote);
    if (index < 0 || index >= items.length) return;
    items[index] = items[index].copyWith(isDone: !items[index].isDone);
    _handleChecklistChanged(Subtasks.writeBack(_currentNote, items));
  }

  double get _revealDistance {
    final measured = _measuredHeight;
    if (measured != null && measured > 8) return measured;
    return NoteReveal._fallbackRevealDistance;
  }

  void _cacheNoteHeight() {
    final size = _noteKey.currentContext?.size;
    if (size == null) return;
    if (_measuredHeight != size.height) _measuredHeight = size.height;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final delta = details.primaryDelta ?? 0;
    _controller.value =
        (_controller.value + delta / _revealDistance).clamp(0.0, 1.0);

    if (_controller.value > 0.5 != _tickedOpen) {
      _tickedOpen = _controller.value > 0.5;
      HapticFeedback.selectionClick();
    }
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = (details.primaryVelocity ?? 0) / _revealDistance;
    final open = velocity.abs() > 1.2 ? velocity > 0 : _controller.value > 0.4;
    _settle(open: open, velocity: velocity);
  }

  void _settle({required bool open, double velocity = 0}) {
    _tickedOpen = open;
    _controller.animateWith(
      SpringSimulation(_spring, _controller.value, open ? 1 : 0, velocity),
    );
  }

  void _toggle() {
    HapticFeedback.selectionClick();
    _settle(open: !_isOpen);
  }

  @override
  Widget build(BuildContext context) {
    if (_currentNote.trim().isEmpty) return widget.child;

    final palette = AppPalette.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) => _cacheNoteHeight());

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          children: [
            widget.child,
            // lock to vertical so sideways swipes still dismiss
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: NoteReveal.pullStripHeight,
              child: Semantics(
                key: NoteReveal.pullStripKey,
                container: true,
                button: true,
                expanded: _semanticsOpen,
                label: _semanticsOpen ? 'Hide note' : 'Show note',
                onTap: _toggle,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _toggle,
                  onVerticalDragUpdate: _onDragUpdate,
                  onVerticalDragEnd: _onDragEnd,
                ),
              ),
            ),
          ],
        ),
        _Sheet(
          controller: _controller,
          palette: palette,
          noteKey: _noteKey,
          note: _currentNote,
          fontScale: widget.fontScale,
          onChecklistChanged: widget.onChecklistChanged == null
              ? null
              : _handleChecklistChanged,
          onChecklistToggle: widget.onChecklistChanged == null
              ? null
              : _handleChecklistToggle,
          onPullClosed: _onDragUpdate,
          onPullEnd: _onDragEnd,
          onTap: _toggle,
        ),
      ],
    );
  }
}

class _Sheet extends StatelessWidget {
  const _Sheet({
    required this.controller,
    required this.palette,
    required this.noteKey,
    required this.note,
    required this.fontScale,
    required this.onChecklistChanged,
    required this.onChecklistToggle,
    required this.onPullClosed,
    required this.onPullEnd,
    required this.onTap,
  });

  final AnimationController controller;
  final AppPalette palette;
  final GlobalKey noteKey;
  final String note;
  final double fontScale;
  final ValueChanged<String>? onChecklistChanged;
  final ValueChanged<int>? onChecklistToggle;
  final ValueChanged<DragUpdateDetails> onPullClosed;
  final ValueChanged<DragEndDetails> onPullEnd;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final sheetColor = Color.alphaBlend(
      palette.support.withValues(alpha: 0.12),
      palette.surface,
    );

    final isChecklist = Subtasks.hasChecklist(note);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onVerticalDragUpdate: onPullClosed,
      onVerticalDragEnd: onPullEnd,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 26),
        child: FrostedSurface(
          color: sheetColor,
          borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(AppConstants.cornerRadius - 4),
          ),
          border: Border.all(color: palette.outline),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: NoteReveal.lipHeight,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.14),
                      Colors.black.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
              AnimatedBuilder(
                animation: controller,
                builder: (context, child) => ClipRect(
                  child: Align(
                    alignment: Alignment.topCenter,
                    heightFactor: controller.value.clamp(0.0, 1.0),
                    child: child,
                  ),
                ),
                child: isChecklist
                    ? _ChecklistBody(
                        noteKey: noteKey,
                        palette: palette,
                        note: note,
                        fontScale: fontScale,
                        onChecklistChanged: onChecklistChanged,
                        onChecklistToggle: onChecklistToggle,
                      )
                    : Padding(
                        key: noteKey,
                        padding: const EdgeInsets.fromLTRB(14, 2, 14, 12),
                        child: Text(
                          note,
                          style: TextStyle(
                            color: palette.textSecondary,
                            fontSize: 13 * fontScale,
                            height: 1.45,
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChecklistBody extends StatelessWidget {
  const _ChecklistBody({
    required this.noteKey,
    required this.palette,
    required this.note,
    required this.fontScale,
    required this.onChecklistChanged,
    required this.onChecklistToggle,
  });

  final GlobalKey noteKey;
  final AppPalette palette;
  final String note;
  final double fontScale;
  final ValueChanged<String>? onChecklistChanged;
  final ValueChanged<int>? onChecklistToggle;

  void _toggle(int index) {
    if (onChecklistToggle == null) return;
    HapticFeedback.selectionClick();
    onChecklistToggle!(index);
  }

  Future<void> _openEditor(BuildContext context) async {
    final changed = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SubtaskEditorSheet(initialNote: note),
    );
    if (changed != null && changed != note && onChecklistChanged != null) {
      onChecklistChanged!(changed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final prose = Subtasks.proseOnly(note).trim();
    final items = Subtasks.parse(note);
    final canEdit = onChecklistChanged != null || onChecklistToggle != null;

    return Padding(
      key: noteKey,
      padding: const EdgeInsets.fromLTRB(14, 2, 10, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (prose.isNotEmpty) ...[
            Text(
              prose,
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 13 * fontScale,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 8),
          ],
          for (var i = 0; i < items.length; i++)
            _ChecklistRow(
              item: items[i],
              palette: palette,
              fontScale: fontScale,
              onTap: canEdit ? () => _toggle(i) : null,
            ),
          if (canEdit) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: Semantics(
                button: true,
                label: 'Edit subtasks',
                child: IconButton(
                  key: NoteReveal.editSubtasksKey,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    Icons.edit_note,
                    size: 20,
                    color: palette.textSecondary,
                  ),
                  onPressed: () => _openEditor(context),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ChecklistRow extends StatelessWidget {
  const _ChecklistRow({
    required this.item,
    required this.palette,
    required this.fontScale,
    this.onTap,
  });

  final Subtask item;
  final AppPalette palette;
  final double fontScale;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                item.isDone
                    ? Icons.check_box
                    : Icons.check_box_outline_blank,
                size: 18,
                color: item.isDone ? palette.support : palette.textSecondary,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                item.text,
                style: TextStyle(
                  color: item.isDone
                      ? palette.textFaint
                      : palette.textPrimary,
                  fontSize: 13 * fontScale,
                  height: 1.35,
                  decoration: item.isDone
                      ? TextDecoration.lineThrough
                      : TextDecoration.none,
                  decorationColor: palette.textFaint,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
