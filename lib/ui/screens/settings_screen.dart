import 'dart:io';

import 'package:arast_haptics/arast_haptics.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/settings_controller.dart';
import '../../controllers/task_list_controller.dart';
import '../../core/app_palette.dart';
import '../../core/constants.dart';
import '../../core/time_formatting.dart';
import '../../data/models/task.dart';
import '../../data/repositories/task_repository.dart';
import '../../services/alarm_service.dart';
import '../../services/app_lock_service.dart';
import '../../services/file_storage_service.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/appearance_sheet.dart';
import '../widgets/frosted_surface.dart';
import 'insights_screen.dart';
import 'trash_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final settings = context.watch<SettingsController>();

    return AppScaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + kToolbarHeight + 8,
          left: 16,
          right: 16,
          bottom: 32,
        ),
        children: [
          _Section(
            palette: palette,
            icon: Icons.tune,
            title: 'Task Defaults',
            children: [
              _ChoiceTile<int>(
                palette: palette,
                icon: Icons.alarm,
                title: 'Early warning time',
                subtitle: 'How long before a task the card pulses and '
                    'the phone vibrates; the alarm itself sounds five '
                    'seconds before the start time',
                value: settings.alarmLeadSeconds,
                options: const {
                  10: '10 seconds',
                  30: '30 seconds',
                  45: '45 seconds',
                  60: '60 seconds',
                },
                onChanged: settings.setAlarmLeadSeconds,
              ),
              _ToggleTile(
                palette: palette,
                icon: Icons.redo,
                title: 'Auto-rollover',
                subtitle: 'Move unfinished tasks into the next '
                    'morning automatically',
                value: settings.autoRollover,
                onChanged: settings.setAutoRollover,
              ),
            ],
          ),
          _Section(
            palette: palette,
            icon: Icons.notifications_outlined,
            title: 'Notifications and Sounds',
            children: [
              _ToggleTile(
                palette: palette,
                icon: Icons.vibration,
                title: 'Pre-task vibration',
                subtitle: 'Buzz ${settings.alarmLeadSeconds} seconds '
                    'before a task starts; the alarm still sounds either '
                    'way',
                value: settings.preTaskVibration,
                onChanged: (enabled) async {
                  await settings.setPreTaskVibration(enabled);
                  if (enabled) {
                    await ArastHaptics.vibrate(settings.vibrationStyle.pattern);
                  }
                },
              ),
              if (settings.preTaskVibration || settings.quietHoursEnabled)
                _ChoiceTile<VibrationStyle>(
                  palette: palette,
                  icon: Icons.graphic_eq,
                  title: 'Vibration pattern',
                  subtitle: 'Used for the pre-task buzz and while alarms '
                      'are silenced',
                  value: settings.vibrationStyle,
                  options: {
                    for (final style in VibrationStyle.values)
                      style: style.label,
                  },
                  onChanged: (style) async {
                    await settings.setVibrationStyle(style);
                    await ArastHaptics.vibrate(style.pattern);
                  },
                ),
              _ToggleTile(
                palette: palette,
                icon: Icons.bedtime_outlined,
                title: 'Quiet hours',
                subtitle: 'Silence alarm audio in a nightly window; '
                    'deliver vibrating notifications instead',
                value: settings.quietHoursEnabled,
                onChanged: settings.setQuietHoursEnabled,
              ),
              if (settings.quietHoursEnabled) ...[
                _TimeTile(
                  palette: palette,
                  icon: Icons.dark_mode_outlined,
                  title: 'Quiet from',
                  minutes: settings.quietStartMinutes,
                  onChanged: settings.setQuietStartMinutes,
                ),
                _TimeTile(
                  palette: palette,
                  icon: Icons.light_mode_outlined,
                  title: 'Quiet until',
                  minutes: settings.quietEndMinutes,
                  onChanged: settings.setQuietEndMinutes,
                ),
              ],
              _NavTile(
                palette: palette,
                icon: Icons.library_music_outlined,
                title: 'Alarm sounds',
                subtitle: 'Manage uploaded custom audio files',
                onTap: () => _openAudioManager(context),
              ),
            ],
          ),
          _Section(
            palette: palette,
            icon: Icons.lock_outline,
            title: 'Security and Privacy',
            children: [
              _ToggleTile(
                palette: palette,
                icon: Icons.fingerprint,
                title: 'App lock',
                subtitle: 'Require fingerprint or face unlock to open '
                    'the app',
                value: settings.appLockEnabled,
                onChanged: (enabled) =>
                    _toggleAppLock(context, settings, enabled),
              ),
              _ToggleTile(
                palette: palette,
                icon: Icons.visibility_off_outlined,
                title: 'Secure screen',
                subtitle: 'Hide app content in the recent apps switcher',
                value: settings.secureScreenEnabled,
                onChanged: settings.setSecureScreenEnabled,
              ),
            ],
          ),
          _Section(
            palette: palette,
            icon: Icons.storage_outlined,
            title: 'Data Management and Storage',
            children: [
              _ButtonTile(
                palette: palette,
                icon: Icons.cleaning_services_outlined,
                title: 'Clear old data and cache',
                subtitle: 'Move past completed tasks to the Trash and '
                    'empty the temporary cache',
                onTap: () => _clearOldData(context),
              ),
            ],
          ),
          _Section(
            palette: palette,
            icon: Icons.center_focus_strong_outlined,
            title: 'Productivity and Focus',
            children: [
              _ToggleTile(
                palette: palette,
                icon: Icons.filter_center_focus,
                title: 'Deep focus mode',
                subtitle: 'While a task is running, hide every other '
                    'task from the dashboard',
                value: settings.deepFocusEnabled,
                onChanged: settings.setDeepFocusEnabled,
              ),
              _WeeklyPulse(palette: palette),
              _NavTile(
                palette: palette,
                icon: Icons.insights_outlined,
                title: 'Analytics dashboard',
                subtitle: 'Completion rates, daily bars and overtime',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const InsightsScreen(),
                  ),
                ),
              ),
            ],
          ),
          _Section(
            palette: palette,
            icon: Icons.swipe_outlined,
            title: 'Interaction Customization',
            children: [
              _ToggleTile(
                palette: palette,
                icon: Icons.swap_horiz,
                title: 'Swap swipe actions',
                subtitle: settings.swipeSwapped
                    ? 'Swipe right deletes, swipe left edits'
                    : 'Swipe right edits, swipe left deletes',
                value: settings.swipeSwapped,
                onChanged: settings.setSwipeSwapped,
              ),
            ],
          ),
          _Section(
            palette: palette,
            icon: Icons.accessibility_new_outlined,
            title: 'Accessibility and Display',
            children: [
              _NavTile(
                palette: palette,
                icon: Icons.palette_outlined,
                title: 'Appearance',
                subtitle: 'Details colour, background colour and background '
                    'image; applies across every screen',
                onTap: () => showAppearanceSheet(context),
              ),
              _SliderTile(
                palette: palette,
                icon: Icons.format_size,
                title: 'Task text size',
                subtitle: 'Scales task titles and times only; the '
                    'layout stays put',
                value: settings.taskFontScale,
                min: 0.85,
                max: 1.3,
                divisions: 9,
                label: '${(settings.taskFontScale * 100).round()} percent',
                onChanged: settings.setTaskFontScale,
                preview: _TaskSizePreview(
                  palette: palette,
                  fontScale: settings.taskFontScale,
                ),
              ),
              _ToggleTile(
                palette: palette,
                icon: Icons.schedule,
                title: '24-hour time',
                subtitle: settings.use24hFormat
                    ? 'Times shown as 21:30'
                    : 'Times shown as 9:30 PM',
                value: settings.use24hFormat,
                onChanged: settings.setUse24hFormat,
              ),
            ],
          ),
          _Section(
            palette: palette,
            icon: Icons.auto_delete_outlined,
            title: 'Automation and Cleanup',
            children: [
              _ChoiceTile<ArchivePolicy>(
                palette: palette,
                icon: Icons.archive_outlined,
                title: 'Completed task cleanup',
                subtitle: 'When finished tasks move to the Trash',
                value: settings.archivePolicy,
                options: {
                  for (final policy in ArchivePolicy.values)
                    policy: policy.label,
                },
                onChanged: settings.setArchivePolicy,
              ),
              _NavTile(
                palette: palette,
                icon: Icons.delete_outline,
                title: 'Trash',
                subtitle: 'Deleted tasks are kept for 30 days',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const TrashScreen(),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _toggleAppLock(
    BuildContext context,
    SettingsController settings,
    bool enabled,
  ) async {
    if (!enabled) {
      await settings.setAppLockEnabled(false);
      return;
    }
    final lockService = AppLockService();
    if (!await lockService.canUseBiometrics()) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No screen lock or biometrics are set up on this device. '
            'Add one in the system settings first.',
          ),
        ),
      );
      return;
    }
    if (await lockService.authenticate()) {
      await settings.setAppLockEnabled(true);
    }
  }

  Future<void> _clearOldData(BuildContext context) async {
    final palette = AppPalette.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: palette.surfaceElevated,
        title: Text(
          'Clear old data?',
          style: TextStyle(color: palette.textPrimary),
        ),
        content: Text(
          'Completed tasks from previous days move to the Trash '
          '(recoverable for 30 days) and the temporary cache is emptied.',
          style: TextStyle(color: palette.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: palette.support,
              foregroundColor: palette.onSupport,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final repository = TaskRepository();
    final today = TimeFormatting.dbDateKey(DateTime.now());
    final oldCompleted = await repository.findCompletedBefore(today);
    for (final task in oldCompleted) {
      if (task.id != null) await repository.softDelete(task.id!);
    }
    final freedBytes = await FileStorageService().clearTemporaryCache();

    if (!context.mounted) return;
    await context.read<TaskListController>().loadTasks();
    if (!context.mounted) return;
    final freedLabel = freedBytes > 1024 * 1024
        ? '${(freedBytes / (1024 * 1024)).toStringAsFixed(1)} MB'
        : '${(freedBytes / 1024).toStringAsFixed(0)} KB';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${oldCompleted.length} completed tasks moved to Trash, '
          '$freedLabel of cache cleared',
        ),
      ),
    );
  }

  Future<void> _openAudioManager(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _AudioManagerSheet(),
    );
  }
}

