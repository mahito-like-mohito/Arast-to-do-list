import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/constants.dart';
import '../core/time_formatting.dart';
import '../data/models/subtask.dart';
import '../data/models/task.dart';
import '../data/models/time_section.dart';
import '../data/repositories/task_repository.dart';
import '../services/alarm_service.dart';

class TaskListController extends ChangeNotifier {
  TaskListController({
    TaskRepository? repository,
    AlarmService? alarmService,
    this.undoGracePeriod = AppConstants.undoGracePeriod,
  })  : _repository = repository ?? TaskRepository(),
        _alarmService = alarmService ?? AlarmService() {
    _selectedDate = _dateOnly(DateTime.now());
  }

  final TaskRepository _repository;
  final AlarmService _alarmService;

  final Duration undoGracePeriod;

  late DateTime _selectedDate;
  List<Task> _tasks = const [];
  bool _isLoading = false;

  final Map<int, Timer> _pendingDeletions = {};

  int? _lastRestoredTaskId;
  DateTime? _lastRestoredAt;

  DateTime get selectedDate => _selectedDate;
  bool get isLoading => _isLoading;
  bool get isEmpty => _tasks.isEmpty;

  Map<TimeSection, List<Task>> get groupedTasks {
    final groups = <TimeSection, List<Task>>{};
    for (final task in _tasks) {
      groups.putIfAbsent(task.section, () => []).add(task);
    }
    return groups;
  }

  String get selectedDateKey => TimeFormatting.dbDateKey(_selectedDate);

  Future<void> loadTasks() async {
    _isLoading = true;
    notifyListeners();

    await _reloadTasks();

    _isLoading = false;
    notifyListeners();
  }

  Future<void> _reloadTasks() async {
    final rows = await _repository.findByDate(selectedDateKey);
    _tasks = rows
        .where((task) => !_pendingDeletions.containsKey(task.id))
        .toList();
  }

  Future<void> selectDate(DateTime date) async {
    _selectedDate = _dateOnly(date);
    await loadTasks();
  }

  Future<void> goToPreviousDay() => selectDate(
      DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day - 1));

  // step the calendar itself so daylight saving never skips a day
  Future<void> goToNextDay() => selectDate(
      DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day + 1));

  Future<void> goToToday() => selectDate(DateTime.now());

  Future<Task> saveTask(Task task) async {
    task = _applyChecklistCompletion(task);

    final Task saved;
    if (task.id == null) {
      saved = await _repository.insert(task);
    } else {
      await _repository.update(task);
      saved = task;
    }

    await _alarmService.scheduleForTask(saved);
    await _reloadTasks();
    notifyListeners();
    return saved;
  }

  Task _applyChecklistCompletion(Task task) {
    // parse once and reuse it for both steps
    final subtasks = task.subtasks;
    if (subtasks.isEmpty) return task;
    final allDone = subtasks.every((subtask) => subtask.isDone);
    if (allDone && !task.isCompleted) return task.copyWith(isCompleted: true);
    if (!allDone && task.isCompleted) return task.copyWith(isCompleted: false);
    return task;
  }

  Future<void> deleteTaskDeferred(Task task) async {
    final id = task.id;
    if (id == null) return;

    _pendingDeletions[id]?.cancel();
    _pendingDeletions[id] =
        Timer(undoGracePeriod, () => _finalizeDeletion(id));

    await _alarmService.cancelForTask(id);

    await loadTasks();
  }

  Future<bool> undoDeleteTask(Task task) async {
    final id = task.id;
    if (id == null) return false;

    final timer = _pendingDeletions.remove(id);
    if (timer == null) return false;
    timer.cancel();

    await _alarmService.scheduleForTask(task);

    _lastRestoredTaskId = id;
    _lastRestoredAt = DateTime.now();
    await loadTasks();
    return true;
  }

  bool shouldAnimateRestore(int? taskId) {
    final restoredAt = _lastRestoredAt;
    return taskId != null &&
        taskId == _lastRestoredTaskId &&
        restoredAt != null &&
        DateTime.now().difference(restoredAt) < const Duration(seconds: 2);
  }

  Future<void> _finalizeDeletion(int id) async {
    if (_pendingDeletions.remove(id) == null) return;

    await _alarmService.cancelForTask(id);
    await _repository.softDelete(id);
    await loadTasks();
  }

  Future<void> toggleCompleted(
    Task task, {
    bool archiveWhenCompleted = false,
  }) async {
    final updated = task.copyWith(isCompleted: !task.isCompleted);
    await _repository.update(updated);
    if (updated.isCompleted) {
      await _alarmService.cancelForTask(updated.id!);
      if (archiveWhenCompleted) {
        await _repository.softDelete(updated.id!);
      }
    } else {
      await _alarmService.scheduleForTask(updated);
    }
    await loadTasks();
  }

  Future<List<Task>> tasksOn(DateTime date) {
    return _repository.findByDate(TimeFormatting.dbDateKey(_dateOnly(date)));
  }

  Future<List<Task>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const <Task>[];
    final results = await _repository.search(trimmed);
    return results
        .where((task) => !_pendingDeletions.containsKey(task.id))
        .toList();
  }

  @override
  void dispose() {
    for (final timer in _pendingDeletions.values) {
      timer.cancel();
    }
    _pendingDeletions.clear();
    super.dispose();
  }

  static DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);
}
