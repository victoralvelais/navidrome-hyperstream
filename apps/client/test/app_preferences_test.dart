import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperstream_client/services/app_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakePreferenceStorage extends Fake implements SharedPreferencesAsync {
  FakePreferenceStorage({required this.read});
  final Future<String?> Function() read;
  final writes = <String>[];

  @override
  Future<String?> getString(String key) => read();
  @override
  Future<void> setString(String key, String value) async => writes.add(value);
}

void main() {
  test(
    'stalled preference reads fall back without overwriting unread settings',
    () async {
      final gate = Completer<String?>();
      final storage = FakePreferenceStorage(read: () => gate.future);
      final preferences = await AppPreferences.load(
        storage: storage,
        timeout: const Duration(milliseconds: 10),
      );
      expect(preferences.notice, contains('temporary settings'));
      await preferences.setVolume(.4);
      expect(preferences.volume, .4);
      expect(preferences.notice, contains('temporary settings'));
      expect(storage.writes, isEmpty);
      gate.complete('{"volume":0.9}');
      await Future<void>.delayed(Duration.zero);
      expect(preferences.volume, .4);
      preferences.dispose();
    },
  );

  test('valid startup preferences retain persistence', () async {
    final storage = FakePreferenceStorage(
      read: () async => '{"volume":0.3,"theme":"dark"}',
    );
    final preferences = await AppPreferences.load(storage: storage);
    expect(preferences.volume, .3);
    expect(preferences.themeMode, ThemeMode.dark);
    await preferences.setVolume(.5);
    expect(jsonDecode(storage.writes.single)['volume'], .5);
    preferences.dispose();
  });

  test('malformed startup preferences are left intact', () async {
    final storage = FakePreferenceStorage(read: () async => 'not-json');
    final preferences = await AppPreferences.load(storage: storage);
    expect(preferences.volume, 1);
    expect(preferences.notice, contains('temporary settings'));
    await preferences.setThemeMode(ThemeMode.dark);
    expect(storage.writes, isEmpty);
    preferences.dispose();
  });

  test(
    'saved preferences restore mute, its previous level, mixing, and theme',
    () async {
      String? saved;
      final preferences = AppPreferences(save: (json) async => saved = json);
      await preferences.setVolume(.35);
      await preferences.setVolume(0);
      await preferences.setMixWithOthers(true);
      await preferences.setThemeMode(ThemeMode.dark);
      await preferences.setGlassEffects(false);
      final restored = AppPreferences()..restore(saved!);
      expect(restored.volume, 0);
      expect(restored.audibleVolume, .35);
      expect(restored.mixWithOthers, isTrue);
      expect(restored.themeMode, ThemeMode.dark);
      expect(restored.glassEffects, isFalse);
      preferences.dispose();
      restored.dispose();
    },
  );

  test('slow preference writes cannot overwrite later choices', () async {
    final gate = Completer<void>();
    final saved = <String>[];
    final preferences = AppPreferences(
      save: (json) async {
        if (saved.isEmpty) await gate.future;
        saved.add(json);
      },
    );
    final first = preferences.setVolume(.2);
    final second = preferences.setVolume(.7);
    gate.complete();
    await Future.wait([first, second]);
    expect(jsonDecode(saved.last)['volume'], .7);
    preferences.dispose();
  });

  test(
    'unavailable storage leaves usable settings with a visible notice',
    () async {
      final preferences = AppPreferences(
        save: (_) async => throw StateError('disk'),
      );
      await preferences.setVolume(.4);
      expect(preferences.volume, .4);
      expect(preferences.notice, contains('could not be saved'));
      preferences.dispose();
    },
  );

  test('invalid saved levels and future theme names have safe defaults', () {
    final preferences = AppPreferences()
      ..restore('{"volume":-4,"audibleVolume":0,"theme":"future"}');
    expect(preferences.volume, 0);
    expect(preferences.audibleVolume, 1);
    expect(preferences.themeMode, ThemeMode.system);
    preferences.dispose();
  });
}
