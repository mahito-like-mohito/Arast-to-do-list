import 'package:flutter/material.dart';

import 'time_section.dart';

enum AlarmSoundType {
  system,

  custom,
}

@immutable
class Task {
  const Task({
    this.id,
    required this.title,
    this.notes = '',
    required this.date,
    required this.startMinutes,
    required this.endMinutes,
    this.delayMinutes = 0,
    this.isCompleted = false,
    this.alarmEnabled = false,
    this.alarmSoundType = AlarmSoundType.system,
    this.alarmSoundUri,
    this.alarmSoundLabel,
    this.deletedAt,
  });

  final int? id;

  final String title;
  final String notes;

  final String date;

  final int startMinutes;

  final int endMinutes;

  final int delayMinutes;

  final bool isCompleted;

  final bool alarmEnabled;

  final AlarmSoundType alarmSoundType;

  final String? alarmSoundUri;

  final String? alarmSoundLabel;

  final String? deletedAt;

  bool get isDeleted => deletedAt != null;

  DateTime? get deletedAtTime =>
      deletedAt == null ? null : DateTime.tryParse(deletedAt!);

  TimeSection get section => TimeSection.fromStartMinute(startMinutes);

  DateTime get dateTime => DateTime.parse(date);

  // build from parts so dst days keep the right time
  DateTime get startDateTime {
    final day = dateTime;
    return DateTime(
      day.year,
      day.month,
      day.day,
      startMinutes ~/ 60,
      startMinutes % 60,
    );
  }

  DateTime get endDateTime {
    final day = dateTime;
    final crossesMidnight = endMinutes <= startMinutes;
    final totalMinutes = endMinutes + delayMinutes;
    return DateTime(
      day.year,
      day.month,
      day.day + (crossesMidnight ? 1 : 0),
      totalMinutes ~/ 60,
      totalMinutes % 60,
    );
  }

  TimeOfDay get startTimeOfDay =>
      TimeOfDay(hour: startMinutes ~/ 60, minute: startMinutes % 60);

  TimeOfDay get endTimeOfDay =>
      TimeOfDay(hour: endMinutes ~/ 60, minute: endMinutes % 60);

  Task copyWith({
    int? id,
    String? title,
    String? notes,
    String? date,
    int? startMinutes,
    int? endMinutes,
    int? delayMinutes,
    bool? isCompleted,
    bool? alarmEnabled,
    AlarmSoundType? alarmSoundType,
    String? alarmSoundUri,
    String? alarmSoundLabel,
    String? deletedAt,
    bool clearDeletedAt = false,
    // plain null means keep so flags clear a field
    bool clearAlarmSound = false,
  }) {
    return Task(
      id: id ?? this.id,
      title: title ?? this.title,
      notes: notes ?? this.notes,
      date: date ?? this.date,
      startMinutes: startMinutes ?? this.startMinutes,
      endMinutes: endMinutes ?? this.endMinutes,
      delayMinutes: delayMinutes ?? this.delayMinutes,
      isCompleted: isCompleted ?? this.isCompleted,
      alarmEnabled: alarmEnabled ?? this.alarmEnabled,
      alarmSoundType: clearAlarmSound
          ? AlarmSoundType.system
          : (alarmSoundType ?? this.alarmSoundType),
      alarmSoundUri:
          clearAlarmSound ? null : (alarmSoundUri ?? this.alarmSoundUri),
      alarmSoundLabel:
          clearAlarmSound ? null : (alarmSoundLabel ?? this.alarmSoundLabel),
      deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
    );
  }

  Map<String, Object?> toMap() {
    return {
      TaskFields.id: id,
      TaskFields.title: title,
      TaskFields.notes: notes,
      TaskFields.date: date,
      TaskFields.startMinutes: startMinutes,
      TaskFields.endMinutes: endMinutes,
      TaskFields.delayMinutes: delayMinutes,
      TaskFields.isCompleted: isCompleted ? 1 : 0,
      TaskFields.alarmEnabled: alarmEnabled ? 1 : 0,
      TaskFields.alarmSoundType: alarmSoundType.name,
      TaskFields.alarmSoundUri: alarmSoundUri,
      TaskFields.alarmSoundLabel: alarmSoundLabel,
      TaskFields.deletedAt: deletedAt,
    };
  }

  factory Task.fromMap(Map<String, Object?> map) {
    return Task(
      id: map[TaskFields.id] as int?,
      title: map[TaskFields.title] as String,
      notes: (map[TaskFields.notes] as String?) ?? '',
      date: map[TaskFields.date] as String,
      startMinutes: map[TaskFields.startMinutes] as int,
      endMinutes: map[TaskFields.endMinutes] as int,
      delayMinutes: (map[TaskFields.delayMinutes] as int?) ?? 0,
      isCompleted: (map[TaskFields.isCompleted] as int? ?? 0) == 1,
      alarmEnabled: (map[TaskFields.alarmEnabled] as int? ?? 0) == 1,
      alarmSoundType: AlarmSoundType.values.asNameMap()[
              map[TaskFields.alarmSoundType] as String? ?? ''] ??
          AlarmSoundType.system,
      alarmSoundUri: map[TaskFields.alarmSoundUri] as String?,
      alarmSoundLabel: map[TaskFields.alarmSoundLabel] as String?,
      deletedAt: map[TaskFields.deletedAt] as String?,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Task &&
        other.id == id &&
        other.title == title &&
        other.notes == notes &&
        other.date == date &&
        other.startMinutes == startMinutes &&
        other.endMinutes == endMinutes &&
        other.delayMinutes == delayMinutes &&
        other.isCompleted == isCompleted &&
        other.alarmEnabled == alarmEnabled &&
        other.alarmSoundType == alarmSoundType &&
        other.alarmSoundUri == alarmSoundUri &&
        other.alarmSoundLabel == alarmSoundLabel &&
        other.deletedAt == deletedAt;
  }

  @override
  int get hashCode => Object.hash(
        id,
        title,
        notes,
        date,
        startMinutes,
        endMinutes,
        delayMinutes,
        isCompleted,
        alarmEnabled,
        alarmSoundType,
        alarmSoundUri,
        alarmSoundLabel,
        deletedAt,
      );

  @override
  String toString() => 'Task(id: $id, title: $title, date: $date, '
      'start: $startMinutes, end: $endMinutes)';
}

abstract final class TaskFields {
  static const String tableName = 'tasks';

  static const String id = 'id';
  static const String title = 'title';
  static const String notes = 'notes';
  static const String date = 'date';
  static const String startMinutes = 'start_minutes';
  static const String endMinutes = 'end_minutes';
  static const String delayMinutes = 'delay_minutes';
  static const String isCompleted = 'is_completed';
  static const String alarmEnabled = 'alarm_enabled';
  static const String alarmSoundType = 'alarm_sound_type';
  static const String alarmSoundUri = 'alarm_sound_uri';
  static const String alarmSoundLabel = 'alarm_sound_label';
  static const String deletedAt = 'deleted_at';
}
