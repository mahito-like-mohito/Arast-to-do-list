import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:arast_alarm/arast_alarm.dart';

import 'package:advanced_todo_list/controllers/settings_controller.dart';
import 'package:advanced_todo_list/core/alarm_schedule.dart';
import 'package:advanced_todo_list/core/constants.dart';
import 'package:advanced_todo_list/core/time_formatting.dart';
import 'package:advanced_todo_list/data/database/database_helper.dart';
import 'package:advanced_todo_list/data/models/task.dart';
import 'package:advanced_todo_list/data/repositories/task_repository.dart';
import 'package:advanced_todo_list/core/schedule_validator.dart';
import 'package:advanced_todo_list/services/alarm_service.dart';
import 'package:advanced_todo_list/services/settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // ffi so the real schema runs in vm tests
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Trash system (soft deletion)', () {
    late TaskRepository repository;

    setUp(() async {
      final dbDir = await databaseFactory.getDatabasesPath();
      await databaseFactory.deleteDatabase('$dbDir/advanced_todo.db');
      await DatabaseHelper.instance.resetForTesting();
      repository = TaskRepository();
    });

    Task newTask(String title, {bool completed = false}) => Task(
          title: title,
          date: '2026-07-26',
          startMinutes: 9 * 60,
          endMinutes: 10 * 60,
          isCompleted: completed,
        );

    test('soft-deleted tasks vanish from live queries but stay in the '
        'database', () async {
      final task = await repository.insert(newTask('Doomed'));
      await repository.softDelete(task.id!);

      expect(await repository.findByDate('2026-07-26'), isEmpty);
      expect(await repository.search('Doomed'), isEmpty);

      final trashed = await repository.findTrashed();
      expect(trashed, hasLength(1));
      expect(trashed.single.title, 'Doomed');
      expect(trashed.single.isDeleted, isTrue);
    });

    test('restore returns the task unchanged to its original slot',
        () async {
      final task = await repository.insert(newTask('Rescued'));
      await repository.softDelete(task.id!);
      await repository.restoreFromTrash(task.id!);

      final live = await repository.findByDate('2026-07-26');
      expect(live, hasLength(1));
      expect(live.single.title, 'Rescued');
      expect(live.single.isDeleted, isFalse);
      expect(await repository.findTrashed(), isEmpty);
    });

    test('retention purge removes only rows older than the window',
        () async {
      final old = await repository.insert(newTask('Expired'));
      final recent = await repository.insert(newTask('Still safe'));
      final now = DateTime(2026, 7, 26);

      await repository.softDelete(old.id!,
          now: now.subtract(const Duration(days: 31)));
      await repository.softDelete(recent.id!,
          now: now.subtract(const Duration(days: 5)));

      final purged = await repository.purgeExpiredTrash(
        AppConstants.trashRetention,
        now: now,
      );

      expect(purged, 1);
      final remaining = await repository.findTrashed();
      expect(remaining.single.title, 'Still safe');
    });

    test('manual empty-trash purges everything at once', () async {
      for (var i = 0; i < 3; i++) {
        final task = await repository.insert(newTask('Task $i'));
        await repository.softDelete(task.id!);
      }

      expect(await repository.purgeAllTrash(), 3);
      expect(await repository.findTrashed(), isEmpty);
    });

    test('archive sweep queries find old completed tasks only', () async {
      await repository.insert(
          newTask('Done yesterday', completed: true)
              .copyWith(date: '2026-07-20'));
      await repository.insert(newTask('Done today', completed: true));
      await repository
          .insert(newTask('Unfinished').copyWith(date: '2026-07-20'));

      final oldCompleted =
          await repository.findCompletedBefore('2026-07-26');
      expect(oldCompleted, hasLength(1));
      expect(oldCompleted.single.title, 'Done yesterday');

      final oldUnfinished =
          await repository.findUncompletedBefore('2026-07-26');
      expect(oldUnfinished, hasLength(1));
      expect(oldUnfinished.single.title, 'Unfinished');
    });
  });

  group('Quiet hours window', () {
    test('handles same-day and midnight-wrapping ranges', () {
      expect(
        SettingsController.isWithinQuietHours(
            nowMinutes: 14 * 60, startMinutes: 13 * 60, endMinutes: 15 * 60),
        isTrue,
      );
      expect(
        SettingsController.isWithinQuietHours(
            nowMinutes: 16 * 60, startMinutes: 13 * 60, endMinutes: 15 * 60),
        isFalse,
      );
      expect(
        SettingsController.isWithinQuietHours(
            nowMinutes: 23 * 60 + 30,
            startMinutes: 22 * 60,
            endMinutes: 7 * 60),
        isTrue,
      );
      expect(
        SettingsController.isWithinQuietHours(
            nowMinutes: 6 * 60, startMinutes: 22 * 60, endMinutes: 7 * 60),
        isTrue,
      );
      expect(
        SettingsController.isWithinQuietHours(
            nowMinutes: 12 * 60, startMinutes: 22 * 60, endMinutes: 7 * 60),
        isFalse,
      );
    });
  });

  group('SettingsController', () {
    test('loads defaults and persists changes', () async {
      SharedPreferences.setMockInitialValues({});
      final service = await SettingsService.create();
      final controller = SettingsController(settingsService: service);

      expect(controller.alarmLeadSeconds, 30);
      expect(controller.preTaskVibration, isTrue);
      expect(controller.archivePolicy, ArchivePolicy.keepForever);
      expect(controller.use24hFormat, isFalse);

      await controller.setAlarmLeadSeconds(60);
      await controller.setUse24hFormat(true);
      await controller.setArchivePolicy(ArchivePolicy.afterWeek);
      await controller.setPreTaskVibration(false);

      final reloaded = SettingsController(
          settingsService: await SettingsService.create());
      expect(reloaded.alarmLeadSeconds, 60);
      expect(reloaded.use24hFormat, isTrue);
      expect(reloaded.archivePolicy, ArchivePolicy.afterWeek);
      expect(reloaded.preTaskVibration, isFalse);

      TimeFormatting.use24Hour = false;
    });

    test('24-hour toggle restyles rendered times globally', () {
      TimeFormatting.use24Hour = false;
      expect(TimeFormatting.minutesLabel(21 * 60 + 30), '9:30 PM');
      TimeFormatting.use24Hour = true;
      expect(TimeFormatting.minutesLabel(21 * 60 + 30), '21:30');
      TimeFormatting.use24Hour = false;
    });
  });

  group('Strict time-blocking validation', () {
    Task at(int id, int startMinutes, int endMinutes,
            {int delayMinutes = 0}) =>
        Task(
          id: id,
          title: 'Task $id',
          date: '2026-07-26',
          startMinutes: startMinutes,
          endMinutes: endMinutes,
          delayMinutes: delayMinutes,
        );

    test('detects an overlapping slot', () {
      final existing = [at(1, 9 * 60, 10 * 60)];
      expect(
        ScheduleValidator.findConflict(
            startMinutes: 9 * 60 + 30,
            endMinutes: 11 * 60,
            existing: existing)?.id,
        1,
      );
      expect(
        ScheduleValidator.findConflict(
            startMinutes: 8 * 60,
            endMinutes: 9 * 60 + 30,
            existing: existing)?.id,
        1,
      );
      expect(
        ScheduleValidator.findConflict(
            startMinutes: 8 * 60, endMinutes: 12 * 60, existing: existing)?.id,
        1,
      );
      expect(
        ScheduleValidator.findConflict(
            startMinutes: 9 * 60 + 10,
            endMinutes: 9 * 60 + 20,
            existing: existing)?.id,
        1,
      );
    });

    test('allows back-to-back tasks that merely touch', () {
      final existing = [at(1, 9 * 60, 10 * 60)];
      expect(
        ScheduleValidator.findConflict(
            startMinutes: 8 * 60, endMinutes: 9 * 60, existing: existing),
        isNull,
      );
      expect(
        ScheduleValidator.findConflict(
            startMinutes: 10 * 60, endMinutes: 11 * 60, existing: existing),
        isNull,
      );
    });

    test('counts overtime as occupied time', () {
      final existing = [at(1, 9 * 60, 10 * 60, delayMinutes: 30)];
      expect(
        ScheduleValidator.findConflict(
            startMinutes: 10 * 60 + 15,
            endMinutes: 11 * 60,
            existing: existing)?.id,
        1,
      );
    });

    test('never conflicts with the task being edited', () {
      final existing = [at(7, 9 * 60, 10 * 60)];
      expect(
        ScheduleValidator.findConflict(
          startMinutes: 9 * 60,
          endMinutes: 10 * 60,
          existing: existing,
          editingTaskId: 7,
        ),
        isNull,
      );
    });

    test('ignores tasks sitting in the Trash', () {
      final trashed = at(1, 9 * 60, 10 * 60)
          .copyWith(deletedAt: DateTime(2026, 7, 26).toIso8601String());
      expect(
        ScheduleValidator.findConflict(
            startMinutes: 9 * 60 + 30,
            endMinutes: 11 * 60,
            existing: [trashed]),
        isNull,
      );
    });
  });

  group('Alarm phase id scheme', () {
    test('a warning id never collides with any task id', () {
      for (final taskId in [1, 42, 999, 99999, 999999]) {
        final warningId = AlarmService.warningAlarmId(taskId);
        expect(warningId, isNot(taskId));
        expect(warningId, greaterThanOrEqualTo(
            AlarmService.warningAlarmIdOffset));
      }
    });
  });

  group('Alarm phase timing', () {
    final start = DateTime(2026, 7, 26, 9, 0);

    AlarmSchedule scheduleWith(Duration warningLead) =>
        AlarmSchedule.forStart(
          startAt: start,
          warningLead: warningLead,
          audioLead: AppConstants.audioLeadTime,
        );

    test('audio starts five seconds before the task, never after it', () {
      final schedule = scheduleWith(const Duration(seconds: 30));

      expect(schedule.audioAt, DateTime(2026, 7, 26, 8, 59, 55));
      expect(schedule.audioAt.isBefore(start), isTrue);
      expect(start.difference(schedule.audioAt), const Duration(seconds: 5));
    });

    test('vibration fires at the configured lead, ahead of the audio', () {
      final schedule = scheduleWith(const Duration(seconds: 30));

      expect(schedule.warnAt, DateTime(2026, 7, 26, 8, 59, 30));
      expect(schedule.warnAt!.isBefore(schedule.audioAt), isTrue);
      expect(start.difference(schedule.warnAt!), const Duration(seconds: 30));
    });

    test('a warning lead no longer than the audio lead is dropped', () {
      expect(scheduleWith(const Duration(seconds: 5)).warnAt, isNull);
      expect(scheduleWith(const Duration(seconds: 3)).warnAt, isNull);
      expect(scheduleWith(const Duration(seconds: 10)).warnAt, isNotNull);
    });

    test('phases arm independently inside the warning window', () {
      final schedule = scheduleWith(const Duration(seconds: 30));
      final now = start.subtract(const Duration(seconds: 20));

      expect(schedule.shouldArmWarning(now), isFalse);
      expect(schedule.shouldArmAudio(now), isTrue);
    });

    test('nothing is armed once the audio point has passed', () {
      final schedule = scheduleWith(const Duration(seconds: 30));
      final now = start.subtract(const Duration(seconds: 2));

      expect(schedule.shouldArmWarning(now), isFalse);
      expect(schedule.shouldArmAudio(now), isFalse);
    });
  });

  group('Alarm payload resolution', () {
    AlarmPreferences preferences({
      bool quietHours = true,
      int startMinutes = 22 * 60,
      int endMinutes = 7 * 60,
    }) =>
        AlarmPreferences(
          leadSeconds: 30,
          preTaskVibration: true,
          vibrationPattern: const [0, 200, 120, 200],
          quietHoursEnabled: quietHours,
          quietStartMinutes: startMinutes,
          quietEndMinutes: endMinutes,
        );

    test('quiet hours are judged at the instant the alarm will fire', () {
      final settings = preferences();

      expect(settings.isQuietAt(DateTime(2026, 7, 26, 23, 30)), isTrue);
      expect(settings.isQuietAt(DateTime(2026, 7, 26, 3, 0)), isTrue);
      expect(settings.isQuietAt(DateTime(2026, 7, 26, 12, 0)), isFalse);
    });

    test('quiet hours switched off never silence an alarm', () {
      expect(
        preferences(quietHours: false).isQuietAt(DateTime(2026, 7, 26, 23, 30)),
        isFalse,
      );
    });

    test('a request carries an absolute trigger instant to the platform', () {
      final triggerAt = DateTime(2026, 7, 26, 8, 59, 55);
      final request = AlarmRequest(
        id: 7,
        triggerAt: triggerAt,
        title: 'Starting now: Deep work',
        body: 'Begins at 9:00 AM. Time to begin.',
        soundUri: 'file:///data/tone.wav',
        vibrationPattern: const [0, 200],
      );

      final args = request.toArguments();
      expect(args['triggerAtMillis'], triggerAt.millisecondsSinceEpoch);
      expect(args['id'], 7);
      expect(args['playAudio'], isTrue);
      expect(args['soundUri'], 'file:///data/tone.wav');
      expect(args['vibrationPattern'], const [0, 200]);
    });
  });

  group('Custom alarm audio bookkeeping', () {
    late TaskRepository repository;

    setUp(() async {
      final dbDir = await databaseFactory.getDatabasesPath();
      await databaseFactory.deleteDatabase('$dbDir/advanced_todo.db');
      await DatabaseHelper.instance.resetForTesting();
      repository = TaskRepository();
    });

    Task soundTask(String title, String? uri, {AlarmSoundType? type}) => Task(
          title: title,
          date: '2026-07-26',
          startMinutes: 9 * 60,
          endMinutes: 10 * 60,
          alarmEnabled: true,
          alarmSoundType: type ??
              (uri == null ? AlarmSoundType.system : AlarmSoundType.custom),
          alarmSoundUri: uri,
          alarmSoundLabel: uri == null ? null : 'Tone',
        );

    test('clearAlarmSound resets the sound triple, which `??` cannot', () {
      final task = soundTask('Loud', '/audio/1756869123456_song.mp3');

      final cleared = task.copyWith(clearAlarmSound: true);
      expect(cleared.alarmSoundUri, isNull);
      expect(cleared.alarmSoundLabel, isNull);
      expect(cleared.alarmSoundType, AlarmSoundType.system);
      expect(cleared.title, 'Loud');
      expect(cleared.alarmEnabled, isTrue);

      expect(task.copyWith(alarmSoundUri: null).alarmSoundUri,
          '/audio/1756869123456_song.mp3');
    });

    test('trashed tasks still count as referencing their audio', () async {
      final live = await repository
          .insert(soundTask('Live', '/audio/1756869123456_a.mp3'));
      final trashed = await repository
          .insert(soundTask('Trashed', '/audio/1756869123456_b.mp3'));
      await repository.insert(soundTask('System sound', null));
      await repository.softDelete(trashed.id!);

      final referencing = await repository.findAllWithCustomSound();
      expect(
        referencing.map((task) => task.alarmSoundUri).toSet(),
        {'/audio/1756869123456_a.mp3', '/audio/1756869123456_b.mp3'},
      );
      expect(referencing.map((task) => task.id), contains(live.id));
    });

    test('deleting a stored file resets every task that used it', () async {
      const path = '/audio/1756869123456_shared.mp3';
      await repository.insert(soundTask('First', path));
      await repository.insert(soundTask('Second', path));
      final other = await repository
          .insert(soundTask('Other', '/audio/1756869123456_keep.mp3'));

      final cleared = await repository.clearCustomSound(path);
      expect(cleared, hasLength(2));
      expect(cleared.every((task) => task.alarmSoundUri == null), isTrue);

      final remaining = await repository.findAllWithCustomSound();
      expect(remaining.map((task) => task.id), [other.id]);

      final reread = await repository.findByDate('2026-07-26');
      final first = reread.firstWhere((task) => task.title == 'First');
      expect(first.alarmSoundUri, isNull);
      expect(first.alarmSoundLabel, isNull);
      expect(first.alarmSoundType, AlarmSoundType.system);
      expect(first.alarmEnabled, isTrue);
    });

    test('clearing an unreferenced path touches nothing', () async {
      await repository.insert(soundTask('Keep', '/audio/1756869123456_a.mp3'));
      expect(await repository.clearCustomSound('/audio/gone.mp3'), isEmpty);
      expect(await repository.findAllWithCustomSound(), hasLength(1));
    });
  });

  group('Audit regressions', () {
    test('Task uses value equality, so rebuilds do not churn timers', () {
      const a = Task(
        id: 1,
        title: 'Same',
        date: '2026-07-26',
        startMinutes: 540,
        endMinutes: 600,
      );
      const b = Task(
        id: 1,
        title: 'Same',
        date: '2026-07-26',
        startMinutes: 540,
        endMinutes: 600,
      );
      final different = b.copyWith(startMinutes: 541);

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(different)));
    });

    test('start and end instants use wall-clock components, not offsets',
        () {
      const task = Task(
        title: 'DST safe',
        date: '2026-03-29',
        startMinutes: 9 * 60,
        endMinutes: 10 * 60 + 30,
      );
      expect(task.startDateTime.hour, 9);
      expect(task.startDateTime.minute, 0);
      expect(task.endDateTime.hour, 10);
      expect(task.endDateTime.minute, 30);
    });

    test('overtime past midnight rolls the end into the next day', () {
      const task = Task(
        title: 'Runs long',
        date: '2026-07-26',
        startMinutes: 23 * 60,
        endMinutes: 23 * 60 + 30,
        delayMinutes: 45,
      );
      expect(task.endDateTime, DateTime(2026, 7, 27, 0, 15));
    });

    test('a midnight-crossing range is checked against the next day too',
        () {
      const nextDayEarly = Task(
        id: 9,
        title: 'Early bird',
        date: '2026-07-27',
        startMinutes: 30,
        endMinutes: 90,
      );
      expect(
        ScheduleValidator.findConflict(
          startMinutes: 23 * 60,
          endMinutes: 60,
          existing: const [],
          nextDayExisting: const [nextDayEarly],
        )?.id,
        9,
      );
      expect(
        ScheduleValidator.findConflict(
          startMinutes: 23 * 60,
          endMinutes: 30,
          existing: const [],
          nextDayExisting: const [nextDayEarly],
        ),
        isNull,
      );
    });
  });
}
