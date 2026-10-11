import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'dart:io';

import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:advanced_todo_list/controllers/settings_controller.dart';
import 'package:advanced_todo_list/controllers/task_list_controller.dart';
import 'package:advanced_todo_list/services/settings_service.dart';
import 'package:advanced_todo_list/core/app_palette.dart';
import 'package:advanced_todo_list/core/constants.dart';
import 'package:advanced_todo_list/core/external_picker.dart';
import 'package:advanced_todo_list/core/task_time_colors.dart';
import 'package:advanced_todo_list/core/time_formatting.dart';
import 'package:advanced_todo_list/data/models/task.dart';
import 'package:advanced_todo_list/data/models/subtask.dart';
import 'package:advanced_todo_list/data/models/time_section.dart';
import 'package:advanced_todo_list/data/repositories/task_repository.dart';
import 'package:advanced_todo_list/services/alarm_service.dart';
import 'package:advanced_todo_list/services/file_storage_service.dart';
import 'package:advanced_todo_list/services/suggestion_service.dart';
import 'package:advanced_todo_list/core/theme_controller.dart';
import 'package:advanced_todo_list/ui/widgets/active_task_ring.dart';
import 'package:advanced_todo_list/ui/widgets/appearance_sheet.dart';
import 'package:advanced_todo_list/ui/widgets/circular_time_picker.dart';
import 'package:advanced_todo_list/ui/widgets/color_wheel.dart';
import 'package:advanced_todo_list/ui/widgets/delay_clock.dart';
import 'package:advanced_todo_list/ui/widgets/note_reveal.dart';
import 'package:advanced_todo_list/ui/widgets/sound_picker_sheet.dart';
import 'package:advanced_todo_list/ui/widgets/task_tile.dart';
import 'package:advanced_todo_list/ui/widgets/task_progress_bar.dart';
import 'package:advanced_todo_list/ui/screens/settings_screen.dart';
import 'package:advanced_todo_list/ui/search/task_search_delegate.dart';
import 'package:advanced_todo_list/ui/widgets/themed_background.dart';
import 'package:advanced_todo_list/ui/widgets/undo_snackbar.dart';
import 'package:advanced_todo_list/ui/screens/add_edit_task_screen.dart';

class _FakeRepository extends TaskRepository {
  _FakeRepository([List<Task>? tasks]) : tasks = List.of(tasks ?? const []);

  final List<Task> tasks;
  final List<int> deletedIds = [];
  final List<int> softDeletedIds = [];

  int _nextId = 1;

  @override
  Future<Task> insert(Task task) async {
    final stored = task.copyWith(id: _nextId++);
    tasks.add(stored);
    return stored;
  }

  @override
  Future<void> update(Task task) async {
    final index = tasks.indexWhere((t) => t.id == task.id);
    if (index >= 0) tasks[index] = task;
  }

  @override
  Future<List<Task>> findBetweenDates(String fromDate, String toDate) async {
    return tasks;
  }

  @override
  Future<List<Task>> findByDate(String date) async {
    return tasks.where((t) => t.date == date).toList();
  }

  @override
  Future<void> delete(int id) async {
    deletedIds.add(id);
    tasks.removeWhere((t) => t.id == id);
  }

  @override
  Future<void> softDelete(int id, {DateTime? now}) async {
    softDeletedIds.add(id);
    tasks.removeWhere((t) => t.id == id);
  }

  @override
  Future<List<Task>> search(String query) async {
    final q = query.toLowerCase();
    return tasks
        .where((t) =>
            t.title.toLowerCase().contains(q) ||
            t.notes.toLowerCase().contains(q))
        .toList();
  }
}

