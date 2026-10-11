import 'dart:async';
import 'dart:io';

import 'package:arast_alarm/arast_alarm.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../controllers/settings_controller.dart';
import '../core/alarm_schedule.dart';
import '../core/constants.dart';
import '../core/time_formatting.dart';
import '../data/models/task.dart';
import '../data/repositories/task_repository.dart';
import 'settings_service.dart';

// no dart code runs when an alarm fires
class AlarmService {
  AlarmService({TaskRepository? repository})
      : _repository = repository ?? TaskRepository();

  final TaskRepository _repository;

  static String? _bundledToneUri;

  static Future<void> initialize() async {
    if (kIsWeb || !Platform.isAndroid) return;

    await Permission.notification.request();
    if (!await ArastAlarm.canScheduleExactAlarms()) {
      await ArastAlarm.requestExactAlarmPermission();
    }
    await _ensureBundledTone();
    await requestBackgroundExemption();
  }

  /// true when the os currently allows exact alarms
  static Future<bool> exactAlarmsGranted() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    return ArastAlarm.canScheduleExactAlarms();
  }

  /// ask once for the battery whitelist so the os stops killing background alarms
  static const _batteryPromptKey = 'alarm.battery_exemption_prompted';

  static Future<void> requestBackgroundExemption() async {
    if (kIsWeb || !Platform.isAndroid) return;
    if (await Permission.ignoreBatteryOptimizations.isGranted) return;
    final settings = await SettingsService.create();
    if (settings.loadBool(_batteryPromptKey, false)) return;
    await settings.saveBool(_batteryPromptKey, true);
    await Permission.ignoreBatteryOptimizations.request();
  }

  static const int warningAlarmIdOffset = 1000000;

  static int warningAlarmId(int taskId) => taskId + warningAlarmIdOffset;

  /// arms both alarms and returns false when the os refused the registration
  Future<bool> scheduleForTask(Task task,
      {AlarmPreferences? preferences}) async {
    if (kIsWeb || !Platform.isAndroid) return true;
    final id = task.id;
    if (id == null) return true;

    await cancelForTask(id);

    if (!task.alarmEnabled || task.isCompleted || task.isDeleted) return true;

    final settings = preferences ?? await AlarmPreferences.load();

    final now = DateTime.now();
    final schedule = AlarmSchedule.forStart(
      startAt: task.startDateTime,
      warningLead: Duration(seconds: settings.leadSeconds),
      audioLead: AppConstants.audioLeadTime,
    );

    final startLabel = TimeFormatting.minutesLabel(task.startMinutes);

    var armed = true;
    if (schedule.shouldArmWarning(now)) {
      armed = await ArastAlarm.schedule(
            AlarmRequest(
              id: warningAlarmId(id),
              triggerAt: schedule.warnAt!,
              title: 'Starting soon: ${task.title}',
              body: 'Begins at $startLabel. Get ready.',
              playAudio: false,
              vibrate: settings.preTaskVibration,
              vibrationPattern: settings.vibrationPattern,
            ),
          ) &&
          armed;
    }

    if (schedule.shouldArmAudio(now)) {
      // judge quiet hours at fire time not at schedule time
      final quiet = settings.isQuietAt(schedule.audioAt);
      armed = await ArastAlarm.schedule(
            AlarmRequest(
              id: id,
              triggerAt: schedule.audioAt,
              title: 'Starting now: ${task.title}',
              body: quiet
                  ? 'Begins at $startLabel. Delivered quietly (quiet hours).'
                  : 'Begins at $startLabel. Time to begin.',
              soundUri: quiet ? null : await _resolveSoundUri(task),
              playAudio: !quiet,
              vibrate: quiet || settings.preTaskVibration,
              vibrationPattern: settings.vibrationPattern,
              maxDuration: AppConstants.alarmPlaybackTimeout,
            ),
          ) &&
          armed;
    }

    if (!armed) {
      debugPrint(
        'AlarmService: the system refused to arm the alarm for task $id '
        '("${task.title}"). Exact-alarm permission is the usual cause; '
        'check Settings > Apps > Special app access > Alarms & reminders.',
      );
    }
    return armed;
  }

  Future<void> cancelForTask(int taskId) async {
    if (kIsWeb || !Platform.isAndroid) return;
    await ArastAlarm.cancel(taskId);
    await ArastAlarm.cancel(warningAlarmId(taskId));
  }

  Future<void> rescheduleAllPending() async {
    if (kIsWeb || !Platform.isAndroid) return;
    final today = TimeFormatting.dbDateKey(DateTime.now());
    final tasks = await _repository.findUpcomingWithAlarms(today);
    if (tasks.isEmpty) return;

    final preferences = await AlarmPreferences.load();
    var refused = 0;
    for (final task in tasks) {
      if (!await scheduleForTask(task, preferences: preferences)) refused++;
    }
    if (refused > 0) {
      debugPrint(
        'AlarmService: the system refused $refused of ${tasks.length} '
        'alarms while rescheduling.',
      );
    }
  }

  static Future<String?> _resolveSoundUri(Task task) async {
    final uri = task.alarmSoundUri;
    if (uri != null && uri.isNotEmpty) {
      if (task.alarmSoundType == AlarmSoundType.custom) {
        if (File(uri).existsSync()) return Uri.file(uri).toString();
      } else {
        return uri;
      }
    }
    return _ensureBundledTone();
  }

  static Future<String?> _ensureBundledTone() async {
    final cached = _bundledToneUri;
    if (cached != null) return cached;

    try {
      final directory = await getApplicationSupportDirectory();
      final file = File(p.join(directory.path, 'alarm_tone.wav'));
      if (!file.existsSync() || file.lengthSync() == 0) {
        final data = await rootBundle.load(
          'assets/${AppConstants.bundledAlarmAsset}',
        );
        await file.writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          flush: true,
        );
      }
      return _bundledToneUri = Uri.file(file.path).toString();
    } catch (error) {
      debugPrint('Bundled alarm tone unavailable: $error');
      return null;
    }
  }
}

