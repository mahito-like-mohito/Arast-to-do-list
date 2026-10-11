import 'package:flutter/services.dart';

abstract final class ArastHaptics {
  static const MethodChannel _channel =
      MethodChannel('com.morphinealonely.arast_haptics/vibrate');

  static Future<bool> vibrate(List<int> pattern) async {
    if (pattern.isEmpty) return false;
    return await _invoke<bool>('vibrate', {'pattern': pattern}) ?? false;
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
