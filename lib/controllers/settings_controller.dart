import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/time_formatting.dart';
import '../services/settings_service.dart';

enum VibrationStyle {
  shortBuzz('Short'),
  longBuzz('Long'),
  pulse('Pulse');

  const VibrationStyle(this.label);

  final String label;

  List<int> get pattern => switch (this) {
        VibrationStyle.shortBuzz => const [0, 200],
        VibrationStyle.longBuzz => const [0, 800],
        VibrationStyle.pulse => const [0, 200, 120, 200, 120, 200],
      };
}

enum ArchivePolicy {
  keepForever('Keep completed tasks'),
  immediately('Archive immediately'),
  endOfDay('Archive at end of day'),
  afterWeek('Archive after a week');

  const ArchivePolicy(this.label);

  final String label;
}

class SettingsController extends ChangeNotifier {
  SettingsController({required SettingsService settingsService})
      : _settings = settingsService {
    _load();
  }

  final SettingsService _settings;

  static const MethodChannel _deviceChannel =
      MethodChannel('com.morphinealonely.advanced_todo_list/device');

  static const String keyAlarmLeadSeconds = 'defaults.alarm_lead_seconds';
  static const String keyAutoRollover = 'defaults.auto_rollover';
  static const String keyQuietHoursEnabled = 'notify.quiet_enabled';
  static const String keyQuietStartMinutes = 'notify.quiet_start';
  static const String keyQuietEndMinutes = 'notify.quiet_end';
  static const String keyVibrationStyle = 'notify.vibration_style';
  static const String keyPreTaskVibration = 'notify.pre_task_vibration';
  static const String keyAppLock = 'security.app_lock';
  static const String keySecureScreen = 'security.secure_screen';
  static const String keyDeepFocus = 'focus.deep_focus';
  static const String keySwipeSwapped = 'gestures.swipe_swapped';
  static const String keyTaskFontScale = 'display.task_font_scale';
  static const String keyUse24hFormat = 'display.use_24h';
  static const String keyArchivePolicy = 'cleanup.archive_policy';

  int _alarmLeadSeconds = 30;
  bool _autoRollover = false;
  bool _quietHoursEnabled = false;
  int _quietStartMinutes = 22 * 60;
  int _quietEndMinutes = 7 * 60;
  VibrationStyle _vibrationStyle = VibrationStyle.pulse;
  bool _preTaskVibration = true;
  bool _appLockEnabled = false;
  bool _secureScreenEnabled = false;
  bool _deepFocusEnabled = false;
  bool _swipeSwapped = false;
  double _taskFontScale = 1.0;
  bool _use24hFormat = false;
  ArchivePolicy _archivePolicy = ArchivePolicy.keepForever;

  int get alarmLeadSeconds => _alarmLeadSeconds;
  bool get autoRollover => _autoRollover;
  bool get quietHoursEnabled => _quietHoursEnabled;
  int get quietStartMinutes => _quietStartMinutes;
  int get quietEndMinutes => _quietEndMinutes;
  VibrationStyle get vibrationStyle => _vibrationStyle;

  bool get preTaskVibration => _preTaskVibration;
  bool get appLockEnabled => _appLockEnabled;
  bool get secureScreenEnabled => _secureScreenEnabled;
  bool get deepFocusEnabled => _deepFocusEnabled;
  bool get swipeSwapped => _swipeSwapped;
  double get taskFontScale => _taskFontScale;
  bool get use24hFormat => _use24hFormat;
  ArchivePolicy get archivePolicy => _archivePolicy;

  void _load() {
    _alarmLeadSeconds = _settings.loadInt(keyAlarmLeadSeconds, 30);
    _autoRollover = _settings.loadBool(keyAutoRollover, false);
    _quietHoursEnabled = _settings.loadBool(keyQuietHoursEnabled, false);
    _quietStartMinutes = _settings.loadInt(keyQuietStartMinutes, 22 * 60);
    _quietEndMinutes = _settings.loadInt(keyQuietEndMinutes, 7 * 60);
    _vibrationStyle = VibrationStyle.values.asNameMap()[
            _settings.loadString(keyVibrationStyle, VibrationStyle.pulse.name)] ??
        VibrationStyle.pulse;
    _preTaskVibration = _settings.loadBool(keyPreTaskVibration, true);
    _appLockEnabled = _settings.loadBool(keyAppLock, false);
    _secureScreenEnabled = _settings.loadBool(keySecureScreen, false);
    _deepFocusEnabled = _settings.loadBool(keyDeepFocus, false);
    _swipeSwapped = _settings.loadBool(keySwipeSwapped, false);
    _taskFontScale = _settings.loadDouble(keyTaskFontScale, 1.0);
    _use24hFormat = _settings.loadBool(keyUse24hFormat, false);
    _archivePolicy = ArchivePolicy.values.asNameMap()[_settings.loadString(
            keyArchivePolicy, ArchivePolicy.keepForever.name)] ??
        ArchivePolicy.keepForever;

    TimeFormatting.use24Hour = _use24hFormat;
    _applySecureScreen();
  }

