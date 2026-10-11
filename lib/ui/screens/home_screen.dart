import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/settings_controller.dart';
import '../../controllers/task_list_controller.dart';
import '../../core/app_palette.dart';
import '../../core/theme_controller.dart';
import '../../core/time_formatting.dart';
import '../../data/models/task.dart';
import '../../data/models/time_section.dart';
import '../search/task_search_delegate.dart';
import '../widgets/app_drawer.dart';
import '../widgets/task_tile.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/undo_snackbar.dart';
import '../widgets/time_section_header.dart';
import 'add_edit_task_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Timer? _focusTimer;

  late final SettingsController _settings;

  @override
  void initState() {
    super.initState();
    _settings = context.read<SettingsController>();
    _settings.addListener(_syncFocusTimer);
    _syncFocusTimer(notify: false);
  }

  @override
  void dispose() {
    _settings.removeListener(_syncFocusTimer);
    _focusTimer?.cancel();
    _focusTimer = null;
    super.dispose();
  }

  void _syncFocusTimer({bool notify = true}) {
    final enabled = _settings.deepFocusEnabled;
    if (enabled && _focusTimer == null) {
      _focusTimer = Timer.periodic(
        const Duration(minutes: 1),
        (_) {
          if (mounted) setState(() {});
        },
      );
    } else if (!enabled && _focusTimer != null) {
      _focusTimer!.cancel();
      _focusTimer = null;
    }
    if (notify && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.watch<ThemeController>().palette;
    final controller = context.watch<TaskListController>();

    return AppScaffold(
      endDrawer: const AppDrawer(),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('My Day'),
        actions: [
          IconButton(
            tooltip: 'Search tasks',
            icon: const Icon(Icons.search),
            onPressed: () => _openSearch(context),
          ),
          Builder(
            builder: (buttonContext) => IconButton(
              tooltip: 'Menu',
              icon: const Icon(Icons.menu),
              onPressed: () => Scaffold.of(buttonContext).openEndDrawer(),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add task',
        onPressed: () => _openEditor(context),
        child: const Icon(Icons.add, size: 28),
      ),
      body: Padding(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + kToolbarHeight,
        ),
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _DateBar(controller: controller)),
            if (controller.isLoading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (controller.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyState(),
              )
            else
              ..._buildSectionSlivers(context, controller, palette),
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildSectionSlivers(
    BuildContext context,
    TaskListController controller,
    AppPalette palette,
  ) {
    var grouped = controller.groupedTasks;

    final settings = context.read<SettingsController>();
    if (settings.deepFocusEnabled) {
      final now = DateTime.now();
      bool isActive(Task task) =>
          !task.isCompleted &&
          !now.isBefore(task.startDateTime) &&
          now.isBefore(task.endDateTime);
      final anyActive =
          grouped.values.any((tasks) => tasks.any(isActive));
      if (anyActive) {
        grouped = {
          for (final entry in grouped.entries)
            if (entry.value.any(isActive))
              entry.key: entry.value.where(isActive).toList(),
        };
      }
    }

    final slivers = <Widget>[];

    for (final section in TimeSection.values) {
      final tasks = grouped[section];
      if (tasks == null || tasks.isEmpty) continue;

      slivers.add(
        SliverMainAxisGroup(
          slivers: [
            SliverPersistentHeader(
              pinned: true,
              delegate: TimeSectionHeaderDelegate(
                section: section,
                taskCount: tasks.length,
                palette: palette,
              ),
            ),
            SliverList.builder(
              itemCount: tasks.length,
              itemBuilder: (context, index) {
                final task = tasks[index];
                return TaskTile(
                  key: ValueKey('task-${task.id}'),
                  task: task,
                  animateEntrance: controller.shouldAnimateRestore(task.id),
                  onEdit: () => _openEditor(context, task: task),
                  onDelete: () => _deleteWithUndo(context, task),
                  onToggleCompleted: () =>
                      context.read<TaskListController>().toggleCompleted(
                            task,
                            archiveWhenCompleted: context
                                    .read<SettingsController>()
                                    .archivePolicy ==
                                ArchivePolicy.immediately,
                          ),
                  onChecklistChanged: (updated) => context
                      .read<TaskListController>()
                      .saveTask(updated),
                );
              },
            ),
          ],
        ),
      );
    }
    return slivers;
  }

  Future<void> _openSearch(BuildContext context) async {
    final controller = context.read<TaskListController>();
    final picked = await showSearch<Task?>(
      context: context,
      delegate: TaskSearchDelegate(controller),
    );
    if (picked != null && context.mounted) {
      await _openEditor(context, task: picked);
    }
  }

  Future<void> _openEditor(BuildContext context, {Task? task}) async {
    final controller = context.read<TaskListController>();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AddEditTaskScreen(
          task: task,
          initialDate: controller.selectedDate,
        ),
      ),
    );
  }

  void _deleteWithUndo(BuildContext context, Task task) {
    final controller = context.read<TaskListController>();
    controller.deleteTaskDeferred(task);
    showUndoDeleteSnackBar(
      context,
      taskTitle: task.title,
      onUndo: () => controller.undoDeleteTask(task),
    );
  }
}

class _DateBar extends StatelessWidget {
  const _DateBar({required this.controller});

  final TaskListController controller;

  bool get _isToday {
    final now = DateTime.now();
    final selected = controller.selectedDate;
    return selected.year == now.year &&
        selected.month == now.month &&
        selected.day == now.day;
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Previous day',
            icon: Icon(Icons.chevron_left, color: palette.onBackdropMuted),
            onPressed: controller.goToPreviousDay,
          ),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: controller.goToToday,
              child: Column(
                children: [
                  Text(
                    _isToday
                        ? 'Today'
                        : TimeFormatting.dateLabel(controller.selectedDate),
                    style: TextStyle(
                      color: palette.onBackdrop,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (!_isToday)
                    Text(
                      'Tap to return to today',
                      style: TextStyle(
                        color: palette.onBackdropMuted,
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: 'Next day',
            icon: Icon(Icons.chevron_right, color: palette.onBackdropMuted),
            onPressed: controller.goToNextDay,
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'A clear day ahead',
            style: TextStyle(
              color: palette.onBackdrop,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Tap the plus button to plan something great',
            style: TextStyle(
              color: palette.onBackdropMuted,
              fontSize: 13.5,
            ),
          ),
        ],
      ),
    );
  }
}
