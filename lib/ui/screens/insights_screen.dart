import 'package:flutter/material.dart';

import '../../core/app_palette.dart';
import '../../core/constants.dart';
import '../../core/time_formatting.dart';
import '../../data/models/task.dart';
import '../../data/models/time_section.dart';
import '../../data/repositories/task_repository.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/frosted_surface.dart';

class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  static const int _windowDays = 7;

  late final Future<_InsightsData> _dataFuture;

  @override
  void initState() {
    super.initState();
    _dataFuture = _load();
  }

  Future<_InsightsData> _load() async {
    final today = DateTime.now();
    // step the calendar itself so daylight saving never skips a day
    final start = DateTime(today.year, today.month, today.day - (_windowDays - 1));
    final tasks = await TaskRepository().findBetweenDates(
      TimeFormatting.dbDateKey(start),
      TimeFormatting.dbDateKey(today),
    );
    return _InsightsData.compute(tasks, start, _windowDays);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return AppScaffold(
      appBar: AppBar(title: const Text('Insights')),
      body: FutureBuilder<_InsightsData>(
        future: _dataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data;
          if (data == null || data.totalPlanned == 0) {
            return _EmptyInsights(palette: palette);
          }
          return ListView(
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + kToolbarHeight + 8,
              left: 16,
              right: 16,
              bottom: 32,
            ),
            children: [
              Row(
                children: [
                  Expanded(
                    child: _StatTile(
                      palette: palette,
                      icon: Icons.task_alt,
                      value: '${(data.completionRate * 100).round()}%',
                      label: 'completed of ${data.totalPlanned} '
                          'planned this week',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatTile(
                      palette: palette,
                      icon: Icons.local_fire_department_outlined,
                      value: '${data.streakDays}',
                      label: data.streakDays == 1
                          ? 'day streak of finishing tasks'
                          : 'days streak of finishing tasks',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _InsightCard(
                palette: palette,
                title: 'Last 7 days',
                subtitle: 'Tasks completed against tasks planned, per day',
                child: Column(
                  children: [
                    SizedBox(
                      height: 130,
                      child: CustomPaint(
                        size: const Size(double.infinity, 130),
                        painter: _DailyBarsPainter(
                          days: data.days,
                          palette: palette,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _ChartLegend(palette: palette),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _InsightCard(
                palette: palette,
                title: 'By time of day',
                subtitle: 'Where your plans actually get done',
                child: Column(
                  children: [
                    for (final block in TimeSection.values) ...[
                      _BlockRow(
                        palette: palette,
                        block: block,
                        stat: data.blocks[block] ?? const _BlockNumbers(),
                      ),
                      if (block != TimeSection.values.last)
                        const SizedBox(height: 14),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _InsightCard(
                palette: palette,
                title: 'Overtime',
                subtitle: 'Extra minutes added with the delay clock',
                child: Row(
                  children: [
                    Icon(Icons.more_time, color: palette.support, size: 30),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        data.overtimeMinutes == 0
                            ? 'No overtime this week. Your estimates '
                                'are holding up well.'
                            : '${data.overtimeMinutes} extra minutes this '
                                'week. Consider planning slightly longer '
                                'slots for similar tasks.',
                        style: TextStyle(
                          color: palette.textSecondary,
                          fontSize: 13.5,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _InsightsData {
  const _InsightsData({
    required this.totalPlanned,
    required this.totalCompleted,
    required this.days,
    required this.blocks,
    required this.overtimeMinutes,
    required this.streakDays,
  });

  final int totalPlanned;
  final int totalCompleted;

  final List<_DayNumbers> days;

  final Map<TimeSection, _BlockNumbers> blocks;
  final int overtimeMinutes;

  final int streakDays;

  double get completionRate =>
      totalPlanned == 0 ? 0 : totalCompleted / totalPlanned;

  factory _InsightsData.compute(
    List<Task> tasks,
    DateTime windowStart,
    int windowDays,
  ) {
    final byDate = <String, List<Task>>{};
    for (final task in tasks) {
      byDate.putIfAbsent(task.date, () => []).add(task);
    }

    final days = <_DayNumbers>[];
    for (var i = 0; i < windowDays; i++) {
      final date = DateTime(windowStart.year, windowStart.month, windowStart.day + i);
      final dayTasks = byDate[TimeFormatting.dbDateKey(date)] ?? const <Task>[];
      days.add(_DayNumbers(
        label: TimeFormatting.weekdayLabel(date),
        planned: dayTasks.length,
        completed: dayTasks.where((t) => t.isCompleted).length,
      ));
    }

    final blocks = <TimeSection, _BlockNumbers>{};
    var overtime = 0;
    for (final task in tasks) {
      final existing = blocks[task.section] ?? const _BlockNumbers();
      blocks[task.section] = _BlockNumbers(
        planned: existing.planned + 1,
        completed: existing.completed + (task.isCompleted ? 1 : 0),
      );
      overtime += task.delayMinutes;
    }

    var streak = 0;
    for (var i = days.length - 1; i >= 0; i--) {
      if (days[i].completed > 0) {
        streak++;
      } else {
        break;
      }
    }

    return _InsightsData(
      totalPlanned: tasks.length,
      totalCompleted: tasks.where((t) => t.isCompleted).length,
      days: days,
      blocks: blocks,
      overtimeMinutes: overtime,
      streakDays: streak,
    );
  }
}

class _DayNumbers {
  const _DayNumbers({
    required this.label,
    required this.planned,
    required this.completed,
  });

  final String label;
  final int planned;
  final int completed;
}

class _BlockNumbers {
  const _BlockNumbers({this.planned = 0, this.completed = 0});

  final int planned;
  final int completed;

  double get rate => planned == 0 ? 0 : completed / planned;
}

class _DailyBarsPainter extends CustomPainter {
  _DailyBarsPainter({required this.days, required this.palette});

  final List<_DayNumbers> days;
  final AppPalette palette;

  static const double _labelHeight = 18;

  @override
  void paint(Canvas canvas, Size size) {
    if (days.isEmpty) return;

    final chartHeight = size.height - _labelHeight;
    final maxCount = days
        .map((d) => d.planned)
        .fold<int>(1, (max, v) => v > max ? v : max);

    final slot = size.width / days.length;
    final barWidth = (slot * 0.42).clamp(6.0, 26.0);

    for (var i = 0; i < days.length; i++) {
      final day = days[i];
      final centerX = slot * i + slot / 2;

      double heightFor(int count) =>
          count == 0 ? 0 : (count / maxCount) * (chartHeight - 14) + 6;

      _paintBar(
        canvas,
        centerX,
        chartHeight,
        heightFor(day.planned),
        barWidth,
        palette.support.withValues(alpha: 0.18),
      );
      _paintBar(
        canvas,
        centerX,
        chartHeight,
        heightFor(day.completed),
        barWidth - 6,
        palette.accent,
      );

      final labelPainter = TextPainter(
        text: TextSpan(
          text: day.label,
          style: TextStyle(
            color: palette.textFaint,
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      labelPainter.paint(
        canvas,
        Offset(centerX - labelPainter.width / 2, chartHeight + 4),
      );
    }
  }

  void _paintBar(Canvas canvas, double centerX, double baseline,
      double height, double width, Color color) {
    if (height <= 0) return;
    final rect = RRect.fromRectAndCorners(
      Rect.fromLTWH(centerX - width / 2, baseline - height, width, height),
      topLeft: const Radius.circular(4),
      topRight: const Radius.circular(4),
    );
    canvas.drawRRect(rect, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_DailyBarsPainter oldDelegate) {
    return oldDelegate.days != days || oldDelegate.palette != palette;
  }
}

class _ChartLegend extends StatelessWidget {
  const _ChartLegend({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    Widget entry(Color swatch, String label) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: swatch,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(color: palette.textSecondary, fontSize: 11.5),
          ),
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        entry(palette.accent, 'Completed'),
        const SizedBox(width: 18),
        entry(palette.support.withValues(alpha: 0.25), 'Planned'),
      ],
    );
  }
}

class _BlockRow extends StatelessWidget {
  const _BlockRow({
    required this.palette,
    required this.block,
    required this.stat,
  });

  final AppPalette palette;
  final TimeSection block;
  final _BlockNumbers stat;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    block.title,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    stat.planned == 0
                        ? 'No tasks yet'
                        : '${stat.completed} of ${stat.planned} done',
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  height: 8,
                  child: LinearProgressIndicator(
                    value: stat.rate,
                    backgroundColor: palette.support.withValues(alpha: 0.15),
                    valueColor:
                        AlwaysStoppedAnimation<Color>(palette.accent),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.palette,
    required this.icon,
    required this.value,
    required this.label,
  });

  final AppPalette palette;
  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return FrostedSurface(
      color: palette.surface,
      borderRadius: BorderRadius.circular(AppConstants.cornerRadius),
      border: Border.all(color: palette.outline),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: palette.support, size: 20),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 26,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 11.5,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({
    required this.palette,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final AppPalette palette;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FrostedSurface(
      color: palette.surface,
      borderRadius: BorderRadius.circular(AppConstants.cornerRadius),
      border: Border.all(color: palette.outline),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: TextStyle(color: palette.textSecondary, fontSize: 12.5),
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class _EmptyInsights extends StatelessWidget {
  const _EmptyInsights({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'No data yet',
              style: TextStyle(
                color: palette.onBackdrop,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Plan and complete a few tasks and your '
              'time-management picture will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.onBackdropMuted,
                fontSize: 13.5,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
