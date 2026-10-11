import 'package:flutter/foundation.dart';

import 'task.dart';

@immutable
class Subtask {
  const Subtask({required this.text, this.isDone = false});

  final String text;
  final bool isDone;

  Subtask copyWith({String? text, bool? isDone}) => Subtask(
        text: text ?? this.text,
        isDone: isDone ?? this.isDone,
      );
}

abstract final class Subtasks {
  static final RegExp _linePattern = RegExp(r'^- \[([ xX])\] *(.*)$');

  static bool _isChecklistLine(String line) => _linePattern.hasMatch(line);

  static bool hasChecklist(String note) =>
      note.split('\n').any(_isChecklistLine);

  static String proseOnly(String note) => [
        for (final line in note.split('\n'))
          if (!_isChecklistLine(line)) line,
      ].join('\n');

  static List<Subtask> parse(String note) {
    return [
      for (final line in note.split('\n'))
        if (_isChecklistLine(line))
          Subtask(
            text: _linePattern.firstMatch(line)![2]!.trim(),
            isDone: _linePattern.firstMatch(line)![1] != ' ',
          ),
    ];
  }

  static String writeBack(String note, List<Subtask> items) {
    final lines = note.split('\n');
    final serialized = [
      for (final item in items)
        '- [${item.isDone ? 'x' : ' '}] ${item.text}',
    ];

    final first = lines.indexWhere(_isChecklistLine);
    if (first < 0) {
      if (serialized.isEmpty) return note;
      final prose = note.trimRight();
      return prose.isEmpty
          ? serialized.join('\n')
          : '$prose\n${serialized.join('\n')}';
    }

    return [
      for (var i = 0; i < lines.length; i++)
        if (i == first)
          ...serialized
        else if (!_isChecklistLine(lines[i]))
          lines[i],
    ].join('\n');
  }
}

extension TaskSubtasks on Task {
  bool get hasChecklist => Subtasks.hasChecklist(notes);

  List<Subtask> get subtasks => Subtasks.parse(notes);

  int get doneSubtaskCount => subtasks.where((s) => s.isDone).length;
}