void main() {
  group('TimeSection classification', () {
    test('maps start minutes to the correct time block', () {
      expect(TimeSection.fromStartMinute(6 * 60), TimeSection.morning);
      expect(TimeSection.fromStartMinute(12 * 60), TimeSection.noon);
      expect(TimeSection.fromStartMinute(16 * 60 + 59), TimeSection.noon);
      expect(TimeSection.fromStartMinute(21 * 60), TimeSection.night);
    });

    test('uses warm encouraging header copy, not plain block names', () {
      expect(TimeSection.morning.title, 'Energetic Start');
      expect(TimeSection.night.title, 'Peaceful Rest');
    });
  });

  group('Task model', () {
    const task = Task(
      title: 'Review notes',
      date: '2026-07-26',
      startMinutes: 9 * 60,
      endMinutes: 10 * 60,
      delayMinutes: 15,
    );

    test('round-trips through the SQLite map representation', () {
      final restored = Task.fromMap(task.toMap());
      expect(restored.title, task.title);
      expect(restored.startMinutes, task.startMinutes);
      expect(restored.delayMinutes, 15);
      expect(restored.alarmEnabled, isFalse);
    });

    test('effective end includes overtime delay minutes', () {
      expect(task.endDateTime, DateTime(2026, 7, 26, 10, 15));
    });

    test('an end at or before the start rolls over to the next day', () {
      const nightTask = Task(
        title: 'Night shift',
        date: '2026-07-26',
        startMinutes: 23 * 60,
        endMinutes: 1 * 60,
      );
      expect(nightTask.endDateTime, DateTime(2026, 7, 27, 1, 0));
    });
  });

  group('TimeFormatting', () {
    test('formats ranges in a 12-hour clock', () {
      expect(TimeFormatting.rangeLabel(9 * 60, 13 * 60 + 30),
          '9:00 AM - 1:30 PM');
    });

    test('formats durations compactly', () {
      expect(TimeFormatting.durationLabel(const Duration(minutes: 125)),
          '2h 05m');
      expect(TimeFormatting.durationLabel(const Duration(minutes: 45)), '45m');
      expect(TimeFormatting.durationLabel(const Duration(seconds: 30)), '30s');
    });
  });

  group('CircularTimePicker', () {
    testWidgets('renders both dials and flips AM to PM from the centre toggle',
        (tester) async {
      TimeOfDay? changed;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CircularTimePicker(
              label: 'Start Time',
              value: const TimeOfDay(hour: 9, minute: 30),
              onChanged: (value) => changed = value,
            ),
          ),
        ),
      );

      expect(find.text('Start Time'), findsOneWidget);
      expect(find.text('9:30 AM'), findsOneWidget);
      expect(find.text('AM'), findsOneWidget);

      await tester.tap(find.text('AM'));
      expect(changed, const TimeOfDay(hour: 21, minute: 30));
    });
  });

  group('AppPalette adaptive contrast', () {
    test('default light blue and brown palette uses dark ink on its light '
        'surfaces', () {
      final palette = AppPalette.fromSeeds(
        accent: AppPalette.lightBlue,
        hasBackdropImage: false,
      );
      expect(
        ThemeData.estimateBrightnessForColor(palette.surface),
        Brightness.light,
      );
      expect(
        ThemeData.estimateBrightnessForColor(palette.textPrimary),
        Brightness.dark,
      );
      expect(
        ThemeData.estimateBrightnessForColor(palette.onAccent),
        Brightness.dark,
      );
    });

    test('a dark accent from the RGB wheel flips its foreground to light',
        () {
      final palette = AppPalette.fromSeeds(
        accent: const Color(0xFF1B2A38),
        hasBackdropImage: false,
      );
      expect(
        ThemeData.estimateBrightnessForColor(palette.onAccent),
        Brightness.light,
      );
    });

    test('backdrop ink flips between solid and photo backgrounds', () {
      final onSolid = AppPalette.fromSeeds(
        accent: AppPalette.lightBlue,
        hasBackdropImage: false,
      );
      final onPhoto = AppPalette.fromSeeds(
        accent: AppPalette.lightBlue,
        hasBackdropImage: true,
      );
      expect(
        ThemeData.estimateBrightnessForColor(onSolid.onBackdrop),
        Brightness.dark,
      );
      expect(
        ThemeData.estimateBrightnessForColor(onPhoto.onBackdrop),
        Brightness.light,
      );
    });

    test('no saved colour means the first offered swatch', () {
      final unset = AppPalette.fromSeeds(
        accent: AppPalette.lightBlue,
        hasBackdropImage: false,
      );
      final chosen = AppPalette.fromSeeds(
        accent: AppPalette.lightBlue,
        hasBackdropImage: false,
        backgroundColor: AppPalette.backgroundSwatches.first,
      );
      expect(unset.backdropBase, AppPalette.backgroundSwatches.first);
      expect(unset.backdropBase, chosen.backdropBase);
      expect(unset.surface, chosen.surface);
      expect(unset.surfaceElevated, chosen.surfaceElevated);
    });

    test('a chosen background retints the card surfaces, not just the '
        'backdrop', () {
      final defaultPalette = AppPalette.fromSeeds(
        accent: AppPalette.lightBlue,
        hasBackdropImage: false,
      );
      final tinted = AppPalette.fromSeeds(
        accent: AppPalette.lightBlue,
        hasBackdropImage: false,
        backgroundColor: AppPalette.paleBlue,
      );

      expect(tinted.backdropBase, AppPalette.paleBlue);
      expect(tinted.surface, isNot(defaultPalette.surface));
      expect(tinted.surfaceElevated, isNot(defaultPalette.surfaceElevated));
      expect(tinted.surface, isNot(tinted.backdropBase));
    });

    test('a dark background flips card ink and lifts the brown support tone',
        () {
      final dark = AppPalette.fromSeeds(
        accent: AppPalette.lightBlue,
        hasBackdropImage: false,
        backgroundColor: const Color(0xFF23303A),
      );

      expect(
        ThemeData.estimateBrightnessForColor(dark.surface),
        Brightness.dark,
      );
      expect(
        ThemeData.estimateBrightnessForColor(dark.textPrimary),
        Brightness.light,
      );
      expect(dark.support, isNot(AppPalette.brown));
      expect(
        ThemeData.estimateBrightnessForColor(dark.support),
        Brightness.light,
      );
      expect(
        ThemeData.estimateBrightnessForColor(dark.inverseSurface),
        Brightness.light,
      );
    });

    test('a photo backdrop frosts the cards instead of leaving them one '
        'flat cream', () {
      final defaultPalette = AppPalette.fromSeeds(
        accent: AppPalette.lightBlue,
        hasBackdropImage: false,
      );
      final onPhoto = AppPalette.fromSeeds(
        accent: AppPalette.lightBlue,
        hasBackdropImage: true,
        backgroundColor: const Color(0xFF23303A),
      );

      expect(defaultPalette.backdropBase, AppPalette.cream);
      expect(defaultPalette.surfaceBlurred, isFalse);
      expect(onPhoto.surfaceBlurred, isTrue);
      expect(onPhoto.surface.toARGB32() & 0xFFFFFF, 0xFFFFFF);
      expect(
        onPhoto.surface.toARGB32() >> 24,
        lessThan(defaultPalette.surface.toARGB32() >> 24),
      );
      expect(
        onPhoto.surfaceElevated.toARGB32() >> 24,
        lessThan(defaultPalette.surfaceElevated.toARGB32() >> 24),
      );
      expect(
        ThemeData.estimateBrightnessForColor(onPhoto.textPrimary),
        Brightness.dark,
      );
      expect(
        ThemeData.estimateBrightnessForColor(onPhoto.onBackdrop),
        Brightness.light,
      );
    });
  });

  group('Frosted glass surfaces', () {
    final now = DateTime(2026, 7, 26, 9, 30);

    File backgroundImageFile() {
      final src = File('assets/icon/app_icon.png');
      final dst = File(
          '${Directory.systemTemp.path}${Platform.pathSeparator}frost_bg.png');
      src.copySync(dst.path);
      addTearDown(() {
        if (dst.existsSync()) dst.deleteSync();
      });
      return dst;
    }

    testWidgets('a background image frosts the task card; the default '
        'theme stays plain', (tester) async {
      final image = backgroundImageFile();

      Widget harness(ThemeController theme, SettingsController settings) =>
          MaterialApp(
            theme: theme.buildTheme(),
            home: ChangeNotifierProvider.value(
              value: settings,
              child: Scaffold(
                body: SizedBox(
                  width: 360,
                  child: TaskTile(
                    task: const Task(
                      id: 1,
                      title: 'Frosted card',
                      date: '2026-07-26',
                      startMinutes: 9 * 60,
                      endMinutes: 10 * 60,
                    ),
                    clock: () => now,
                    onEdit: () {},
                    onDelete: () {},
                    onToggleCompleted: () {},
                  ),
                ),
              ),
            ),
          );

      SharedPreferences.setMockInitialValues({});
      final plainTheme = ThemeController(
        settingsService: await SettingsService.create(),
        fileStorageService: FileStorageService(),
      );
      expect(plainTheme.palette.surfaceBlurred, isFalse);

      await tester.pumpWidget(
          harness(plainTheme, SettingsController(settingsService: await SettingsService.create())));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(BackdropFilter), findsNothing);

      SharedPreferences.setMockInitialValues({
        AppConstants.prefKeyBackgroundImage: image.path,
      });
      final photoTheme = ThemeController(
        settingsService: await SettingsService.create(),
        fileStorageService: FileStorageService(),
      );
      expect(photoTheme.palette.surfaceBlurred, isTrue);

      await tester.pumpWidget(
          harness(photoTheme, SettingsController(settingsService: await SettingsService.create())));
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
      expect(find.byType(BackdropFilter), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      photoTheme.dispose();
      plainTheme.dispose();
    });
  });

  group('SuggestionService', () {
    test('suggests conflict-free slots and avoids busy ranges', () async {
      final service = SuggestionService(
        repository: _FakeRepository(const []),
      );
      const busy = Task(
        id: 1,
        title: 'Standup',
        date: '2026-07-26',
        startMinutes: 9 * 60,
        endMinutes: 10 * 60,
      );

      final suggestions = await service.suggestFor(
        date: DateTime(2026, 7, 26),
        existing: const [busy],
      );

      expect(suggestions, isNotEmpty);
      for (final suggestion in suggestions) {
        final start =
            suggestion.start.hour * 60 + suggestion.start.minute;
        final end = suggestion.end.hour * 60 + suggestion.end.minute;
        final overlapsBusy =
            start < busy.endMinutes && busy.startMinutes < end;
        expect(overlapsBusy, isFalse,
            reason: 'suggested slot must not overlap existing tasks');
      }
    });

    test('prefers the block with the best completion history', () async {
      final history = [
        for (var i = 0; i < 5; i++)
          Task(
            id: 100 + i,
            title: 'Morning item $i',
            date: '2026-07-20',
            startMinutes: 8 * 60,
            endMinutes: 9 * 60,
          ),
        for (var i = 0; i < 5; i++)
          Task(
            id: 200 + i,
            title: 'Night item $i',
            date: '2026-07-20',
            startMinutes: 20 * 60,
            endMinutes: 21 * 60,
            isCompleted: true,
          ),
      ];
      final service = SuggestionService(
        repository: _FakeRepository(history),
      );

      final suggestions = await service.suggestFor(
        date: DateTime(2026, 7, 26),
        existing: const [],
      );

      expect(suggestions, isNotEmpty);
      final first = suggestions.first;
      final firstStart = first.start.hour * 60 + first.start.minute;
      expect(
        TimeSection.fromStartMinute(firstStart),
        TimeSection.night,
        reason: 'the most reliably completed block should rank first',
      );
    });
  });

  group('ActiveTaskRing flash logic', () {
    const base = AppPalette.lightBlue;

    test('keeps the base track color outside the final 30 seconds', () {
      expect(
        ActiveTaskRing.resolveRingColor(
          remaining: const Duration(minutes: 5),
          baseColor: base,
          flashPhase: 0.2,
        ),
        base,
      );
      expect(
        ActiveTaskRing.resolveRingColor(
          remaining: const Duration(seconds: 30),
          baseColor: base,
          flashPhase: 0.2,
        ),
        base,
      );
    });

    test('alternates solid green then solid white inside the final 30 seconds',
        () {
      expect(
        ActiveTaskRing.resolveRingColor(
          remaining: const Duration(seconds: 12),
          baseColor: base,
          flashPhase: 0.2,
        ),
        TaskTimeColors.imminentGreen,
      );
      expect(
        ActiveTaskRing.resolveRingColor(
          remaining: const Duration(seconds: 12),
          baseColor: base,
          flashPhase: 0.7,
        ),
        TaskTimeColors.flashWhite,
      );
    });

    test('stops flashing once the countdown reaches zero', () {
      expect(
        ActiveTaskRing.resolveRingColor(
          remaining: Duration.zero,
          baseColor: base,
          flashPhase: 0.2,
        ),
        base,
      );
    });
  });

  group('ActiveTaskRing phases', () {
    testWidgets('renders nothing once the task has begun (main time)',
        (tester) async {
      final now = DateTime(2026, 7, 26, 10, 0);
      const task = Task(
        id: 1,
        title: 'Deep work',
        date: '2026-07-26',
        startMinutes: 9 * 60,
        endMinutes: 10 * 60 + 30,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ActiveTaskRing(task: task, clock: () => now),
          ),
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.notifications_active_outlined), findsNothing);
      expect(find.byIcon(Icons.timer_outlined), findsNothing);
      expect(find.byIcon(Icons.timer_off_outlined), findsNothing);
      expect(find.textContaining('Main:'), findsNothing);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('renders nothing during extra time (no badge, no ring)',
        (tester) async {
      final now = DateTime(2026, 7, 26, 10, 0);
      const task = Task(
        id: 2,
        title: 'Overrunning task',
        date: '2026-07-26',
        startMinutes: 8 * 60,
        endMinutes: 9 * 60 + 30,
        delayMinutes: 60,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ActiveTaskRing(task: task, clock: () => now),
          ),
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.notifications_active_outlined), findsNothing);
      expect(find.byIcon(Icons.timer_outlined), findsNothing);
      expect(find.text('Main: 1h 30m'), findsNothing);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('pulses and shows the warning ring just before the start',
        (tester) async {
      final now = DateTime(2026, 7, 26, 8, 59, 40);
      const task = Task(
        id: 4,
        title: 'About to begin',
        date: '2026-07-26',
        startMinutes: 9 * 60,
        endMinutes: 10 * 60,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ActiveTaskRing(task: task, clock: () => now),
          ),
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.notifications_active_outlined), findsOneWidget);
      expect(find.byIcon(Icons.timer_outlined), findsNothing);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('renders nothing well before the start time', (tester) async {
      final now = DateTime(2026, 7, 26, 8, 0);
      const task = Task(
        id: 3,
        title: 'Later today',
        date: '2026-07-26',
        startMinutes: 9 * 60,
        endMinutes: 10 * 60,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ActiveTaskRing(task: task, clock: () => now),
          ),
        ),
      );

      expect(find.byIcon(Icons.timer_outlined), findsNothing);
      expect(find.byIcon(Icons.notifications_active_outlined), findsNothing);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('flash color alternates green and white during the window',
        (tester) async {
      final now = DateTime(2026, 7, 26, 8, 59, 40);
      const task = Task(
        id: 5,
        title: 'Flashing',
        date: '2026-07-26',
        startMinutes: 9 * 60,
        endMinutes: 10 * 60,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ActiveTaskRing(task: task, clock: () => now),
          ),
        ),
      );
      await tester.pump();

      Color ringColor() {
        final paint = tester.widgetList<CustomPaint>(find.byType(CustomPaint)).firstWhere(
              (p) =>
                  p.painter != null &&
                  p.painter.runtimeType.toString().contains('StopwatchRing'),
            );
        return (paint.painter! as dynamic).ringColor as Color;
      }

      final c0 = ringColor();
      await tester.pump(const Duration(milliseconds: 1200));
      final c1 = ringColor();
      await tester.pump(const Duration(milliseconds: 1000));
      final c2 = ringColor();

      expect(c0, isNot(c1), reason: 'flash must leave the green half');
      expect(c1, isNot(c2), reason: 'flash must return to green');

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a longer warning lead re-arms when settings change',
        (tester) async {
      var now = DateTime(2026, 7, 26, 8, 59, 0);
      const task = Task(
        id: 6,
        title: 'Lead change',
        date: '2026-07-26',
        startMinutes: 9 * 60,
        endMinutes: 10 * 60,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ActiveTaskRing(
              task: task,
              clock: () => now,
              warningWindow: const Duration(seconds: 10),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byIcon(Icons.notifications_active_outlined), findsNothing);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ActiveTaskRing(
              task: task,
              clock: () => now,
              warningWindow: const Duration(seconds: 90),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.notifications_active_outlined), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });
  });

  group('TaskProgressBar colour ramp', () {
    const cool = AppPalette.lightBlue;
    const hour = Duration(hours: 1);

    Color colorAt(Duration elapsed, {Duration total = hour}) =>
        TaskProgressBar.resolveColor(
          elapsed: elapsed,
          total: total,
        );

    test('starts at fixed green, isolated from appearance', () {
      expect(colorAt(Duration.zero), TaskProgressBar.startColor);
      expect(TaskProgressBar.startColor, isNot(cool));
    });

    test('red hold is proportional: 10% of total, capped at five minutes',
        () {
      expect(
        TaskProgressBar.redHoldFor(const Duration(hours: 1)),
        const Duration(minutes: 5),
      );
      expect(
        TaskProgressBar.redHoldFor(const Duration(minutes: 15)),
        const Duration(seconds: 90),
      );
    });

    test('reaches solid red at the proportional hold border', () {
      expect(colorAt(const Duration(minutes: 55)), TaskProgressBar.solidRed);
      expect(
        colorAt(const Duration(minutes: 26),
            total: const Duration(minutes: 30)),
        isNot(TaskProgressBar.solidRed),
      );
      expect(
        colorAt(const Duration(minutes: 27),
            total: const Duration(minutes: 30)),
        TaskProgressBar.solidRed,
      );
    });

    test('holds solid red through the final hold', () {
      expect(colorAt(const Duration(minutes: 57)), TaskProgressBar.solidRed);
      expect(
        colorAt(const Duration(minutes: 59, seconds: 59)),
        TaskProgressBar.solidRed,
      );
    });

    test('midpoint blends vivid (HSL), not muddy', () {
      final midpoint = colorAt(const Duration(minutes: 27, seconds: 30));
      expect(
          midpoint,
          HSLColor.lerp(
            HSLColor.fromColor(TaskProgressBar.startColor),
            HSLColor.fromColor(TaskProgressBar.solidRed),
            0.5,
          )!
              .toColor());
      expect(midpoint, isNot(TaskProgressBar.startColor));
      expect(midpoint, isNot(TaskProgressBar.solidRed));
    });

    test('a zero-length task starts red', () {
      expect(
        colorAt(Duration.zero, total: Duration.zero),
        TaskProgressBar.solidRed,
      );
    });

    test('remaining fraction depletes from full to empty and clamps', () {
      double fractionAt(Duration elapsed) =>
          TaskProgressBar.resolveRemainingFraction(
            elapsed: elapsed,
            total: hour,
          );

      expect(fractionAt(Duration.zero), 1.0);
      expect(fractionAt(const Duration(minutes: 30)), closeTo(0.5, 0.001));
      expect(fractionAt(hour), 0.0);
      expect(fractionAt(const Duration(minutes: 90)), 0.0);
    });
  });

  group('TaskSearchDelegate background', () {
    testWidgets('shows the app background image behind search results',
        (tester) async {
      final src = File('assets/icon/app_icon.png');
      final dst = File(
          '${Directory.systemTemp.path}${Platform.pathSeparator}bg_test.png');
      src.copySync(dst.path);
      addTearDown(() {
        if (dst.existsSync()) dst.deleteSync();
      });

      SharedPreferences.setMockInitialValues({
        AppConstants.prefKeyBackgroundImage: dst.path,
      });
      final settings = await SettingsService.create();
      final theme = ThemeController(
        settingsService: settings,
        fileStorageService: FileStorageService(),
      );
      final tasks = TaskListController(repository: _FakeRepository(const []));

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: theme),
            ChangeNotifierProvider.value(value: tasks),
          ],
          child: MaterialApp(
            theme: theme.buildTheme(),
            builder: (context, child) => ThemedBackground(
              child: child ?? const SizedBox.shrink(),
            ),
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => showSearch<Task?>(
                    context: context,
                    delegate: TaskSearchDelegate(tasks),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byType(ThemedBackground), findsOneWidget);
      final screen = tester.getSize(find.byType(MaterialApp));
      final box = tester.renderObject<RenderBox>(
        find.byType(ThemedBackground),
      );
      expect(box.localToGlobal(Offset.zero), Offset.zero);
      expect(box.size, screen);

      expect(
        Theme.of(tester.element(find.byType(Scaffold).last))
            .scaffoldBackgroundColor,
        Colors.transparent,
      );

      await tester.enterText(find.byType(TextField), 'standup');
      await tester.pumpAndSettle();

      await tester.pumpWidget(const SizedBox());
      tasks.dispose();
      theme.dispose();
    });
  });

  group('TaskProgressBar phases', () {
    const task = Task(
      id: 1,
      title: 'Focus block',
      date: '2026-07-26',
      startMinutes: 9 * 60,
      endMinutes: 10 * 60,
    );

    Future<void> pumpAt(WidgetTester tester, DateTime now) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TaskProgressBar(task: task, clock: () => now),
          ),
        ),
      );
    }

    testWidgets('renders the bar and remaining time while running',
        (tester) async {
      await pumpAt(tester, DateTime(2026, 7, 26, 9, 30));

      expect(find.byType(CustomPaint), findsWidgets);
      expect(find.text('30m left'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('renders nothing before the start or after the end',
        (tester) async {
      await pumpAt(tester, DateTime(2026, 7, 26, 8, 59));
      expect(find.textContaining('left'), findsNothing);

      await pumpAt(tester, DateTime(2026, 7, 26, 10, 1));
      expect(find.textContaining('left'), findsNothing);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a completed task shows no bar', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TaskProgressBar(
              task: task.copyWith(isCompleted: true),
              clock: () => DateTime(2026, 7, 26, 9, 30),
            ),
          ),
        ),
      );

      expect(find.textContaining('left'), findsNothing);

      await tester.pumpWidget(const SizedBox());
    });
  });

  group('TaskProgressBar placement inside the task card', () {
    testWidgets('sits directly under the start/end times', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings =
          SettingsController(settingsService: await SettingsService.create());
      await settings.setTaskFontScale(1.3);

      final now = DateTime(2026, 7, 26, 9, 30);
      const task = Task(
        id: 1,
        title: 'A deliberately long task title that wraps onto two lines',
        date: '2026-07-26',
        startMinutes: 9 * 60,
        endMinutes: 10 * 60,
        delayMinutes: 10,
        alarmEnabled: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider.value(
            value: settings,
            child: Scaffold(
              body: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 360,
                    child: TaskTile(
                      task: task,
                      clock: () => now,
                      onEdit: () {},
                      onDelete: () {},
                      onToggleCompleted: () {},
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);

      final card = tester.getRect(find.byType(Dismissible));
      final bar = tester.getRect(find.byType(TaskProgressBar));
      final timeRange = tester.getRect(find.textContaining(' - '));

      expect(bar.top, greaterThan(timeRange.bottom));
      expect(bar.top - timeRange.bottom, lessThan(20));
      expect(bar.left, greaterThan(card.left));
      expect(bar.right, lessThan(card.right));
      expect(bar.width, lessThan(card.width * 0.55));
      expect(bar.bottom, lessThan(card.bottom));

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('while running the card shows the bar only, never the ring',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings =
          SettingsController(settingsService: await SettingsService.create());

      final now = DateTime(2026, 7, 26, 9, 30);
      const task = Task(
        id: 2,
        title: 'Mid-run task',
        date: '2026-07-26',
        startMinutes: 9 * 60,
        endMinutes: 10 * 60,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider.value(
            value: settings,
            child: Scaffold(
              body: SizedBox(
                width: 360,
                child: TaskTile(
                  task: task,
                  clock: () => now,
                  onEdit: () {},
                  onDelete: () {},
                  onToggleCompleted: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(TaskProgressBar), findsOneWidget);
      expect(find.text('30m left'), findsOneWidget);
      expect(find.byIcon(Icons.notifications_active_outlined), findsNothing);
      expect(find.byIcon(Icons.timer_outlined), findsNothing);
      expect(find.byIcon(Icons.timer_off_outlined), findsNothing);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('at the exact start instant the ring hands off, never both',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings =
          SettingsController(settingsService: await SettingsService.create());

      var now = DateTime(2026, 7, 26, 8, 59, 59);
      const task = Task(
        id: 3,
        title: 'Handoff task',
        date: '2026-07-26',
        startMinutes: 9 * 60,
        endMinutes: 10 * 60,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider.value(
            value: settings,
            child: Scaffold(
              body: SizedBox(
                width: 360,
                child: TaskTile(
                  task: task,
                  clock: () => now,
                  onEdit: () {},
                  onDelete: () {},
                  onToggleCompleted: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.notifications_active_outlined), findsOneWidget);
      expect(find.textContaining('left'), findsNothing);

      now = DateTime(2026, 7, 26, 9, 0);
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.notifications_active_outlined), findsNothing);
      expect(find.byType(TaskProgressBar), findsOneWidget);
      expect(find.text('1h 00m left'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });
  });

  group('Appearance background swatches', () {
    testWidgets('every swatch, including the dark ones, is on screen at '
        'phone width', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final theme = ThemeController(
        settingsService: await SettingsService.create(),
        fileStorageService: FileStorageService(),
      );

      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: theme.buildTheme(),
          home: ChangeNotifierProvider.value(
            value: theme,
            child: const Scaffold(
              body: SingleChildScrollView(child: AppearanceSheet()),
            ),
          ),
        ),
      );
      await tester.pump();

      final screen = tester.view.physicalSize.width / tester.view.devicePixelRatio;
      for (final color in AppPalette.backgroundSwatches) {
        final finder = find.byKey(AppearanceSheet.backgroundSwatchKey(color));
        expect(finder, findsOneWidget, reason: 'swatch $color is missing');
        final rect = tester.getRect(finder);
        expect(rect.left, greaterThanOrEqualTo(0),
            reason: 'swatch $color starts off the left edge');
        expect(rect.right, lessThanOrEqualTo(screen),
            reason: 'swatch $color runs past the right edge');
      }

      final custom = find.byKey(AppearanceSheet.customBackgroundSwatchKey);
      expect(custom, findsOneWidget);
      expect(tester.getRect(custom).right, lessThanOrEqualTo(screen));

      expect(
        AppPalette.backgroundSwatches.where((c) =>
            ThemeData.estimateBrightnessForColor(c) == Brightness.dark),
        isNotEmpty,
      );
      expect(AppPalette.backgroundSwatches, contains(const Color(0xFF000000)));

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the details section is titled and every details swatch is '
        'reachable at phone width', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final theme = ThemeController(
        settingsService: await SettingsService.create(),
        fileStorageService: FileStorageService(),
      );

      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: theme.buildTheme(),
          home: ChangeNotifierProvider.value(
            value: theme,
            child: const Scaffold(
              body: SingleChildScrollView(child: AppearanceSheet()),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Details color'), findsOneWidget);
      expect(find.text('Background color'), findsOneWidget);

      final screen =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      for (final color in AppPalette.accentSwatches) {
        final finder = find.byKey(AppearanceSheet.accentSwatchKey(color));
        expect(finder, findsOneWidget, reason: 'accent $color is missing');
        final rect = tester.getRect(finder);
        expect(rect.left, greaterThanOrEqualTo(0),
            reason: 'accent $color starts off the left edge');
        expect(rect.right, lessThanOrEqualTo(screen),
            reason: 'accent $color runs past the right edge');
      }

      expect(AppPalette.accentSwatches.first,
          equals(AppConstants.defaultAccentColor));

      final customAccent =
          find.byKey(AppearanceSheet.customAccentSwatchKey);
      expect(customAccent, findsOneWidget);
      expect(tester.getRect(customAccent).right, lessThanOrEqualTo(screen));

      final rose = AppPalette.accentSwatches
          .firstWhere((c) => c.toARGB32() == const Color(0xFFD4708F).toARGB32());
      await tester.tap(find.byKey(AppearanceSheet.accentSwatchKey(rose)));
      await tester.pumpAndSettle();
      expect(theme.accentColor.toARGB32(), rose.toARGB32());
      expect(theme.palette.accent.toARGB32(), rose.toARGB32());

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the custom details wheel keeps the dragged colour when '
        'the finger lifts', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final theme = ThemeController(
        settingsService: await SettingsService.create(),
        fileStorageService: FileStorageService(),
      );
      final before = theme.accentColor;

      await tester.pumpWidget(
        MaterialApp(
          theme: theme.buildTheme(),
          home: ChangeNotifierProvider.value(
            value: theme,
            child: const Scaffold(
              body: SingleChildScrollView(child: AppearanceSheet()),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(AppearanceSheet.customAccentSwatchKey));
      await tester.pumpAndSettle();

      // the sheet once saved the colour from before it opened
      final wheel = tester.getRect(find.byType(ColorWheel));
      final gesture = await tester.startGesture(wheel.center);
      await gesture.moveBy(Offset(wheel.height / 4, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      final picked = HSVColor.fromAHSV(1, 0, 0.5, 1).toColor();
      expect(theme.accentColor.toARGB32(), picked.toARGB32());
      expect(theme.accentColor.toARGB32(), isNot(before.toARGB32()));

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(theme.accentColor.toARGB32(), picked.toARGB32());

      await tester.pumpWidget(const SizedBox());
      theme.dispose();
    });

    test('every offered details colour can carry legible text on top of it',
        () {
      for (final color in AppPalette.accentSwatches) {
        final palette = AppPalette.fromSeeds(
          accent: color,
          hasBackdropImage: false,
        );
        final gap = (color.computeLuminance() -
                palette.onAccent.computeLuminance())
            .abs();
        expect(gap, greaterThan(0.25), reason: 'accent $color is too close to '
            'its own foreground ${palette.onAccent}');
      }
    });
  });

  group('Note reveal', () {
    const noteText = 'Bring the signed contract and the blue folder.';
    final now = DateTime(2026, 7, 26, 9, 30);

    Future<Widget> harness(Task task) async {
      SharedPreferences.setMockInitialValues({});
      final settings =
          SettingsController(settingsService: await SettingsService.create());
      return MaterialApp(
        home: ChangeNotifierProvider.value(
          value: settings,
          child: Scaffold(
            body: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 360,
                  child: TaskTile(
                    task: task,
                    clock: () => now,
                    onEdit: () {},
                    onDelete: () {},
                    onToggleCompleted: () {},
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    const bare = Task(
      id: 1,
      title: 'No note here',
      date: '2026-07-26',
      startMinutes: 9 * 60,
      endMinutes: 10 * 60,
    );
    final annotated = bare.copyWith(id: 2, notes: noteText);

    testWidgets('a task without a note gains nothing at all', (tester) async {
      await tester.pumpWidget(await harness(bare));

      expect(find.byKey(NoteReveal.pullStripKey), findsNothing);
      expect(find.text(noteText), findsNothing);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a note shows only its page edge until it is opened',
        (tester) async {
      await tester.pumpWidget(await harness(annotated));
      await tester.pump();

      final closedHeight = tester.getSize(find.byType(NoteReveal)).height;
      final cardHeight = tester.getSize(find.byType(Dismissible)).height;

      expect(closedHeight - cardHeight, lessThan(12));
      expect(find.byKey(NoteReveal.pullStripKey), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('tapping the bottom edge unrolls the note', (tester) async {
      await tester.pumpWidget(await harness(annotated));
      await tester.pump();
      final closedHeight = tester.getSize(find.byType(NoteReveal)).height;

      await tester.tap(find.byKey(NoteReveal.pullStripKey));
      await tester.pumpAndSettle();

      final openHeight = tester.getSize(find.byType(NoteReveal)).height;
      expect(openHeight, greaterThan(closedHeight + 20));
      expect(find.text(noteText), findsOneWidget);

      await tester.tap(find.byKey(NoteReveal.pullStripKey));
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byType(NoteReveal)).height,
        closeTo(closedHeight, 1),
      );

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('pulling the edge down opens it, and a short pull springs '
        'back', (tester) async {
      await tester.pumpWidget(await harness(annotated));
      await tester.pump();
      final closedHeight = tester.getSize(find.byType(NoteReveal)).height;

      await tester.tap(find.byKey(NoteReveal.pullStripKey));
      await tester.pumpAndSettle();
      final travel =
          tester.getSize(find.byType(NoteReveal)).height - closedHeight;
      await tester.tap(find.byKey(NoteReveal.pullStripKey));
      await tester.pumpAndSettle();

      const slow = Duration(milliseconds: 300);
      double pull(double fraction) => kTouchSlop + travel * fraction;

      await tester.timedDrag(
          find.byKey(NoteReveal.pullStripKey), Offset(0, pull(0.6)), slow);
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byType(NoteReveal)).height,
        greaterThan(closedHeight + 20),
      );

      await tester.tap(find.byKey(NoteReveal.pullStripKey));
      await tester.pumpAndSettle();
      await tester.timedDrag(
          find.byKey(NoteReveal.pullStripKey), Offset(0, pull(0.2)), slow);
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byType(NoteReveal)).height,
        closeTo(closedHeight, 1),
      );

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the silent affordance is announced to a screen reader',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(await harness(annotated));
      await tester.pump();

      SemanticsData data() => tester
          .getSemantics(find.byKey(NoteReveal.pullStripKey))
          .getSemanticsData();

      expect(data().label, 'Show note');
      expect(data().flagsCollection.isButton, isTrue);
      expect(data().flagsCollection.isExpanded, Tristate.isFalse);
      expect(data().hasAction(SemanticsAction.tap), isTrue);

      expect(find.text(annotated.title), findsOneWidget);

      await tester.tap(find.byKey(NoteReveal.pullStripKey));
      await tester.pumpAndSettle();
      expect(data().label, 'Hide note');
      expect(data().flagsCollection.isExpanded, Tristate.isTrue);

      await tester.pumpWidget(const SizedBox());
      semantics.dispose();
    });
  });

  group('Subtasks', () {
    final now = DateTime(2026, 7, 26, 9, 30);

    Task checklistTask(String notes) => Task(
          id: 1,
          title: 'Birthday shopping',
          date: '2026-07-26',
          startMinutes: 9 * 60,
          endMinutes: 10 * 60,
          notes: notes,
        );

    Future<Widget> harness(Task task, ValueChanged<Task>? onChanged) async {
      SharedPreferences.setMockInitialValues({});
      final settings =
          SettingsController(settingsService: await SettingsService.create());
      return MaterialApp(
        home: ChangeNotifierProvider.value(
          value: settings,
          child: Scaffold(
            body: SizedBox(
              width: 360,
              child: TaskTile(
                task: task,
                clock: () => now,
                onEdit: () {},
                onDelete: () {},
                onToggleCompleted: () {},
                onChecklistChanged: onChanged,
              ),
            ),
          ),
        ),
      );
    }

    test('parses checklist syntax and keeps prose out of it', () {
      const note = 'Remember the cake\n'
          '- [ ] Blue tape\n'
          '- [x] Wrapping paper\n'
          'Just prose, not a subtask\n'
          '- [ ] Ribbon';
      final task = checklistTask(note);
      expect(task.hasChecklist, isTrue);
      final items = task.subtasks;
      expect(items.length, 3);
      expect(items[0].text, 'Blue tape');
      expect(items[0].isDone, isFalse);
      expect(items[1].text, 'Wrapping paper');
      expect(items[1].isDone, isTrue);
      expect(task.doneSubtaskCount, 1);
    });

    test('writeBack preserves prose, order and checked state', () {
      const note = 'Top prose\n- [ ] a\nMiddle prose\n- [x] b\n- [ ] c';
      final rewritten = Subtasks.writeBack(note, [
        const Subtask(text: 'a', isDone: true),
        const Subtask(text: 'renamed', isDone: false),
      ]);
      expect(rewritten,
          'Top prose\n- [x] a\n- [ ] renamed\nMiddle prose');
    });

    test('writeBack with no items removes the checklist, keeps prose', () {
      const note = 'Prose survives\n- [ ] a\n- [x] b';
      expect(Subtasks.writeBack(note, []), 'Prose survives');
    });

    test('writeBack onto a prose-only note appends the checklist', () {
      const note = 'Only prose';
      expect(Subtasks.writeBack(note, [const Subtask(text: 'new')]),
          'Only prose\n- [ ] new');
    });

    testWidgets('a checklist note renders tappable rows and the ✓ badge',
        (tester) async {
      String? savedNotes;
      final task = checklistTask(
          'Plan\n- [ ] Blue tape\n- [x] Wrapping paper\n- [ ] Ribbon');

      await tester.pumpWidget(await harness(task, (updated) {
        savedNotes = updated.notes;
      }));
      await tester.pump();

      expect(find.text('✓ 1/3'), findsOneWidget);

      await tester.tap(find.byKey(NoteReveal.pullStripKey));
      await tester.pumpAndSettle();

      expect(find.text('Blue tape'), findsOneWidget);
      expect(find.text('Wrapping paper'), findsOneWidget);
      expect(find.text('Ribbon'), findsOneWidget);
      expect(find.byKey(NoteReveal.editSubtasksKey), findsOneWidget);

      await tester.tap(find.text('Blue tape'));
      await tester.pumpAndSettle();
      expect(savedNotes,
          'Plan\n- [x] Blue tape\n- [x] Wrapping paper\n- [ ] Ribbon');

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the subtask editor edits, deletes and adds rows',
        (tester) async {
      String? savedNotes;
      final task = checklistTask('Plan\n- [ ] Blue tape\n- [x] Wrapping paper');

      await tester.pumpWidget(await harness(task, (updated) {
        savedNotes = updated.notes;
      }));
      await tester.pump();
      await tester.tap(find.byKey(NoteReveal.pullStripKey));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(NoteReveal.editSubtasksKey));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(TextField, 'Blue tape'), 'Blue duck tape');
      await tester.tap(find.text('Add subtask'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextField, '').last, 'Cake pickup');
      await tester.tap(find.widgetWithIcon(IconButton, Icons.delete_outline)
          .at(1));

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(savedNotes,
          'Plan\n- [ ] Blue duck tape\n- [ ] Cake pickup');

      await tester.pumpWidget(const SizedBox());
    });
  });

  group('Add / Edit subtasks', () {
    testWidgets('the editor builds subtasks through their own field, not '
        'typed syntax', (tester) async {
      // the eager dials swallow scroll drags so give the test a tall screen
      tester.view.physicalSize = const Size(800, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      SharedPreferences.setMockInitialValues({});
      final settings =
          SettingsController(settingsService: await SettingsService.create());
      final repository = _FakeRepository(const []);
      final tasks = TaskListController(
        repository: repository,
        alarmService: AlarmService(repository: repository),
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: settings),
            ChangeNotifierProvider.value(value: tasks),
          ],
          child: MaterialApp(
            home: AddEditTaskScreen(
              initialDate: DateTime(2026, 7, 26),
              suggestionService: SuggestionService(repository: repository),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(TextField, 'What do you want to do?'),
          'Store run');
      await tester.enterText(
          find.widgetWithText(TextField, 'Add a subtask'), 'Buy legumes');
      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();
      await tester.enterText(
          find.widgetWithText(TextField, 'Add a subtask'), 'Buy meat');
      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();

      expect(find.text('Buy legumes'), findsOneWidget);
      expect(find.text('Buy meat'), findsOneWidget);
      final notesField = find.widgetWithText(TextField, 'Notes (optional)');
      expect(tester.widget<TextField>(notesField).controller!.text, '');

      await tester.tap(find.text('Buy legumes'));
      await tester.pump();

      await tester.tap(find.text('Create Task'));
      await tester.pumpAndSettle();

      final saved = repository.tasks.single;
      expect(saved.title, 'Store run');
      expect(saved.notes, '- [x] Buy legumes\n- [ ] Buy meat');
      expect(saved.isCompleted, isFalse);

      await tester.pumpWidget(const SizedBox());
      tasks.dispose();
    });

    testWidgets('deleting a subtask row removes it from the saved note',
        (tester) async {
      tester.view.physicalSize = const Size(800, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      SharedPreferences.setMockInitialValues({});
      final settings =
          SettingsController(settingsService: await SettingsService.create());
      final repository = _FakeRepository(const []);
      final tasks = TaskListController(
        repository: repository,
        alarmService: AlarmService(repository: repository),
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: settings),
            ChangeNotifierProvider.value(value: tasks),
          ],
          child: MaterialApp(
            home: AddEditTaskScreen(
              initialDate: DateTime(2026, 7, 26),
              suggestionService: SuggestionService(repository: repository),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(TextField, 'What do you want to do?'),
          'Store run');
      await tester.enterText(
          find.widgetWithText(TextField, 'Add a subtask'), 'Buy legumes');
      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();
      await tester.enterText(
          find.widgetWithText(TextField, 'Add a subtask'), 'Buy meat');
      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.delete_outline).first);
      await tester.pump();
      expect(find.text('Buy legumes'), findsNothing);

      await tester.tap(find.text('Create Task'));
      await tester.pumpAndSettle();

      expect(repository.tasks.single.notes, '- [ ] Buy meat');

      await tester.pumpWidget(const SizedBox());
      tasks.dispose();
    });
  });

  group('Checklist-driven completion', () {
    test('a task completes itself once every subtask is ticked, and a '
        'cleared subtask reopens it', () async {
      final repository = _FakeRepository(const []);
      final controller = TaskListController(
        repository: repository,
        alarmService: AlarmService(repository: repository),
      );

      final created = await controller.saveTask(const Task(
        title: 'Store run',
        date: '2026-07-26',
        startMinutes: 9 * 60,
        endMinutes: 10 * 60,
        notes: '- [ ] Legumes\n- [x] Meat',
      ));
      expect(created.isCompleted, isFalse,
          reason: 'one subtask is still unticked');

      final finished = await controller.saveTask(
          created.copyWith(notes: '- [x] Legumes\n- [x] Meat'));
      expect(finished.isCompleted, isTrue,
          reason: 'ticking the last subtask must complete the task');

      final reopened = await controller.saveTask(
          finished.copyWith(notes: '- [ ] Legumes\n- [x] Meat'));
      expect(reopened.isCompleted, isFalse,
          reason: 'clearing a subtask must reopen a completed task');

      controller.dispose();
    });

    test('tasks without a checklist keep their manual completion state',
        () async {
      final repository = _FakeRepository(const []);
      final controller = TaskListController(
        repository: repository,
        alarmService: AlarmService(repository: repository),
      );

      final saved = await controller.saveTask(const Task(
        title: 'Plain task',
        date: '2026-07-26',
        startMinutes: 9 * 60,
        endMinutes: 10 * 60,
      ));
      expect(saved.isCompleted, isFalse);

      final manual = await controller.saveTask(
          saved.copyWith(isCompleted: true));
      expect(manual.isCompleted, isTrue,
          reason: 'no checklist means the rule never interferes');

      controller.dispose();
    });
  });

  group('Deferred deletion with undo window', () {
    Task taskForToday(int id, String title) {
      final today = DateTime.now();
      final date = '${today.year.toString().padLeft(4, '0')}-'
          '${today.month.toString().padLeft(2, '0')}-'
          '${today.day.toString().padLeft(2, '0')}';
      return Task(
        id: id,
        title: title,
        date: date,
        startMinutes: 9 * 60,
        endMinutes: 10 * 60,
      );
    }

    test('hides the task immediately but keeps the database row', () async {
      final task = taskForToday(1, 'Rescuable');
      final repository = _FakeRepository([task]);
      final controller = TaskListController(
        repository: repository,
        alarmService: AlarmService(repository: repository),
        undoGracePeriod: const Duration(minutes: 5),
      );

      await controller.loadTasks();
      expect(controller.isEmpty, isFalse);

      await controller.deleteTaskDeferred(task);
      expect(controller.isEmpty, isTrue,
          reason: 'the task must vanish from the visible list at once');
      expect(repository.deletedIds, isEmpty,
          reason: 'the row must not be deleted during the grace window');

      controller.dispose();
    });

    test('undo restores the task to its original list position', () async {
      final first = taskForToday(1, 'First');
      final second = taskForToday(2, 'Second')
          .copyWith(startMinutes: 11 * 60, endMinutes: 12 * 60);
      final repository = _FakeRepository([first, second]);
      final controller = TaskListController(
        repository: repository,
        alarmService: AlarmService(repository: repository),
        undoGracePeriod: const Duration(minutes: 5),
      );

      await controller.loadTasks();
      await controller.deleteTaskDeferred(first);

      final rescued = await controller.undoDeleteTask(first);
      expect(rescued, isTrue);
      expect(repository.deletedIds, isEmpty);

      final visible = controller.groupedTasks.values
          .expand((tasks) => tasks)
          .map((t) => t.id)
          .toList();
      expect(visible, [1, 2],
          reason: 'the rescued task returns in chronological order');
      expect(controller.shouldAnimateRestore(1), isTrue);
      expect(controller.shouldAnimateRestore(2), isFalse);

      controller.dispose();
    });

    test('commits the deletion after the grace window elapses', () async {
      final task = taskForToday(1, 'Doomed');
      final repository = _FakeRepository([task]);
      final controller = TaskListController(
        repository: repository,
        alarmService: AlarmService(repository: repository),
        undoGracePeriod: const Duration(milliseconds: 40),
      );

      await controller.loadTasks();
      await controller.deleteTaskDeferred(task);
      var committed = false;
      for (var i = 0; i < 100 && !committed; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        committed = repository.softDeletedIds.contains(1);
      }
      expect(committed, isTrue,
          reason: 'the expired window must move the row to the Trash');
      expect(await controller.undoDeleteTask(task), isFalse,
          reason: 'undo after the window closed must report failure');

      controller.dispose();
    });
  });

  group('UndoCountdownRing', () {
    testWidgets('counts down from five and depletes to zero',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: UndoCountdownRing(duration: Duration(seconds: 5)),
          ),
        ),
      );

      expect(find.text('5'), findsOneWidget);

      await tester.pump(const Duration(seconds: 2));
      expect(find.text('3'), findsOneWidget);

      await tester.pump(const Duration(seconds: 3));
      expect(find.text('0'), findsOneWidget);
    });
  });

  group('Audio format validation', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('audio_test');
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    Future<File> writeFile(String name, List<int> bytes) async {
      final file = File('${tempDir.path}/$name');
      await file.writeAsBytes(bytes);
      return file;
    }

    test('accepts files with valid audio signatures', () async {
      final mp3 = await writeFile('song.mp3', [
        ...'ID3'.codeUnits,
        ...List.filled(13, 0),
      ]);
      final wav = await writeFile('tone.wav', [
        ...'RIFF'.codeUnits,
        0, 0, 0, 0,
        ...'WAVE'.codeUnits,
        ...List.filled(4, 0),
      ]);
      final ogg = await writeFile('clip.ogg', [
        ...'OggS'.codeUnits,
        ...List.filled(12, 0),
      ]);

      expect(await FileStorageService.isLikelyAudioFile(mp3), isTrue);
      expect(await FileStorageService.isLikelyAudioFile(wav), isTrue);
      expect(await FileStorageService.isLikelyAudioFile(ogg), isTrue);
    });

    test('rejects mislabelled and unsupported files', () async {
      final fake = await writeFile(
          'not_audio.mp3', 'hello world, not audio'.codeUnits);
      final wrongExt = await writeFile('script.txt', [
        ...'ID3'.codeUnits,
        ...List.filled(13, 0),
      ]);
      final empty = await writeFile('empty.wav', const []);

      expect(await FileStorageService.isLikelyAudioFile(fake), isFalse);
      expect(await FileStorageService.isLikelyAudioFile(wrongExt), isFalse);
      expect(await FileStorageService.isLikelyAudioFile(empty), isFalse);
    });
  });

  group('Stored audio display names', () {
    test('the import timestamp is hidden from the label', () {
      expect(
        FileStorageService.displayName('/data/alarm_audio/1756869123456_song.mp3'),
        'song',
      );
      expect(
        FileStorageService.displayName(
            '/data/alarm_audio/1756869123456_My Track (final).m4a'),
        'My Track (final)',
      );
    });

    test('names that only look timestamped are left intact', () {
      expect(FileStorageService.displayName('/a/123_song.mp3'), '123_song');
      expect(FileStorageService.displayName('/a/song.mp3'), 'song');
      expect(
        FileStorageService.displayName('/a/1756869123456_.mp3'),
        '1756869123456_',
      );
    });
  });

  group('Orphaned alarm audio pruning', () {
    late Directory docsDir;
    late FileStorageService storage;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      docsDir = await Directory.systemTemp.createTemp('prune_test');
      storage = FileStorageService();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => docsDir.path,
      );
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        null,
      );
      await docsDir.delete(recursive: true);
    });

    Future<File> storedFile(String name) async {
      final dir = Directory('${docsDir.path}/alarm_audio');
      await dir.create(recursive: true);
      final file = File('${dir.path}/$name');
      await file.writeAsBytes(<int>[...'ID3'.codeUnits, ...List.filled(13, 0)]);
      return file;
    }

    test('files no task references are reclaimed, referenced ones are kept',
        () async {
      final kept = await storedFile('1756869123456_kept.mp3');
      final orphan = await storedFile('1756869123457_orphan.mp3');

      final removed = await storage.pruneUnusedAlarmAudio({kept.path});

      expect(removed, 1);
      expect(await kept.exists(), isTrue);
      expect(await orphan.exists(), isFalse);
    });

    test('an empty reference set clears the folder', () async {
      await storedFile('1756869123456_a.mp3');
      await storedFile('1756869123457_b.mp3');

      expect(await storage.pruneUnusedAlarmAudio(const {}), 2);
      expect(await storage.listAlarmAudioFiles(), isEmpty);
    });

    test('references are compared normalised, not as raw strings', () async {
      final kept = await storedFile('1756869123456_kept.mp3');
      final awkward = '${docsDir.path}/alarm_audio/./1756869123456_kept.mp3';

      expect(await storage.pruneUnusedAlarmAudio({awkward}), 0);
      expect(await kept.exists(), isTrue);
    });
  });

  group('Alarm sound picker sheet', () {
    const channel =
        MethodChannel('com.morphinealonely.advanced_todo_list/ringtones');
    late List<String> calls;
    late List<Map<String, String>> catalogue;

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      calls = [];
      catalogue = [
        {'title': 'Argon', 'uri': 'content://media/alarm/1'},
        {'title': 'Helium', 'uri': 'content://media/alarm/2'},
      ];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (call.method == 'list') return catalogue;
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    Future<void> openSheet(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showSoundPickerSheet(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    Future<void> reportPreviewComplete(WidgetTester tester, String uri) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(MethodCall('onPreviewComplete', uri)),
        (_) {},
      );
      await tester.pump();
    }

    testWidgets('a preview that ends on its own resets the toggle',
        (tester) async {
      await openSheet(tester);
      expect(find.text('Argon'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.play_circle_outline).first);
      await tester.pumpAndSettle();
      expect(calls, contains('play'));
      expect(find.byIcon(Icons.stop_circle_outlined), findsOneWidget);

      await reportPreviewComplete(tester, 'content://media/alarm/1');
      expect(find.byIcon(Icons.stop_circle_outlined), findsNothing);
      expect(find.byIcon(Icons.play_circle_outline), findsNWidgets(2));
    });

    testWidgets('a completion for a different sound leaves the toggle alone',
        (tester) async {
      await openSheet(tester);
      await tester.tap(find.byIcon(Icons.play_circle_outline).first);
      await tester.pumpAndSettle();

      await reportPreviewComplete(tester, 'content://media/alarm/2');
      expect(find.byIcon(Icons.stop_circle_outlined), findsOneWidget);
    });

    testWidgets('an empty catalogue can be retried in place', (tester) async {
      catalogue = [];
      await openSheet(tester);

      expect(find.text('No system ringtones available on this device.'),
          findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);

      catalogue = [
        {'title': 'Argon', 'uri': 'content://media/alarm/1'},
      ];
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(find.text('Argon'), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
      expect(calls.where((call) => call == 'list').length, 2);
    });

    testWidgets('the default option no longer promises a notification sound',
        (tester) async {
      await openSheet(tester);
      expect(find.text("Use the app's built-in alarm tone"), findsOneWidget);
      expect(find.text('Follow the system notification sound'), findsNothing);
    });
  });

  group('DelayClock', () {
    testWidgets('shows the selected overtime minutes in the centre',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DelayClock(minutes: 25, onChanged: (_) {}),
          ),
        ),
      );

      expect(find.text('+25'), findsOneWidget);
      expect(find.text('overtime minutes'), findsOneWidget);
    });
  });

  group('External picker excursions', () {
    setUp(ExternalPicker.resetForTesting);
    tearDown(ExternalPicker.resetForTesting);

    test('the flag is raised only while a pick is in flight', () async {
      expect(ExternalPicker.isActive, isFalse);

      final gate = Completer<void>();
      final pick = ExternalPicker.run(() async {
        expect(ExternalPicker.isActive, isTrue);
        await gate.future;
        return 'picked';
      });

      expect(ExternalPicker.isActive, isTrue);
      gate.complete();
      expect(await pick, 'picked');
      expect(ExternalPicker.isActive, isTrue);
    });

    test('a throwing picker still clears the flag', () async {
      await expectLater(
        ExternalPicker.run(() async => throw StateError('picker blew up')),
        throwsStateError,
      );
      ExternalPicker.resetForTesting();
      expect(ExternalPicker.isActive, isFalse);
    });

    test('overlapping picks do not clear the flag early', () async {
      final inner = Completer<void>();
      final outer = Completer<void>();

      final first = ExternalPicker.run(() => outer.future);
      final second = ExternalPicker.run(() => inner.future);

      inner.complete();
      await second;
      expect(ExternalPicker.isActive, isTrue);
      outer.complete();
      await first;
    });

    test('being foregrounded again ends the settling tail immediately',
        () async {
      await ExternalPicker.run(() async => 'picked');
      expect(ExternalPicker.isActive, isTrue);

      ExternalPicker.noteResumed();
      expect(ExternalPicker.isActive, isFalse);
    });

    test('a resume during a pick does not lower the flag', () async {
      final gate = Completer<void>();
      final pick = ExternalPicker.run(() => gate.future);

      ExternalPicker.noteResumed();
      expect(ExternalPicker.isActive, isTrue);

      gate.complete();
      await pick;
      expect(ExternalPicker.isActive, isTrue);
    });
  });

  group('Task text size live preview', () {
    testWidgets('sample task title resizes as the slider moves',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsController(
        settingsService: await SettingsService.create(),
      );
      final theme = ThemeController(
        settingsService: await SettingsService.create(),
        fileStorageService: FileStorageService(),
      );

      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final previousOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.exceptionAsString().contains('ListTile background color')) {
          return;
        }
        previousOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = previousOnError);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: theme),
            ChangeNotifierProvider.value(value: settings),
          ],
          child: MaterialApp(
            theme: theme.buildTheme(),
            home: const SettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final sampleTitle = find.byKey(
        const ValueKey('task-text-size-preview-title'),
      );
      await tester.scrollUntilVisible(
        sampleTitle,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(sampleTitle, findsOneWidget);

      double sampleFontSize() =>
          tester.widget<Text>(sampleTitle).style?.fontSize ?? 0;

      expect(settings.taskFontScale, 1.0);
      expect(sampleFontSize(), closeTo(15.5, 0.01));

      final slider = find.byWidgetPredicate(
        (w) => w is Slider && w.min == 0.85 && w.max == 1.3,
      );
      expect(slider, findsOneWidget);

      await tester.drag(slider, const Offset(500, 0));
      await tester.pumpAndSettle();

      expect(settings.taskFontScale, 1.3);
      expect(sampleFontSize(), closeTo(15.5 * 1.3, 0.01));

      await tester.drag(slider, const Offset(-500, 0));
      await tester.pumpAndSettle();

      expect(settings.taskFontScale, 0.85);
      expect(sampleFontSize(), closeTo(15.5 * 0.85, 0.01));

      await tester.pumpWidget(const SizedBox());
    });
  });
}
