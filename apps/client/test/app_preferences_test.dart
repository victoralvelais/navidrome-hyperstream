import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperstream_client/services/app_preferences.dart';

void main() {
  test(
    'saved preferences restore mute, its previous level, mixing, and theme',
    () async {
      String? saved;
      final preferences = AppPreferences(save: (json) async => saved = json);
      await preferences.setVolume(.35);
      await preferences.setVolume(0);
      await preferences.setMixWithOthers(true);
      await preferences.setThemeMode(ThemeMode.dark);
      final restored = AppPreferences()..restore(saved!);
      expect(restored.volume, 0);
      expect(restored.audibleVolume, .35);
      expect(restored.mixWithOthers, isTrue);
      expect(restored.themeMode, ThemeMode.dark);
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
