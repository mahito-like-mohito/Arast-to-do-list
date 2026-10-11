import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/task_list_controller.dart';
import '../../core/app_palette.dart';
import '../../core/constants.dart';
import '../../core/time_formatting.dart';
import '../../data/models/task.dart';
import '../../data/repositories/task_repository.dart';
import '../../services/alarm_service.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/frosted_surface.dart';

class TrashScreen extends StatefulWidget {
  const TrashScreen({super.key});

  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  final TaskRepository _repository = TaskRepository();
  final AlarmService _alarmService = AlarmService();

  List<Task>? _trashed;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final trashed = await _repository.findTrashed();
    if (mounted) setState(() => _trashed = trashed);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final trashed = _trashed;

    return AppScaffold(
      appBar: AppBar(title: const Text('Trash')),
      floatingActionButton: trashed != null && trashed.isNotEmpty
          ? FloatingActionButton(
              tooltip: 'Empty Trash',
              backgroundColor: palette.danger,
              foregroundColor: Colors.white,
              onPressed: _emptyTrash,
              child: const Icon(Icons.delete_outline),
            )
          : null,
      body: Padding(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + kToolbarHeight + 8,
        ),
        child: trashed == null
            ? const Center(child: CircularProgressIndicator())
            : trashed.isEmpty
                ? _EmptyTrash(palette: palette)
                : Column(
                    children: [
                      _RetentionBanner(palette: palette),
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.only(bottom: 96),
                          itemCount: trashed.length,
                          itemBuilder: (context, index) => _TrashTile(
                            palette: palette,
                            task: trashed[index],
                            onRestore: () => _restore(trashed[index]),
                            onPurge: () => _purgeOne(trashed[index]),
                          ),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }

  Future<void> _restore(Task task) async {
    final id = task.id;
    if (id == null) return;
    await _repository.restoreFromTrash(id);
    await _alarmService.scheduleForTask(task.copyWith(clearDeletedAt: true));
    await _refresh();
    if (!mounted) return;
    await context.read<TaskListController>().loadTasks();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Restored "${task.title}"')),
    );
  }

  Future<void> _purgeOne(Task task) async {
    final id = task.id;
    if (id == null) return;
    await _repository.delete(id);
    await _refresh();
  }

  Future<void> _emptyTrash() async {
    final palette = AppPalette.of(context);
    final count = _trashed?.length ?? 0;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: palette.surfaceElevated,
        title: Text(
          'Empty the Trash?',
          style: TextStyle(color: palette.textPrimary),
        ),
        content: Text(
          count == 1
              ? 'The 1 task in the Trash will be deleted permanently. '
                  'This cannot be undone.'
              : 'All $count tasks in the Trash will be deleted '
                  'permanently. This cannot be undone.',
          style: TextStyle(color: palette.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: palette.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete All Permanently'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final purged = await _repository.purgeAllTrash();
    await _refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          purged == 1
              ? '1 task deleted permanently'
              : '$purged tasks deleted permanently',
        ),
      ),
    );
  }
}

class _RetentionBanner extends StatelessWidget {
  const _RetentionBanner({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: palette.support.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.support.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.history_toggle_off, size: 18, color: palette.support),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Deleted tasks are kept for '
              '${AppConstants.trashRetention.inDays} days, then removed '
              'permanently.',
              style: TextStyle(
                color: palette.textSecondary,
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

class _TrashTile extends StatelessWidget {
  const _TrashTile({
    required this.palette,
    required this.task,
    required this.onRestore,
    required this.onPurge,
  });

  final AppPalette palette;
  final Task task;
  final VoidCallback onRestore;
  final VoidCallback onPurge;

  String get _expiryLabel {
    final deletedAt = task.deletedAtTime;
    if (deletedAt == null) return '';
    final expiresIn = AppConstants.trashRetention -
        DateTime.now().difference(deletedAt);
    final days = expiresIn.inDays;
    if (days <= 0) return 'Removed at next cleanup';
    return days == 1 ? 'Removed in 1 day' : 'Removed in $days days';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: FrostedSurface(
        color: palette.surface,
        borderRadius: BorderRadius.circular(AppConstants.cornerRadius),
        border: Border.all(color: palette.outline),
        child: ListTile(
          leading: Icon(task.section.icon, color: palette.textFaint),
          title: Text(
            task.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: palette.textPrimary, fontSize: 14.5),
          ),
          subtitle: Text(
            '${TimeFormatting.dateLabel(task.dateTime)}   '
                '${TimeFormatting.rangeLabel(task.startMinutes, task.endMinutes)}'
                '\n$_expiryLabel',
            style: TextStyle(
              color: palette.textSecondary,
              fontSize: 11.5,
              height: 1.4,
            ),
          ),
          isThreeLine: true,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Restore',
                icon: Icon(Icons.restore, color: palette.accent),
                onPressed: onRestore,
              ),
              IconButton(
                tooltip: 'Delete forever',
                icon: Icon(Icons.delete_forever_outlined,
                    color: palette.danger),
                onPressed: onPurge,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyTrash extends StatelessWidget {
  const _EmptyTrash({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'The Trash is empty',
            style: TextStyle(
              color: palette.onBackdrop,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Deleted tasks wait here for 30 days before being '
            'removed for good.',
            textAlign: TextAlign.center,
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
