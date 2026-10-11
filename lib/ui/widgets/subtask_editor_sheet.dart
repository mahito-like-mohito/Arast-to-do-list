import 'package:flutter/material.dart';

import '../../core/app_palette.dart';
import '../../data/models/subtask.dart';
import 'frosted_surface.dart';

class _DeletingRow {
  _DeletingRow({required this.controller, required this.isDone});
  final TextEditingController controller;
  final bool isDone;
}

class _ExitAnimationRow extends StatefulWidget {
  const _ExitAnimationRow({
    required this.controller,
    required this.isDone,
    required this.animation,
    required this.onDispose,
  });

  final TextEditingController controller;
  final bool isDone;
  final Animation<double> animation;
  final VoidCallback onDispose;

  @override
  State<_ExitAnimationRow> createState() => _ExitAnimationRowState();
}

class _ExitAnimationRowState extends State<_ExitAnimationRow> {
  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SizeTransition(
      sizeFactor: widget.animation,
      child: Padding(
        padding: const EdgeInsets.only(left: 16, right: 4),
        child: Row(
          children: [
            Expanded(
              child: IgnorePointer(
                child: TextField(
                  controller: widget.controller,
                  style: TextStyle(color: palette.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Subtask',
                    hintStyle: TextStyle(color: palette.textFaint),
                  ),
                ),
              ),
            ),
            const IconButton(
              icon: Icon(Icons.delete_outline, size: 20),
              onPressed: null,
            ),
          ],
        ),
      ),
    );
  }
}

class SubtaskEditorSheet extends StatefulWidget {
  const SubtaskEditorSheet({super.key, required this.initialNote});

  final String initialNote;

  @override
  State<SubtaskEditorSheet> createState() => _SubtaskEditorSheetState();
}

class _SubtaskEditorSheetState extends State<SubtaskEditorSheet> {
  late final List<TextEditingController> _controllers;
  late final List<bool> _done;
  late final GlobalKey<AnimatedListState> _listKey;

  // each leaving row disposes its own controller
  final Map<int, _DeletingRow> _exiting = {};

  @override
  void initState() {
    super.initState();
    final items = Subtasks.parse(widget.initialNote);
    _controllers = [
      for (final item in items) TextEditingController(text: item.text),
    ];
    _done = [for (final item in items) item.isDone];
    _listKey = GlobalKey<AnimatedListState>();
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    for (final exiting in _exiting.values) {
      exiting.controller.dispose();
    }
    super.dispose();
  }

  void _add() {
    _listKey.currentState?.insertItem(_controllers.length);
    _controllers.add(TextEditingController());
    _done.add(false);
    setState(() {});
  }

  void _delete(int index) {
    _exiting[index] = _DeletingRow(
      controller: _controllers.removeAt(index),
      isDone: _done.removeAt(index),
    );
    _listKey.currentState?.removeItem(
      index,
      (context, animation) {
        final row = _exiting.remove(index)!;
        return _ExitAnimationRow(
          controller: row.controller,
          isDone: row.isDone,
          animation: animation,
          onDispose: () => row.controller.dispose(),
        );
      },
      duration: const Duration(milliseconds: 200),
    );
    setState(() {});
  }

  void _save() {
    final items = <Subtask>[];
    for (var i = 0; i < _controllers.length; i++) {
      final text = _controllers[i].text.trim();
      if (text.isEmpty) continue;
      items.add(Subtask(text: text, isDone: _done[i]));
    }
    Navigator.of(context).pop(Subtasks.writeBack(widget.initialNote, items));
  }

  Widget _row(int index, Animation<double> animation) {
    final palette = AppPalette.of(context);
    return SizeTransition(
      sizeFactor: animation,
      child: Padding(
        padding: const EdgeInsets.only(left: 16, right: 4),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controllers[index],
                style: TextStyle(color: palette.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Subtask',
                  hintStyle: TextStyle(color: palette.textFaint),
                ),
              ),
            ),
            IconButton(
              icon: Icon(
                Icons.delete_outline,
                size: 20,
                color: palette.danger,
              ),
              onPressed: () => _delete(index),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return FrostedSurface(
      color: palette.surfaceElevated,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Edit subtasks',
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _save,
                    child: const Text('Done'),
                  ),
                ],
              ),
            ),
            Flexible(
              child: AnimatedList(
                key: _listKey,
                initialItemCount: _controllers.length,
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 8),
                itemBuilder: (context, index, animation) =>
                    _row(index, animation),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _add,
                  icon: const Icon(Icons.add),
                  label: const Text('Add subtask'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