  Future<void> Function()? onAlarmSettingsChanged;

  void _alarmSettingsChanged() {
    final callback = onAlarmSettingsChanged;
    if (callback != null) unawaited(callback());
  }

  Future<void> setAlarmLeadSeconds(int seconds) async {
    _alarmLeadSeconds = seconds;
    notifyListeners();
    await _settings.saveInt(keyAlarmLeadSeconds, seconds);
    _alarmSettingsChanged();
  }

  Future<void> setAutoRollover(bool enabled) async {
    _autoRollover = enabled;
    notifyListeners();
    await _settings.saveBool(keyAutoRollover, enabled);
  }

  Future<void> setQuietHoursEnabled(bool enabled) async {
    _quietHoursEnabled = enabled;
    notifyListeners();
    await _settings.saveBool(keyQuietHoursEnabled, enabled);
    _alarmSettingsChanged();
  }

  Future<void> setQuietStartMinutes(int minutes) async {
    _quietStartMinutes = minutes;
    notifyListeners();
    await _settings.saveInt(keyQuietStartMinutes, minutes);
    _alarmSettingsChanged();
  }

  Future<void> setQuietEndMinutes(int minutes) async {
    _quietEndMinutes = minutes;
    notifyListeners();
    await _settings.saveInt(keyQuietEndMinutes, minutes);
    _alarmSettingsChanged();
  }

  Future<void> setVibrationStyle(VibrationStyle style) async {
    _vibrationStyle = style;
    notifyListeners();
    await _settings.saveString(keyVibrationStyle, style.name);
    _alarmSettingsChanged();
  }

  Future<void> setPreTaskVibration(bool enabled) async {
    _preTaskVibration = enabled;
    notifyListeners();
    await _settings.saveBool(keyPreTaskVibration, enabled);
    _alarmSettingsChanged();
  }

  Future<void> setAppLockEnabled(bool enabled) async {
    _appLockEnabled = enabled;
    notifyListeners();
    await _settings.saveBool(keyAppLock, enabled);
  }

  Future<void> setSecureScreenEnabled(bool enabled) async {
    _secureScreenEnabled = enabled;
    notifyListeners();
    await _settings.saveBool(keySecureScreen, enabled);
    await _applySecureScreen();
  }

  Future<void> setDeepFocusEnabled(bool enabled) async {
    _deepFocusEnabled = enabled;
    notifyListeners();
    await _settings.saveBool(keyDeepFocus, enabled);
  }

  Future<void> setSwipeSwapped(bool swapped) async {
    _swipeSwapped = swapped;
    notifyListeners();
    await _settings.saveBool(keySwipeSwapped, swapped);
  }

  Future<void> setTaskFontScale(double scale) async {
    _taskFontScale = scale;
    notifyListeners();
    await _settings.saveDouble(keyTaskFontScale, scale);
  }

  Future<void> setUse24hFormat(bool use24h) async {
    _use24hFormat = use24h;
    TimeFormatting.use24Hour = use24h;
    notifyListeners();
    await _settings.saveBool(keyUse24hFormat, use24h);
  }

  Future<void> setArchivePolicy(ArchivePolicy policy) async {
    _archivePolicy = policy;
    notifyListeners();
    await _settings.saveString(keyArchivePolicy, policy.name);
  }

  static bool isWithinQuietHours({
    required int nowMinutes,
    required int startMinutes,
    required int endMinutes,
  }) {
    if (startMinutes == endMinutes) return false;
    if (startMinutes < endMinutes) {
      return nowMinutes >= startMinutes && nowMinutes < endMinutes;
    }
    return nowMinutes >= startMinutes || nowMinutes < endMinutes;
  }

  Future<void> _applySecureScreen() async {
    try {
      await _deviceChannel.invokeMethod<void>(
        'setSecureScreen',
        {'enabled': _secureScreenEnabled},
      );
    } on PlatformException {
      // best effort
    } on MissingPluginException {
      // best effort
    }
  }
}
