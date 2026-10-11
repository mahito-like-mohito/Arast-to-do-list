import 'package:flutter/services.dart';

class SystemRingtone {
  const SystemRingtone({required this.title, required this.uri});

  final String title;

  final String uri;
}

class RingtoneService {
  static const MethodChannel _channel =
      MethodChannel('com.morphinealonely.advanced_todo_list/ringtones');

  // setting a callback starts listening
  set onPreviewComplete(void Function(String uri)? callback) {
    _onPreviewComplete = callback;
    if (callback != null) _ensureListening();
  }

  void Function(String uri)? _onPreviewComplete;

  bool _listening = false;

  void _ensureListening() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onPreviewComplete') {
        final uri = call.arguments as String?;
        if (uri != null) _onPreviewComplete?.call(uri);
      }
      return null;
    });
  }

  void dispose() {
    _onPreviewComplete = null;
    if (_listening) {
      _channel.setMethodCallHandler(null);
      _listening = false;
    }
  }

  Future<List<SystemRingtone>> getSystemRingtones() async {
    try {
      final result =
          await _channel.invokeListMethod<Map<Object?, Object?>>('list');
      if (result == null) return const [];
      return result
          .map((entry) => SystemRingtone(
                title: entry['title'] as String? ?? 'Unknown ringtone',
                uri: entry['uri'] as String? ?? '',
              ))
          .where((ringtone) => ringtone.uri.isNotEmpty)
          .toList();
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  Future<void> play(String uri) async {
    try {
      await _channel.invokeMethod<void>('play', {'uri': uri});
    } on PlatformException {
      // best effort
    } on MissingPluginException {
      // best effort
    }
  }

  Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } on PlatformException {
      // best effort
    } on MissingPluginException {
      // best effort
    }
  }
}
