import 'package:flutter/material.dart';

import 'app_palette.dart';

abstract final class AppConstants {
  static const Color defaultAccentColor = AppPalette.lightBlue;

  static const Duration longPressDuration = Duration(seconds: 3);

  static const Duration remainingOverlayDuration = Duration(seconds: 4);

  static const Duration alarmLeadTime = Duration(seconds: 30);

  static const Duration audioLeadTime = Duration(seconds: 5);

  static const String bundledAlarmAsset = 'audio/alarm_tone.wav';

  static const Duration alarmPlaybackTimeout = Duration(minutes: 2);

  static const double cornerRadius = 18.0;

  static const double timePickerSize = 280.0;

  static const double delayClockSize = 220.0;

  static const double colorWheelSize = 240.0;

  static const String prefKeyAccentColor = 'appearance.accent_color';
  static const String prefKeyBackgroundImage = 'appearance.background_image';
  static const String prefKeyBackgroundColor = 'appearance.background_color';

  static const Duration undoGracePeriod = Duration(seconds: 5);

  static const Duration trashRetention = Duration(days: 30);
}