class _WeeklyPulse extends StatefulWidget {
  const _WeeklyPulse({required this.palette});

  final AppPalette palette;

  @override
  State<_WeeklyPulse> createState() => _WeeklyPulseState();
}

class _WeeklyPulseState extends State<_WeeklyPulse> {
  // load once per visit so rebuilds never requery
  late final Future<List<Task>> _weekTasks;

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    final weekAgo = DateTime(today.year, today.month, today.day - 6);
    _weekTasks = TaskRepository().findBetweenDates(
      TimeFormatting.dbDateKey(weekAgo),
      TimeFormatting.dbDateKey(today),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _weekTasks,
      builder: (context, snapshot) {
        final tasks = snapshot.data ?? const [];
        if (tasks.isEmpty) return const SizedBox.shrink();
        final completed = tasks.where((t) => t.isCompleted).length;
        final overtime =
            tasks.fold<int>(0, (sum, t) => sum + t.delayMinutes);
        final rate = completed / tasks.length;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This week: $completed of ${tasks.length} tasks done, '
                '$overtime overtime minutes',
                style: TextStyle(
                    color: widget.palette.textSecondary, fontSize: 12.5),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  height: 8,
                  child: LinearProgressIndicator(
                    value: rate,
                    backgroundColor:
                        widget.palette.support.withValues(alpha: 0.15),
                    valueColor: AlwaysStoppedAnimation<Color>(
                        widget.palette.accent),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AudioManagerSheet extends StatefulWidget {
  const _AudioManagerSheet();

  @override
  State<_AudioManagerSheet> createState() => _AudioManagerSheetState();
}

class _AudioManagerSheetState extends State<_AudioManagerSheet> {
  final FileStorageService _storage = FileStorageService();
  final TaskRepository _repository = TaskRepository();
  final AlarmService _alarmService = AlarmService();
  List<File>? _files;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final files = await _storage.listAlarmAudioFiles();
    if (mounted) setState(() => _files = files);
  }

  Future<void> _deleteFile(File file) async {
    final cleared = await _repository.clearCustomSound(file.path);
    await _storage.deleteAlarmAudioFile(file.path);
    for (final task in cleared) {
      await _alarmService.scheduleForTask(task);
    }
    if (!mounted) return;
    if (cleared.isNotEmpty) {
      await context.read<TaskListController>().loadTasks();
    }
    if (!mounted) return;
    await _refresh();
    if (!mounted || cleared.isEmpty) return;
    final count = cleared.length;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$count ${count == 1 ? 'task was' : 'tasks were'} using that file '
          'and now use the default alarm sound.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final files = _files;
    return FrostedSurface(
      color: palette.surfaceElevated,
      borderRadius:
          const BorderRadius.vertical(top: Radius.circular(24)),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'Custom alarm sounds',
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (files == null)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (files.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'No custom audio uploaded yet. Pick one from any '
                    'task\'s alarm settings.',
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(color: palette.textFaint, fontSize: 13),
                  ),
                )
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final file in files)
                        ListTile(
                          leading: Icon(Icons.audio_file_outlined,
                              color: palette.support),
                          title: Text(
                            FileStorageService.displayName(file.path),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: palette.textPrimary, fontSize: 14.5),
                          ),
                          subtitle: Text(
                            '${(file.lengthSync() / 1024).round()} KB',
                            style: TextStyle(
                                color: palette.textFaint, fontSize: 12),
                          ),
                          trailing: IconButton(
                            tooltip: 'Delete file',
                            icon: Icon(Icons.delete_outline,
                                color: palette.danger),
                            onPressed: () => _deleteFile(file),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.palette,
    required this.icon,
    required this.title,
    required this.children,
  });

  final AppPalette palette;
  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: FrostedSurface(
        color: palette.surface,
        borderRadius: BorderRadius.circular(AppConstants.cornerRadius),
        border: Border.all(color: palette.outline),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Row(
                children: [
                  Icon(icon, size: 18, color: palette.support),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ...children,
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}

class _ToggleTile extends StatelessWidget {
  const _ToggleTile({
    required this.palette,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final AppPalette palette;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      secondary: Icon(icon, color: palette.support),
      activeThumbColor: palette.onAccent,
      activeTrackColor: palette.accent,
      title: Text(
        title,
        style: TextStyle(color: palette.textPrimary, fontSize: 14.5),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: palette.textSecondary, fontSize: 12),
      ),
      value: value,
      onChanged: onChanged,
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.palette,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final AppPalette palette;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: palette.support),
      title: Text(
        title,
        style: TextStyle(color: palette.textPrimary, fontSize: 14.5),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: palette.textSecondary, fontSize: 12),
      ),
      trailing: Icon(Icons.chevron_right, color: palette.textFaint),
      onTap: onTap,
    );
  }
}

class _ButtonTile extends _NavTile {
  const _ButtonTile({
    required super.palette,
    required super.icon,
    required super.title,
    required super.subtitle,
    required super.onTap,
  });
}

class _SliderTile extends StatelessWidget {
  const _SliderTile({
    required this.palette,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.label,
    required this.onChanged,
    this.preview,
  });

  final AppPalette palette;
  final IconData icon;
  final String title;
  final String subtitle;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String label;
  final ValueChanged<double> onChanged;

  final Widget? preview;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          leading: Icon(icon, color: palette.support),
          title: Text(
            title,
            style: TextStyle(color: palette.textPrimary, fontSize: 14.5),
          ),
          subtitle: Text(
            subtitle,
            style: TextStyle(color: palette.textSecondary, fontSize: 12),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            label: label,
            activeColor: palette.accent,
            inactiveColor: palette.support.withValues(alpha: 0.2),
            onChanged: onChanged,
          ),
        ),
        if (preview != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: preview,
          ),
      ],
    );
  }
}

