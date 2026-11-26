import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/library.dart';
import 'navidrome_client.dart';

class SongPlaybackSettings {
  const SongPlaybackSettings({this.speed = 1, this.keepPitch = true});

  final double speed;
  final bool keepPitch;
  bool get isDefault => speed == 1 && keepPitch;

  void validate() {
    if (!speed.isFinite || speed < .5 || speed > 2) {
      throw const FormatException('Invalid song tempo');
    }
  }

  Map<String, Object> toJson() => {'speed': speed, 'keepPitch': keepPitch};

  factory SongPlaybackSettings.fromJson(Map<String, dynamic> data) {
    if (data['speed'] is! num || data['keepPitch'] is! bool) {
      throw const FormatException('Invalid song settings');
    }
    final value = SongPlaybackSettings(
      speed: (data['speed'] as num).toDouble(),
      keepPitch: data['keepPitch'] as bool,
    );
    value.validate();
    return value;
  }

  @override
  bool operator ==(Object other) =>
      other is SongPlaybackSettings &&
      other.speed == speed &&
      other.keepPitch == keepPitch;
  @override
  int get hashCode => Object.hash(speed, keepPitch);
}

/// Device-local song choices, separate from account credentials and app defaults.
/// Only opaque identity digests and audio settings are written to storage.
class SongPlaybackStore extends ChangeNotifier {
  SongPlaybackStore({this._save});

  static const storageKey = 'hyperstream.song-playback.v1';
  static final _validKey = RegExp(r'^[a-f0-9]{64}$');
  final Future<void> Function(String)? _save;
  final _values = <String, SongPlaybackSettings>{};
  Future<void>? _pending;
  String? _nextWrite;
  String? notice;

  static String keyFor(NavidromeClient client, Track track) {
    final source = track.source;
    final identity = source == null
        ? ['navidrome', client.baseUri.toString(), client.username, track.id]
        : ['online', source.sourceId, source.trackId];
    return sha256.convert(utf8.encode(jsonEncode(identity))).toString();
  }

  static Future<SongPlaybackStore> load({
    SharedPreferencesAsync? storage,
    Duration timeout = const Duration(seconds: 3),
  }) async {
    try {
      final backend = storage ?? SharedPreferencesAsync();
      final json = await backend.getString(storageKey).timeout(timeout);
      final store = SongPlaybackStore(
        save: (value) => backend.setString(storageKey, value),
      );
      if (json != null) {
        if (json.length > 16 * 1024 * 1024) throw const FormatException();
        final data = jsonDecode(json) as Map<String, dynamic>;
        if (data['schemaVersion'] != 1) throw const FormatException();
        final songs = data['songs'] as Map<String, dynamic>;
        if (songs.length > 100000) throw const FormatException();
        for (final entry in songs.entries) {
          if (!_validKey.hasMatch(entry.key)) throw const FormatException();
          store._values[entry.key] = SongPlaybackSettings.fromJson(
            entry.value as Map<String, dynamic>,
          );
        }
      }
      return store;
    } on Object {
      // Never replace unread/corrupt/newer data with an empty default map.
      return SongPlaybackStore()
        ..notice =
            'Saved song settings are unavailable. Changes are temporary for this session.';
    }
  }

  SongPlaybackSettings get(String key) =>
      _values[key] ?? const SongPlaybackSettings();

  Future<void> set(String key, SongPlaybackSettings value) {
    value.validate();
    if (!_validKey.hasMatch(key)) {
      throw const FormatException('Invalid song key');
    }
    if (value.isDefault) {
      _values.remove(key);
    } else {
      _values[key] = value;
    }
    notifyListeners();
    if (_save == null) return Future.value();
    _nextWrite = jsonEncode({
      'schemaVersion': 1,
      'songs': _values.map((key, value) => MapEntry(key, value.toJson())),
    });
    return _pending ??= _drain();
  }

  Future<void> _drain() async {
    // Yield before work so _pending is assigned even for a synchronous backend.
    await Future<void>.value();
    while (_nextWrite != null) {
      final json = _nextWrite!;
      _nextWrite = null;
      try {
        await _save!(json);
        notice = null;
      } on Object {
        notice =
            'Song settings changed for this session but could not be saved.';
      }
      notifyListeners();
    }
    _pending = null;
  }

  Future<void> flush() => _pending ?? Future.value();
}
