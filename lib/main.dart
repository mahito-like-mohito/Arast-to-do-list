import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'controllers/settings_controller.dart';
import 'controllers/task_list_controller.dart';
import 'core/theme_controller.dart';
import 'services/alarm_service.dart';
import 'services/file_storage_service.dart';
import 'services/maintenance_service.dart';
import 'services/settings_service.dart';
import 'ui/screens/home_screen.dart';
import 'ui/widgets/lock_gate.dart';
import 'ui/widgets/themed_background.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  await AlarmService.initialize();

  final settingsService = await SettingsService.create();
  final themeController = ThemeController(
    settingsService: settingsService,
    fileStorageService: FileStorageService(),
  );
  final settingsController =
      SettingsController(settingsService: settingsService);
  settingsController.onAlarmSettingsChanged =
      () => AlarmService().rescheduleAllPending();

  final taskListController = TaskListController();
  unawaited(
    MaintenanceService()
        .runStartupSweep(settingsController)
        .then((_) => taskListController.loadTasks())
        .then((_) => AlarmService().rescheduleAllPending()),
  );

  runApp(
    AdvancedTodoApp(
      themeController: themeController,
      taskListController: taskListController,
      settingsController: settingsController,
    ),
  );
}

class AdvancedTodoApp extends StatelessWidget {
  const AdvancedTodoApp({
    super.key,
    required this.themeController,
    required this.taskListController,
    required this.settingsController,
  });

  final ThemeController themeController;
  final TaskListController taskListController;
  final SettingsController settingsController;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: themeController),
        ChangeNotifierProvider.value(value: taskListController),
        ChangeNotifierProvider.value(value: settingsController),
      ],
      child: Consumer<ThemeController>(
        builder: (context, controller, _) {
          return MaterialApp(
            title: 'Arast',
            debugShowCheckedModeBanner: false,
            theme: controller.buildTheme(),
            themeAnimationDuration: controller.isLivePreview
                ? Duration.zero
                : const Duration(milliseconds: 420),
            themeAnimationCurve: Curves.easeInOutCubic,
            builder: (context, child) => ThemedBackground(
              child: child ?? const SizedBox.shrink(),
            ),
            home: const LockGate(child: HomeScreen()),
          );
        },
      ),
    );
  }
}
