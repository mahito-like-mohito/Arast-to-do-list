import 'dart:async';

abstract final class ExternalPicker {
  static int _depth = 0;
  static DateTime? _endedAt;

  // a pause can land after the picker already returned
  static const Duration _tail = Duration(seconds: 6);

  static bool get isActive {
    if (_depth > 0) return true;
    final endedAt = _endedAt;
    if (endedAt == null) return false;
    return DateTime.now().difference(endedAt) < _tail;
  }

  static Future<T> run<T>(Future<T> Function() action) async {
    _depth++;
    try {
      return await action();
    } finally {
      // always count down so a throw never locks the app
      _depth--;
      if (_depth < 0) _depth = 0;
      if (_depth == 0) _endedAt = DateTime.now();
    }
  }

  static void noteResumed() {
    if (_depth == 0) _endedAt = null;
  }

  static void resetForTesting() {
    _depth = 0;
    _endedAt = null;
  }
}
