import 'package:flutter/foundation.dart';

import '../controllers/settings_controller.dart';
import '../core/constants.dart';
import '../core/time_formatting.dart';
import '../data/models/task.dart';
import '../data/models/time_section.dart';
import '../data/repositories/task_repository.dart';
import 'alarm_service.dart';
import 'file_storage_service.dart';

class MaintenanceService {
  MaintenanceService()
      : _repository = TaskRepository(),
        _alarmService = AlarmService(),
        _fileStorage = FileStorageService();

  final TaskRepository _repository;
  final AlarmService _alarmService;
  final FileStorageService _fileStorage;

  static const int _morningStartMinutes = 9 * 60;

  Future<void> runStartupSweep(SettingsController settings) async {
    await _repository.purgeExpiredTrash(AppConstants.trashRetention);
    await _applyArchivePolicy(settings.archivePolicy);
    if (settings.autoRollover) {
      await _rolloverUnfinishedTasks();
    }
    await _pruneOrphanedAlarmAudio();
  }

  Future<void> _pruneOrphanedAlarmAudio() async {
    try {
      final referencing = await _repository.findAllWithCustomSound();
      final referenced = referencing
          .map((task) => task.alarmSoundUri)
          .whereType<String>()
          .toSet();
      await _fileStorage.pruneUnusedAlarmAudio(referenced);
    } catch (error) {
      debugPrint('Alarm audio prune skipped: $error');
    }
  }

  Future<void> _applyArchivePolicy(ArchivePolicy policy) async {
    final now = DateTime.now();
    final String cutoff;
    switch (policy) {
      case ArchivePolicy.keepForever:
        return;
      case ArchivePolicy.immediately:
      case ArchivePolicy.endOfDay:
        cutoff = TimeFormatting.dbDateKey(now);
        // step the calendar itself so daylight saving never skips a day
      case ArchivePolicy.afterWeek:
        cutoff = TimeFormatting.dbDateKey(
            DateTime(now.year, now.month, now.day - 7));
    }

    final expired = await _repository.findCompletedBefore(cutoff);
    for (final task in expired) {
      final id = task.id;
      if (id == null) continue;
      await _alarmService.cancelForTask(id);
      await _repository.softDelete(id);
    }
  }

  Future<void> _rolloverUnfinishedTasks() async {
    final today = TimeFormatting.dbDateKey(DateTime.now());
    final overdue = await _repository.findUncompletedBefore(today);

    for (final task in overdue) {
      final rolled = _rollIntoMorning(task, today);
      await _repository.update(rolled);
      await _alarmService.scheduleForTask(rolled);
    }
  }

  static Task _rollIntoMorning(Task task, String newDate) {
    final duration = task.endMinutes > task.startMinutes
        ? task.endMinutes - task.startMinutes
        : (24 * 60 - task.startMinutes) + task.endMinutes;

    if (task.startMinutes <= TimeSection.morning.endMinute) {
      return task.copyWith(date: newDate);
    }

    const newStart = _morningStartMinutes;
    final newEnd = (newStart + duration).clamp(newStart + 1, 24 * 60 - 1);
    return task.copyWith(
      date: newDate,
      startMinutes: newStart,
      endMinutes: newEnd,
    );
  }
}