class AlarmPreferences {
  const AlarmPreferences({
    required this.leadSeconds,
    required this.preTaskVibration,
    required this.vibrationPattern,
    required this.quietHoursEnabled,
    required this.quietStartMinutes,
    required this.quietEndMinutes,
  });

  final int leadSeconds;
  final bool preTaskVibration;
  final List<int> vibrationPattern;
  final bool quietHoursEnabled;
  final int quietStartMinutes;
  final int quietEndMinutes;

  static Future<AlarmPreferences> load() async {
    final settings = await SettingsService.create();
    final styleName = settings.loadString(
        SettingsController.keyVibrationStyle, VibrationStyle.pulse.name);
    final style =
        VibrationStyle.values.asNameMap()[styleName] ?? VibrationStyle.pulse;

    return AlarmPreferences(
      leadSeconds: settings.loadInt(
        SettingsController.keyAlarmLeadSeconds,
        AppConstants.alarmLeadTime.inSeconds,
      ),
      preTaskVibration:
          settings.loadBool(SettingsController.keyPreTaskVibration, true),
      vibrationPattern: style.pattern,
      quietHoursEnabled:
          settings.loadBool(SettingsController.keyQuietHoursEnabled, false),
      quietStartMinutes:
          settings.loadInt(SettingsController.keyQuietStartMinutes, 22 * 60),
      quietEndMinutes:
          settings.loadInt(SettingsController.keyQuietEndMinutes, 7 * 60),
    );
  }

  bool isQuietAt(DateTime instant) {
    if (!quietHoursEnabled) return false;
    return SettingsController.isWithinQuietHours(
      nowMinutes: instant.hour * 60 + instant.minute,
      startMinutes: quietStartMinutes,
      endMinutes: quietEndMinutes,
    );
  }
}
