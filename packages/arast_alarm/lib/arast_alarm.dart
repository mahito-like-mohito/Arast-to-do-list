import 'package:flutter/services.dart';

class AlarmRequest {
  const AlarmRequest({
    required this.id,
    required this.triggerAt,
    required this.title,
    required this.body,
    this.soundUri,
    this.playAudio = true,
    this.vibrate = false,
    this.vibrationPattern = const [],
    this.maxDuration = const Duration(minutes: 2),
  });

  final int id;

  final DateTime triggerAt;
  final String title;
  final String body;

  final String? soundUri;

  final bool playAudio;
  final bool vibrate;

  final List<int> vibrationPattern;

  final Duration maxDuration;

  Map<String, Object?> toArguments() => {
        'id': id,
        'triggerAtMillis': triggerAt.millisecondsSinceEpoch,
        'title': title,
        'body': body,
        'soundUri': soundUri,
        'playAudio': playAudio,
        'vibrate': vibrate,
        'vibrationPattern': vibrationPattern,
        'maxDurationMillis': maxDuration.inMilliseconds,
      };
}

abstract final class ArastAlarm {
  static const MethodChannel _channel =
      MethodChannel('com.morphinealonely.arast_alarm/scheduler');

  static Future<bool> schedule(AlarmRequest request) async {
    return await _invoke<bool>('schedule', request.toArguments()) ?? false;
  }

  static Future<void> cancel(int id) => _invoke<void>('cancel', {'id': id});

  static Future<bool> canScheduleExactAlarms() async {
    return await _invoke<bool>('canScheduleExactAlarms') ?? false;
  }

  static Future<bool> requestExactAlarmPermission() async {
    return await _invoke<bool>('requestExactAlarmPermission') ?? false;
  }

  static Future<T?> _invoke<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
