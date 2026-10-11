import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../controllers/task_list_controller.dart';
import '../../core/app_palette.dart';
import '../../core/constants.dart';
import '../../core/schedule_validator.dart';
import '../../core/time_formatting.dart';
import '../../data/models/subtask.dart';
import '../../data/models/task.dart';
import '../../services/alarm_service.dart';
import '../../services/suggestion_service.dart';
import '../widgets/circular_time_picker.dart';
import '../widgets/delay_clock.dart';
import '../widgets/sound_picker_sheet.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/frosted_surface.dart';

class AddEditTaskScreen extends StatefulWidget {
  const AddEditTaskScreen({
    super.key,
    this.task,
    this.initialDate,
    this.suggestionService,
  });

  final Task? task;

  final DateTime? initialDate;

  final SuggestionService? suggestionService;

  @override
  State<AddEditTaskScreen> createState() => _AddEditTaskScreenState();
}

class _AddEditTaskScreenState extends State<AddEditTaskScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _notesController;
  late final TextEditingController _subtaskInputController;

  late List<Subtask> _subtasks;

  late DateTime _selectedDate;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  late int _delayMinutes;
  late bool _alarmEnabled;
  late AlarmSoundType _soundType;
  String? _soundUri;
  String? _soundLabel;

  List<Task> _dayTasks = const [];

  List<Task> _nextDayTasks = const [];

  List<ScheduleSuggestion> _suggestions = const [];

  late final SuggestionService _suggestionService;

  bool get _isEditing => widget.task != null;

  @override
  void initState() {
    super.initState();
    final task = widget.task;

    _suggestionService = widget.suggestionService ?? SuggestionService();

    _titleController = TextEditingController(text: task?.title ?? '');
    _notesController =
        TextEditingController(text: Subtasks.proseOnly(task?.notes ?? ''));
    _subtaskInputController = TextEditingController();
    _subtasks = task == null ? [] : Subtasks.parse(task.notes);

    if (task != null) {
      _selectedDate = task.dateTime;
      _startTime = task.startTimeOfDay;
      _endTime = task.endTimeOfDay;
      _delayMinutes = task.delayMinutes;
      _alarmEnabled = task.alarmEnabled;
      _soundType = task.alarmSoundType;
      _soundUri = task.alarmSoundUri;
      _soundLabel = task.alarmSoundLabel;
    } else {
      final now = DateTime.now();
      _selectedDate = widget.initialDate ?? now;
      final nextHour = (now.hour + 1) % 24;
      _startTime = TimeOfDay(hour: nextHour, minute: 0);
      _endTime = TimeOfDay(hour: (nextHour + 1) % 24, minute: 0);
      _delayMinutes = 0;
      _alarmEnabled = false;
      _soundType = AlarmSoundType.system;
      _soundUri = null;
      _soundLabel = null;
    }

    _refreshDayContext();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    _subtaskInputController.dispose();
    super.dispose();
  }

  Future<void> _refreshDayContext() async {
    final controller = context.read<TaskListController>();
    final dayTasks = await controller.tasksOn(_selectedDate);
    // step the calendar itself so daylight saving never skips a day
    final nextDayTasks = await controller.tasksOn(DateTime(
        _selectedDate.year, _selectedDate.month, _selectedDate.day + 1));

    List<ScheduleSuggestion> suggestions = const [];
    if (!_isEditing) {
      suggestions = await _suggestionService.suggestFor(
        date: _selectedDate,
        existing: dayTasks,
      );
    }

    if (!mounted) return;
    setState(() {
      _dayTasks = dayTasks;
      _nextDayTasks = nextDayTasks;
      _suggestions = suggestions;
    });
  }

  int get _startMinutes => _startTime.hour * 60 + _startTime.minute;
  int get _endMinutes => _endTime.hour * 60 + _endTime.minute;

  bool get _crossesMidnight => _endMinutes <= _startMinutes;

  Task? get _conflict => ScheduleValidator.findConflict(
        startMinutes: _startMinutes,
        endMinutes: _endMinutes,
        existing: _dayTasks,
        editingTaskId: widget.task?.id,
        nextDayExisting: _nextDayTasks,
      );

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return AppScaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Task' : 'New Task'),
      ),
      body: ListView(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + kToolbarHeight + 8,
          left: 16,
          right: 16,
          bottom: 32,
        ),
        children: [
          _SectionCard(
            palette: palette,
            title: 'Details',
            child: Column(
              children: [
                TextField(
                  controller: _titleController,
                  textCapitalization: TextCapitalization.sentences,
                  style: TextStyle(color: palette.textPrimary),
                  decoration:
                      _inputDecoration(palette, 'What do you want to do?'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _notesController,
                  textCapitalization: TextCapitalization.sentences,
                  maxLines: 3,
                  minLines: 2,
                  style: TextStyle(color: palette.textPrimary),
                  decoration: _inputDecoration(palette, 'Notes (optional)'),
                ),
              ],
            ),
          ),
          _SectionCard(
            palette: palette,
            title: 'Subtasks',
            subtitle: 'Optional steps; the task completes itself once '
                'every step is ticked',
            child: _buildSubtasks(palette),
          ),
          _SectionCard(
            palette: palette,
            title: 'Date',
            child: _buildCalendar(palette),
          ),
          _SectionCard(
            palette: palette,
            title: 'Schedule',
            child: Column(
              children: [
                if (_suggestions.isNotEmpty) ...[
                  _SuggestionRow(
                    palette: palette,
                    suggestions: _suggestions,
                    onApply: (suggestion) => setState(() {
                      _startTime = suggestion.start;
                      _endTime = suggestion.end;
                    }),
                  ),
                  const SizedBox(height: 20),
                ],
                CircularTimePicker(
                  label: 'Start Time',
                  value: _startTime,
                  onChanged: (time) => setState(() => _startTime = time),
                ),
                const SizedBox(height: 28),
                CircularTimePicker(
                  label: 'End Time',
                  value: _endTime,
                  onChanged: (time) => setState(() => _endTime = time),
                ),
                if (_crossesMidnight) ...[
                  const SizedBox(height: 14),
                  _InfoStrip(
                    palette: palette,
                    icon: Icons.nights_stay_outlined,
                    text: 'Ends after midnight, on the following day',
                  ),
                ],
                if (_conflict != null) ...[
                  const SizedBox(height: 10),
                  _InfoStrip(
                    palette: palette,
                    icon: Icons.block,
                    emphasized: true,
                    text: 'This slot is taken by "${_conflict!.title}" '
                        '(${TimeFormatting.rangeLabel(_conflict!.startMinutes, _conflict!.endMinutes)}). '
                        'Adjust the times to save.',
                  ),
                ],
              ],
            ),
          ),
          _SectionCard(
            palette: palette,
            title: 'Running late?',
            subtitle: 'Add overtime minutes if this task takes longer '
                'than expected',
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: DelayClock(
                minutes: _delayMinutes,
                onChanged: (minutes) =>
                    setState(() => _delayMinutes = minutes),
              ),
            ),
          ),
          _SectionCard(
            palette: palette,
            title: 'Alarm',
            subtitle: 'Rings ${AppConstants.audioLeadTime.inSeconds} seconds '
                'before the start time, after a silent early warning',
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _alarmEnabled,
                  activeThumbColor: palette.onAccent,
                  activeTrackColor: palette.accent,
                  title: Text(
                    'Enable alarm for this task',
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 14.5,
                    ),
                  ),
                  onChanged: (value) =>
                      setState(() => _alarmEnabled = value),
                ),
                if (_alarmEnabled)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading:
                        Icon(Icons.music_note_outlined, color: palette.support),
                    title: Text(
                      _soundLabel ?? 'Default alarm sound',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 14.5,
                      ),
                    ),
                    subtitle: Text(
                      _soundType == AlarmSoundType.custom
                          ? 'Custom audio file'
                          : 'System sound',
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    trailing: Icon(
                      Icons.chevron_right,
                      color: palette.textFaint,
                    ),
                    onTap: _chooseSound,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: palette.accent,
              foregroundColor: palette.onAccent,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.circular(AppConstants.cornerRadius),
              ),
            ),
            onPressed: _save,
            child: Text(
              _isEditing ? 'Save Changes' : 'Create Task',
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(AppPalette palette, String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: palette.textFaint),
      filled: true,
      fillColor: palette.support.withValues(alpha: 0.08),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    );
  }

  void _addSubtask() {
    final text = _subtaskInputController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _subtasks.add(Subtask(text: text));
      _subtaskInputController.clear();
    });
  }

  void _toggleSubtask(int index) {
    setState(() {
      _subtasks[index] =
          _subtasks[index].copyWith(isDone: !_subtasks[index].isDone);
    });
  }

  void _deleteSubtask(int index) {
    setState(() => _subtasks.removeAt(index));
  }

  Widget _buildSubtasks(AppPalette palette) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _subtaskInputController,
                textCapitalization: TextCapitalization.sentences,
                onSubmitted: (_) => _addSubtask(),
                style: TextStyle(color: palette.textPrimary),
                decoration: _inputDecoration(palette, 'Add a subtask'),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Add subtask',
              style: IconButton.styleFrom(
                backgroundColor: palette.accent,
                foregroundColor: palette.onAccent,
              ),
              icon: const Icon(Icons.add),
              onPressed: _addSubtask,
            ),
          ],
        ),
        const SizedBox(height: 4),
        for (var i = 0; i < _subtasks.length; i++)
          _SubtaskRow(
            item: _subtasks[i],
            palette: palette,
            onToggle: () => _toggleSubtask(i),
            onDelete: () => _deleteSubtask(i),
          ),
      ],
    );
  }

  Widget _buildCalendar(AppPalette palette) {
    return TableCalendar<void>(
      firstDay: DateTime.utc(2020, 1, 1),
      lastDay: DateTime.utc(2035, 12, 31),
      focusedDay: _selectedDate,
      selectedDayPredicate: (day) => isSameDay(day, _selectedDate),
      onDaySelected: (selected, focused) {
        setState(() => _selectedDate = selected);
        _refreshDayContext();
      },
      availableGestures: AvailableGestures.horizontalSwipe,
      headerStyle: HeaderStyle(
        formatButtonVisible: false,
        titleCentered: true,
        titleTextStyle: TextStyle(
          color: palette.textPrimary,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
        leftChevronIcon:
            Icon(Icons.chevron_left, color: palette.textSecondary),
        rightChevronIcon:
            Icon(Icons.chevron_right, color: palette.textSecondary),
      ),
      daysOfWeekStyle: DaysOfWeekStyle(
        weekdayStyle: TextStyle(
          color: palette.textSecondary,
          fontSize: 12,
        ),
        weekendStyle: TextStyle(
          color: palette.support,
          fontSize: 12,
        ),
      ),
      calendarStyle: CalendarStyle(
        defaultTextStyle: TextStyle(color: palette.textPrimary),
        weekendTextStyle: TextStyle(color: palette.textPrimary),
        outsideTextStyle: TextStyle(color: palette.textFaint),
        selectedDecoration: BoxDecoration(
          color: palette.accent,
          shape: BoxShape.circle,
        ),
        selectedTextStyle: TextStyle(
          color: palette.onAccent,
          fontWeight: FontWeight.w700,
        ),
        todayDecoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: palette.accent, width: 1.5),
        ),
        todayTextStyle: TextStyle(color: palette.textPrimary),
      ),
    );
  }

  Future<void> _chooseSound() async {
    final selection = await showSoundPickerSheet(context);
    if (selection == null) return;
    setState(() {
      _soundType = selection.type;
      _soundUri = selection.uri;
      _soundLabel = selection.label;
    });
  }

  void _showConflictSnackBar(Task conflict) {
    final palette = AppPalette.of(context);
    final range = TimeFormatting.rangeLabel(
        conflict.startMinutes, conflict.endMinutes);

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 4),
          content: Row(
            children: [
              Icon(Icons.event_busy_outlined,
                  size: 20, color: palette.onInverseSurface),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Time slot already occupied by "${conflict.title}" '
                  '($range)',
                  style: TextStyle(color: palette.onInverseSurface),
                ),
              ),
            ],
          ),
        ),
      );
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Give your task a title first')),
      );
      return;
    }

    if (_startMinutes == _endMinutes) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('End time must be different from start time'),
        ),
      );
      return;
    }

    final conflict = _conflict;
    if (conflict != null) {
      _showConflictSnackBar(conflict);
      return;
    }

    // the form hides checklist syntax and shows plain text
    final prose = Subtasks.proseOnly(_notesController.text);
    final allSubtasks = [
      ..._subtasks,
      ...Subtasks.parse(_notesController.text),
    ];
    final notes = allSubtasks.isEmpty
        ? prose.trim()
        : Subtasks.writeBack(prose, allSubtasks);

    final task = Task(
      id: widget.task?.id,
      title: title,
      notes: notes,
      date: TimeFormatting.dbDateKey(_selectedDate),
      startMinutes: _startMinutes,
      endMinutes: _endMinutes,
      delayMinutes: _delayMinutes,
      isCompleted: widget.task?.isCompleted ?? false,
      alarmEnabled: _alarmEnabled,
      alarmSoundType: _soundType,
      alarmSoundUri: _soundUri,
      alarmSoundLabel: _soundLabel,
    );

    final controller = context.read<TaskListController>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    await controller.saveTask(task);
    // without the exact alarm grant the os refuses silently so warn now
    if (_alarmEnabled && !await AlarmService.exactAlarmsGranted()) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Task saved, but Alarms & reminders permission is off — '
            'the alarm may not ring until you enable it.',
          ),
        ),
      );
      return;
    }
    if (navigator.canPop()) navigator.pop();
  }
}

