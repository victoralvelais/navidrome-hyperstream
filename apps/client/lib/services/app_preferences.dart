import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Non-secret preferences only. Credentials never enter this store.
/// A single JSON value keeps mute and its restore level together.
class AppPreferences extends ChangeNotifier {
  AppPreferences({this._save});

  static const storageKey = 'hyperstream.preferences.v1';
  final Future<void> Function(String)? _save;
  Future<void> _pending = Future.value();
  double volume = 1;
  double audibleVolume = 1;
  bool mixWithOthers = false;
  ThemeMode themeMode = ThemeMode.system;
  String? notice;

  static Future<AppPreferences> load() async {
    final storage = SharedPreferencesAsync();
    final preferences = AppPreferences(
      save: (json) => storage.setString(storageKey, json),
    );
    try {
      final json = await storage.getString(storageKey);
      if (json != null) preferences.restore(json);
    } on Object {
      preferences.notice = 'Saved settings could not be read. Using defaults.';
    }
    return preferences;
  }

  void restore(String json) {
    final data = jsonDecode(json) as Map<String, dynamic>;
    double level(Object? value, double fallback) =>
        value is num && value.isFinite
        ? value.toDouble().clamp(0, 1)
        : fallback;
    volume = level(data['volume'], 1);
    audibleVolume = level(data['audibleVolume'], 1);
    if (audibleVolume == 0) audibleVolume = 1;
    mixWithOthers = data['mixWithOthers'] == true;
    themeMode = ThemeMode.values.firstWhere(
      (mode) => mode.name == data['theme'],
      orElse: () => ThemeMode.system,
    );
  }

  Future<void> setVolume(double value) {
    volume = value;
    if (value > 0) audibleVolume = value;
    return _persist();
  }

  Future<void> setMixWithOthers(bool value) {
    mixWithOthers = value;
    return _persist();
  }

  Future<void> setThemeMode(ThemeMode value) {
    themeMode = value;
    return _persist();
  }

  Future<void> _persist() {
    final json = jsonEncode({
      'volume': volume,
      'audibleVolume': audibleVolume,
      'mixWithOthers': mixWithOthers,
      'theme': themeMode.name,
    });
    notifyListeners();
    // Serial writes prevent a slow older slider change from replacing a newer one.
    _pending = _pending.then((_) async {
      try {
        await _save?.call(json);
        notice = null;
      } on Object {
        notice = 'Settings changed for this session but could not be saved.';
      }
      notifyListeners();
    });
    return _pending;
  }

  Future<void> flush() => _pending;
}
