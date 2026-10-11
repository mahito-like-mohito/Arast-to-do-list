import '../data/models/task.dart';

abstract final class ScheduleValidator {
  static Task? findConflict({
    required int startMinutes,
    required int endMinutes,
    required List<Task> existing,
    int? editingTaskId,
    List<Task> nextDayExisting = const [],
  }) {
    final crossesMidnight = endMinutes <= startMinutes;

    final sameDayEnd = crossesMidnight ? 24 * 60 : endMinutes;
    final sameDayConflict = _firstOverlap(
      startMinutes: startMinutes,
      endMinutes: sameDayEnd,
      candidates: existing,
      editingTaskId: editingTaskId,
    );
    if (sameDayConflict != null) return sameDayConflict;

    if (crossesMidnight && endMinutes > 0) {
      return _firstOverlap(
        startMinutes: 0,
        endMinutes: endMinutes,
        candidates: nextDayExisting,
        editingTaskId: editingTaskId,
      );
    }
    return null;
  }

  static Task? _firstOverlap({
    required int startMinutes,
    required int endMinutes,
    required List<Task> candidates,
    required int? editingTaskId,
  }) {
    for (final task in candidates) {
      if (task.id != null && task.id == editingTaskId) continue;
      if (task.isDeleted) continue;

      final existingStart = task.startMinutes;
      final existingEndRaw = task.endMinutes + task.delayMinutes;
      final existingEnd =
          existingEndRaw > existingStart ? existingEndRaw : 24 * 60;

      if (startMinutes < existingEnd && endMinutes > existingStart) {
        return task;
      }
    }
    return null;
  }
}
