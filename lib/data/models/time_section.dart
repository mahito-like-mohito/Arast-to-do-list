import 'package:flutter/material.dart';

enum TimeSection {
  morning(
    title: 'Energetic Start',
    subtitle: 'Make the most of your fresh morning energy',
    icon: Icons.wb_sunny_outlined,
    startMinute: 0,
    endMinute: 12 * 60 - 1,
  ),
  noon(
    title: 'Steady Momentum',
    subtitle: 'Keep the day flowing, one task at a time',
    icon: Icons.light_mode_outlined,
    startMinute: 12 * 60,
    endMinute: 17 * 60 - 1,
  ),
  night(
    title: 'Peaceful Rest',
    subtitle: 'Wind down and wrap up the day gently',
    icon: Icons.dark_mode_outlined,
    startMinute: 17 * 60,
    endMinute: 24 * 60 - 1,
  );

  const TimeSection({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.startMinute,
    required this.endMinute,
  });

  final String title;

  final String subtitle;

  final IconData icon;

  final int startMinute;

  final int endMinute;

  static TimeSection fromStartMinute(int minute) {
    for (final section in TimeSection.values) {
      if (minute >= section.startMinute && minute <= section.endMinute) {
        return section;
      }
    }
    return TimeSection.night;
  }
}
