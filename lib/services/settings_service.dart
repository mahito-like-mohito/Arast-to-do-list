import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';

class SettingsService {
  SettingsService(this._prefs);

  final SharedPreferences _prefs;

  static Future<SettingsService> create() async {
    return SettingsService(await SharedPreferences.getInstance());
  }

  Color loadAccentColor() {
    final stored = _prefs.getInt(AppConstants.prefKeyAccentColor);
    return stored == null ? AppConstants.defaultAccentColor : Color(stored);
  }

  Future<void> saveAccentColor(Color color) async {
    await _prefs.setInt(AppConstants.prefKeyAccentColor, color.toARGB32());
  }

  String? loadBackgroundImagePath() {
    return _prefs.getString(AppConstants.prefKeyBackgroundImage);
  }

  Future<void> saveBackgroundImagePath(String? path) async {
    if (path == null) {
      await _prefs.remove(AppConstants.prefKeyBackgroundImage);
    } else {
      await _prefs.setString(AppConstants.prefKeyBackgroundImage, path);
    }
  }

  Color? loadBackgroundColor() {
    final stored = _prefs.getInt(AppConstants.prefKeyBackgroundColor);
    return stored == null ? null : Color(stored);
  }

  Future<void> saveBackgroundColor(Color? color) async {
    if (color == null) {
      await _prefs.remove(AppConstants.prefKeyBackgroundColor);
    } else {
      await _prefs.setInt(AppConstants.prefKeyBackgroundColor, color.toARGB32());
    }
  }

  bool loadBool(String key, bool fallback) =>
      _prefs.getBool(key) ?? fallback;

  int loadInt(String key, int fallback) => _prefs.getInt(key) ?? fallback;

  double loadDouble(String key, double fallback) =>
      _prefs.getDouble(key) ?? fallback;

  String loadString(String key, String fallback) =>
      _prefs.getString(key) ?? fallback;

  Future<void> saveBool(String key, bool value) =>
      _prefs.setBool(key, value);

  Future<void> saveInt(String key, int value) => _prefs.setInt(key, value);

  Future<void> saveDouble(String key, double value) =>
      _prefs.setDouble(key, value);

  Future<void> saveString(String key, String value) =>
      _prefs.setString(key, value);
}
