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
  bool glassEffects = true;
  ThemeMode themeMode = ThemeMode.system;
  String? notice;

  static Future<AppPreferences> load({
    SharedPreferencesAsync? storage,
    Duration timeout = const Duration(seconds: 3),
  }) async {
    try {
      // Construct inside the guard too: missing plugin registration may throw
      // before the first platform call. A stalled read must not block listening.
      final backend = storage ?? SharedPreferencesAsync();
      final json = await backend.getString(storageKey).timeout(timeout);
      final preferences = AppPreferences(
        save: (json) => backend.setString(storageKey, json),
      );
      if (json != null) preferences.restore(json);
      return preferences;
    } on Object {
      // Do not write defaults over unread settings or retry a stalled backend.
      return AppPreferences()
        ..notice =
            'Saved settings are unavailable. Using temporary settings for this session.';
    }
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
    glassEffects = data['glassEffects'] != false;
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

  Future<void> setGlassEffects(bool value) {
    glassEffects = value;
    return _persist();
  }

  Future<void> _persist() {
    final json = jsonEncode({
      'volume': volume,
      'audibleVolume': audibleVolume,
      'mixWithOthers': mixWithOthers,
      'glassEffects': glassEffects,
      'theme': themeMode.name,
    });
    notifyListeners();
    if (_save == null) return Future.value();
    // Serial writes prevent a slow older slider change from replacing a newer one.
    _pending = _pending.then((_) async {
      try {
        await _save(json);
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
