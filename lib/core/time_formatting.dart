import 'package:intl/intl.dart';

abstract final class TimeFormatting {
  static final DateFormat _time12Format = DateFormat('h:mm a');
  static final DateFormat _time24Format = DateFormat('HH:mm');
  static final DateFormat _dateFormat = DateFormat('EEE, MMM d');
  static final DateFormat _dbDateFormat = DateFormat('yyyy-MM-dd');
  static final DateFormat _weekdayFormat = DateFormat('E');

  static bool use24Hour = false;

  static String dbDateKey(DateTime date) => _dbDateFormat.format(date);

  static String weekdayLabel(DateTime date) => _weekdayFormat.format(date);

  static String minutesLabel(int minutesSinceMidnight) {
    final hour = minutesSinceMidnight ~/ 60;
    final minute = minutesSinceMidnight % 60;
    final time = DateTime(2000, 1, 1, hour, minute);
    return (use24Hour ? _time24Format : _time12Format).format(time);
  }

  static String rangeLabel(int startMinutes, int endMinutes) {
    return '${minutesLabel(startMinutes)} - ${minutesLabel(endMinutes)}';
  }

  static String dateLabel(DateTime date) => _dateFormat.format(date);

  static String durationLabel(Duration duration) {
    final total = duration.isNegative ? -duration : duration;
    final hours = total.inHours;
    final minutes = total.inMinutes % 60;
    final seconds = total.inSeconds % 60;

    if (hours > 0) {
      return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
    }
    if (minutes > 0) {
      return '${minutes}m';
    }
    return '${seconds}s';
  }
}