class _TaskSizePreview extends StatelessWidget {
  const _TaskSizePreview({
    required this.palette,
    required this.fontScale,
  });

  static const Key containerKey = ValueKey('task-text-size-preview');
  static const Key titleKey = ValueKey('task-text-size-preview-title');

  final AppPalette palette;
  final double fontScale;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: containerKey,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: palette.surfaceElevated,
        borderRadius: BorderRadius.circular(AppConstants.cornerRadius),
        border: Border.all(color: palette.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Morning workout',
            key: titleKey,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 15.5 * fontScale,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                Icons.schedule,
                size: 13,
                color: palette.textSecondary,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  TimeFormatting.rangeLabel(6 * 60, 7 * 60),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 12 * fontScale,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TimeTile extends StatelessWidget {
  const _TimeTile({
    required this.palette,
    required this.icon,
    required this.title,
    required this.minutes,
    required this.onChanged,
  });

  final AppPalette palette;
  final IconData icon;
  final String title;
  final int minutes;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: palette.support),
      title: Text(
        title,
        style: TextStyle(color: palette.textPrimary, fontSize: 14.5),
      ),
      trailing: Text(
        TimeFormatting.minutesLabel(minutes),
        style: TextStyle(
          color: palette.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
      onTap: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime:
              TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
        );
        if (picked != null) {
          onChanged(picked.hour * 60 + picked.minute);
        }
      },
    );
  }
}

class _ChoiceTile<T> extends StatelessWidget {
  const _ChoiceTile({
    required this.palette,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final AppPalette palette;
  final IconData icon;
  final String title;
  final String subtitle;
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: palette.support),
      title: Text(
        title,
        style: TextStyle(color: palette.textPrimary, fontSize: 14.5),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: palette.textSecondary, fontSize: 12),
      ),
      trailing: Text(
        options[value] ?? '',
        style: TextStyle(
          color: palette.textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
      onTap: () async {
        final picked = await showDialog<T>(
          context: context,
          builder: (dialogContext) => SimpleDialog(
            backgroundColor: palette.surfaceElevated,
            title: Text(
              title,
              style: TextStyle(color: palette.textPrimary, fontSize: 17),
            ),
            children: [
              RadioGroup<T>(
                groupValue: value,
                onChanged: (picked) =>
                    Navigator.of(dialogContext).pop(picked),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final entry in options.entries)
                      RadioListTile<T>(
                        value: entry.key,
                        activeColor: palette.accent,
                        title: Text(
                          entry.value,
                          style: TextStyle(
                              color: palette.textPrimary, fontSize: 14.5),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
        if (picked != null) onChanged(picked);
      },
    );
  }
}
