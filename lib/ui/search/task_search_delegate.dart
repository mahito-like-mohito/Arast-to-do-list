import 'package:flutter/material.dart';

import '../../core/app_palette.dart';
import '../../controllers/task_list_controller.dart';
import '../../core/time_formatting.dart';
import '../../data/models/task.dart';

class TaskSearchDelegate extends SearchDelegate<Task?> {
  TaskSearchDelegate(this._controller);

  final TaskListController _controller;

  @override
  String get searchFieldLabel => 'Search tasks';

  @override
  ThemeData appBarTheme(BuildContext context) {
    final base = Theme.of(context);
    final palette = AppPalette.of(context);
    return base.copyWith(
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: palette.onBackdrop),
      ),
      scaffoldBackgroundColor: Colors.transparent,
      inputDecorationTheme: InputDecorationTheme(
        hintStyle: TextStyle(color: palette.onBackdropMuted),
        border: InputBorder.none,
      ),
      textTheme: base.textTheme.copyWith(
        titleLarge: TextStyle(color: palette.onBackdrop, fontSize: 17),
      ),
    );
  }

  @override
  List<Widget> buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(
          tooltip: 'Clear',
          icon: const Icon(Icons.close),
          onPressed: () => query = '',
        ),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      tooltip: 'Back',
      icon: const Icon(Icons.arrow_back),
      onPressed: () => close(context, null),
    );
  }

  @override
  Widget buildResults(BuildContext context) => _buildMatches(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildMatches(context);

  Widget _buildMatches(BuildContext context) {
    if (query.trim().isEmpty) {
      return const _CenteredNote(
        message: 'Type to search your tasks by title or notes',
      );
    }

    return FutureBuilder<List<Task>>(
      future: _controller.search(query),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final results = snapshot.data ?? const <Task>[];
        if (results.isEmpty) {
          return _CenteredNote(
            message: 'No tasks match "${query.trim()}"',
          );
        }
        return ListView.builder(
          itemCount: results.length,
          itemBuilder: (context, index) {
            final task = results[index];
            final palette = AppPalette.of(context);
            return ListTile(
              leading: Icon(task.section.icon, color: palette.support),
              title: Text(
                task.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: palette.textPrimary),
              ),
              subtitle: Text(
                '${TimeFormatting.dateLabel(task.dateTime)}   '
                '${TimeFormatting.rangeLabel(task.startMinutes, task.endMinutes)}',
                style: TextStyle(color: palette.textSecondary, fontSize: 12),
              ),
              onTap: () => close(context, task),
            );
          },
        );
      },
    );
  }
}

class _CenteredNote extends StatelessWidget {
  const _CenteredNote({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.textSecondary, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
