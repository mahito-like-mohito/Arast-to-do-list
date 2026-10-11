import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:advanced_todo_list/controllers/settings_controller.dart';
import 'package:advanced_todo_list/services/settings_service.dart';
import 'package:advanced_todo_list/data/models/task.dart';
import 'package:advanced_todo_list/data/repositories/task_repository.dart';
import 'package:advanced_todo_list/services/alarm_service.dart';
import 'package:advanced_todo_list/controllers/task_list_controller.dart';
import 'package:advanced_todo_list/ui/widgets/note_reveal.dart';
import 'package:advanced_todo_list/ui/widgets/subtask_editor_sheet.dart';
import 'package:advanced_todo_list/ui/widgets/task_tile.dart';

class _FakeRepo extends TaskRepository {
  _FakeRepo(this.tasks);
  List<Task> tasks;

  @override
  Future<List<Task>> findByDate(String date) async => tasks;
  @override
  Future<void> update(Task task) async {
    await Future<void>.delayed(const Duration(milliseconds: 30));
    final i = tasks.indexWhere((t) => t.id == task.id);
    if (i >= 0) tasks[i] = task;
  }
}

void main() {
  testWidgets('BUG1: deleting the LAST row in the editor crashes / shows wrong row',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SubtaskEditorSheet(
            initialNote: 'Plan\n- [ ] Blue tape\n- [x] Wrapping paper'),
      ),
    ));
    await tester.tap(
        find.widgetWithIcon(IconButton, Icons.delete_outline).at(1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final errors = tester.takeException();
    debugPrint('BUG1 exception: $errors');
    expect(errors, isNull, reason: 'last-row delete must not throw');
  });

  testWidgets('BUG2: two quick taps on different rows lose the first toggle (stale note)',
      (tester) async {
    final task = Task(
      id: 1,
      title: 'Birthday shopping',
      date: '2026-07-26',
      startMinutes: 9 * 60,
      endMinutes: 10 * 60,
      notes: 'Plan\n- [ ] Blue tape\n- [ ] Ribbon',
    );
    final saved = <String>[];
    SharedPreferences.setMockInitialValues({});
    final settings =
        SettingsController(settingsService: await SettingsService.create());
    await tester.pumpWidget(MaterialApp(
      home: ChangeNotifierProvider.value(
        value: settings,
        child: Scaffold(
          body: SizedBox(
            width: 360,
            child: TaskTile(
              task: task,
              onEdit: () {},
              onDelete: () {},
              onToggleCompleted: () {},
              onChecklistChanged: (t) => saved.add(t.notes),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.byKey(NoteReveal.pullStripKey));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Blue tape'));
    await tester.tap(find.text('Ribbon'));
    await tester.pumpAndSettle();

    final last = saved.last;
    debugPrint('BUG2 last saved note: ${last.replaceAll('\n', ' | ')}');
    expect(last.contains('- [x] Blue tape'), isTrue,
        reason: 'first toggle must survive the second tap');
    expect(last.contains('- [x] Ribbon'), isTrue);
  });

  test('BUG3: saveTask notifies with isLoading=true mid-save (list unmount window)',
      () async {
    final task = Task(
      id: 1,
      title: 'T',
      date: '2026-07-26',
      startMinutes: 9 * 60,
      endMinutes: 10 * 60,
      notes: '- [ ] a',
    );
    final repo = _FakeRepo([task]);
    final controller = TaskListController(
      repository: repo,
      alarmService: AlarmService(repository: repo),
    );
    await controller.loadTasks();

    var sawLoadingDuringSave = false;
    controller.addListener(() {
      if (controller.isLoading) sawLoadingDuringSave = true;
    });

    await controller.saveTask(task.copyWith(notes: '- [x] a'));
    debugPrint('BUG3 sawLoadingDuringSave: $sawLoadingDuringSave');
    expect(sawLoadingDuringSave, isFalse,
        reason: 'a note-only save must not flip the list into its loading state');
    controller.dispose();
  });
}
