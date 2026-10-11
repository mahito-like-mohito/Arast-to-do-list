import 'package:flutter/material.dart';

import '../core/time_formatting.dart';
import '../data/models/task.dart';
import '../data/models/time_section.dart';
import '../data/repositories/task_repository.dart';

@immutable
class ScheduleSuggestion {
  const ScheduleSuggestion({
    required this.start,
    required this.end,
    required this.reason,
  });

  final TimeOfDay start;
  final TimeOfDay end;

  final String reason;
}

class SuggestionService {
  SuggestionService({TaskRepository? repository})
      : _repository = repository ?? TaskRepository();

  final TaskRepository _repository;

  static const int _historyDays = 30;

  static const int _defaultDurationMinutes = 60;

  Future<List<ScheduleSuggestion>> suggestFor({
    required DateTime date,
    required List<Task> existing,
    int maxSuggestions = 3,
  }) async {
    final to = DateTime.now();
    // step the calendar itself so daylight saving never skips a day
    final from = DateTime(to.year, to.month, to.day - _historyDays);
    final history = await _repository.findBetweenDates(
      TimeFormatting.dbDateKey(from),
      TimeFormatting.dbDateKey(to),
    );

    final stats = _blockStats(history);
    final typicalDuration = _typicalDurationMinutes(history);

    final rankedBlocks = List.of(TimeSection.values)
      ..sort((a, b) {
        final scoreA = stats[a]?.completionRate ?? 0.5;
        final scoreB = stats[b]?.completionRate ?? 0.5;
        if (scoreA != scoreB) return scoreB.compareTo(scoreA);
        return a.startMinute.compareTo(b.startMinute);
      });

    final suggestions = <ScheduleSuggestion>[];
    for (final block in rankedBlocks) {
      if (suggestions.length >= maxSuggestions) break;

      final slotStart = _firstFreeSlot(block, existing, typicalDuration);
      if (slotStart == null) continue;

      final blockStat = stats[block];
      final reason = blockStat != null && blockStat.total >= 3
          ? '${(blockStat.completionRate * 100).round()} percent of your '
              '${block.title} tasks get done'
          : 'A quiet stretch in your ${block.title} block';

      suggestions.add(
        ScheduleSuggestion(
          start: TimeOfDay(
              hour: slotStart ~/ 60, minute: slotStart % 60),
          end: TimeOfDay(
              hour: ((slotStart + typicalDuration) % (24 * 60)) ~/ 60,
              minute: (slotStart + typicalDuration) % 60),
          reason: reason,
        ),
      );
    }
    return suggestions;
  }

  Map<TimeSection, _BlockStat> _blockStats(List<Task> history) {
    final stats = <TimeSection, _BlockStat>{};
    for (final task in history) {
      final stat = stats.putIfAbsent(task.section, _BlockStat.new);
      stat.total++;
      if (task.isCompleted) stat.completed++;
    }
    return stats;
  }

  int _typicalDurationMinutes(List<Task> history) {
    final durations = history
        .map((t) => t.endMinutes - t.startMinutes)
        .where((d) => d > 0)
        .toList()
      ..sort();
    if (durations.isEmpty) return _defaultDurationMinutes;
    final median = durations[durations.length ~/ 2];
    final snapped = ((median / 15).round() * 15).clamp(15, 240);
    return snapped;
  }

  int? _firstFreeSlot(
    TimeSection block,
    List<Task> existing,
    int durationMinutes,
  ) {
    for (var start = block.startMinute;
        start + durationMinutes - 1 <= block.endMinute;
        start += 30) {
      final end = start + durationMinutes;
      final collides = existing.any((task) {
        final taskEnd = task.endMinutes + task.delayMinutes;
        return start < taskEnd && task.startMinutes < end;
      });
      if (!collides) return start;
    }
    return null;
  }
}

class _BlockStat {
  int total = 0;
  int completed = 0;

  double get completionRate => total == 0 ? 0 : completed / total;
}