class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({
    required this.palette,
    required this.suggestions,
    required this.onApply,
  });

  final AppPalette palette;
  final List<ScheduleSuggestion> suggestions;
  final ValueChanged<ScheduleSuggestion> onApply;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Suggested for this day',
          style: TextStyle(
            color: palette.textSecondary,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 62,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: suggestions.length,
            separatorBuilder: (context, index) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final suggestion = suggestions[index];
              final start = suggestion.start;
              final end = suggestion.end;
              return InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => onApply(suggestion),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: palette.accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: palette.accent.withValues(alpha: 0.55),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        TimeFormatting.rangeLabel(
                          start.hour * 60 + start.minute,
                          end.hour * 60 + end.minute,
                        ),
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        suggestion.reason,
                        style: TextStyle(
                          color: palette.textSecondary,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SubtaskRow extends StatelessWidget {
  const _SubtaskRow({
    required this.item,
    required this.palette,
    required this.onToggle,
    required this.onDelete,
  });

  final Subtask item;
  final AppPalette palette;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Icon(
              item.isDone ? Icons.check_box : Icons.check_box_outline_blank,
              size: 20,
              color: item.isDone ? palette.support : palette.textSecondary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                item.text,
                style: TextStyle(
                  color:
                      item.isDone ? palette.textFaint : palette.textPrimary,
                  fontSize: 14,
                  decoration: item.isDone
                      ? TextDecoration.lineThrough
                      : TextDecoration.none,
                  decorationColor: palette.textFaint,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Delete subtask',
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.delete_outline, size: 20, color: palette.danger),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoStrip extends StatelessWidget {
  const _InfoStrip({
    required this.palette,
    required this.icon,
    required this.text,
    this.emphasized = false,
  });

  final AppPalette palette;
  final IconData icon;
  final String text;

  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final tint = emphasized ? palette.danger : palette.support;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tint.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 17, color: tint),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 12.5,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.palette,
    required this.title,
    required this.child,
    this.subtitle,
  });

  final AppPalette palette;
  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: FrostedSurface(
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
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(
                  subtitle!,
                  style:
                      TextStyle(color: palette.textSecondary, fontSize: 12.5),
                ),
              ],
              const SizedBox(height: 12),
              child,
            ],
          ),
        ),
      ),
    );
  }
}
