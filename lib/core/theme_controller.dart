import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/file_storage_service.dart';
import '../services/settings_service.dart';
import 'app_palette.dart';

class ThemeController extends ChangeNotifier {
  ThemeController({
    required SettingsService settingsService,
    required FileStorageService fileStorageService,
  })  : _settings = settingsService,
        _fileStorage = fileStorageService,
        _accentColor = settingsService.loadAccentColor(),
        _backgroundImagePath = settingsService.loadBackgroundImagePath(),
        _backgroundColor = settingsService.loadBackgroundColor() {
    _validateBackgroundPath();
    _rebuildPalette();
  }

  final SettingsService _settings;
  final FileStorageService _fileStorage;

  Color _accentColor;
  String? _backgroundImagePath;
  Color? _backgroundColor;
  late AppPalette _palette;

  DateTime _lastPreviewNotify = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _previewThrottle = Duration(milliseconds: 16);

  bool get isLivePreview => _isLivePreview;
  bool _isLivePreview = false;

  Color get accentColor => _accentColor;

  AppPalette get palette => _palette;

  String? get backgroundImagePath => _backgroundImagePath;

  bool get hasCustomBackground => _backgroundImagePath != null;

  Color? get backgroundColor => _backgroundColor;

  Future<void> setBackgroundColor(Color? color) async {
    _backgroundColor = color;
    _isLivePreview = false;
    _rebuildPalette();
    notifyListeners();
    await _settings.saveBackgroundColor(color);
  }

  void previewBackgroundColor(Color color) {
    if (_backgroundColor == color) return;
    _backgroundColor = color;
    _isLivePreview = true;
    _rebuildPalette();

    final now = DateTime.now();
    if (now.difference(_lastPreviewNotify) >= _previewThrottle) {
      _lastPreviewNotify = now;
      notifyListeners();
    }
  }

  void previewAccentColor(Color color) {
    if (color == _accentColor) return;
    _accentColor = color;
    _isLivePreview = true;
    _rebuildPalette();

    final now = DateTime.now();
    if (now.difference(_lastPreviewNotify) >= _previewThrottle) {
      _lastPreviewNotify = now;
      notifyListeners();
    }
  }

  Future<void> commitAccentColor(Color color) async {
    _accentColor = color;
    _isLivePreview = false;
    _rebuildPalette();
    notifyListeners();
    await _settings.saveAccentColor(color);
  }

  Future<bool> pickBackgroundImage() async {
    final storedPath = await _fileStorage.pickAndStoreBackgroundImage();
    if (storedPath == null) return false;

    _backgroundImagePath = storedPath;
    _rebuildPalette();
    notifyListeners();
    await _settings.saveBackgroundImagePath(storedPath);
    return true;
  }

  Future<void> clearBackgroundImage() async {
    await _fileStorage.deleteBackgroundImage();
    _backgroundImagePath = null;
    _rebuildPalette();
    notifyListeners();
    await _settings.saveBackgroundImagePath(null);
  }

  ThemeData buildTheme() {
    final palette = _palette;
    final surfaceIsLight =
        ThemeData.estimateBrightnessForColor(palette.surfaceElevated) ==
            Brightness.light;

    final scheme = ColorScheme.fromSeed(
      seedColor: palette.accent,
      brightness: surfaceIsLight ? Brightness.light : Brightness.dark,
      primary: palette.accent,
      secondary: palette.support,
    );

    final backdropIsLight =
        ThemeData.estimateBrightnessForColor(palette.onBackdrop) ==
            Brightness.dark;

    // a fill here would hide under the blur
    final frosted = palette.surfaceBlurred;

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.transparent,
      extensions: [palette],
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        foregroundColor: palette.onBackdrop,
        titleTextStyle: TextStyle(
          color: palette.onBackdrop,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
        ),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness:
              backdropIsLight ? Brightness.dark : Brightness.light,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarIconBrightness:
              backdropIsLight ? Brightness.dark : Brightness.light,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: palette.accent,
        foregroundColor: palette.onAccent,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: palette.surfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: palette.inverseSurface,
        contentTextStyle: TextStyle(color: palette.onInverseSurface),
        actionTextColor: palette.accent,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor:
            frosted ? Colors.transparent : palette.surfaceElevated,
        surfaceTintColor: frosted ? Colors.transparent : null,
        elevation: frosted ? 0 : null,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor:
            frosted ? Colors.transparent : palette.surfaceElevated,
        surfaceTintColor: frosted ? Colors.transparent : null,
        elevation: frosted ? 0 : null,
      ),
    );
  }

  void _rebuildPalette() {
    _palette = AppPalette.fromSeeds(
      accent: _accentColor,
      hasBackdropImage: _backgroundImagePath != null,
      backgroundColor: _backgroundColor,
    );
  }

  void _validateBackgroundPath() {
    final path = _backgroundImagePath;
    if (path != null && !File(path).existsSync()) {
      _backgroundImagePath = null;
    }
  }
}
