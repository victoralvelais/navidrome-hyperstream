import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/playlist_icon.dart';
import 'navidrome_client.dart';

/// Device-only presentation, isolated by account. Server artwork is untouched.
class PlaylistIconStore extends ChangeNotifier {
  PlaylistIconStore(
    NavidromeClient client, {
    Future<String?> Function(String)? read,
    Future<void> Function(String, String)? write,
  }) : storageKey =
           'hyperstream.playlistIcons.v1.${sha256.convert(utf8.encode(jsonEncode([client.baseUri.toString(), client.username])))}',
       _read = read ?? ((key) => SharedPreferencesAsync().getString(key)),
       _write =
           write ??
           ((key, value) => SharedPreferencesAsync().setString(key, value));
  final String storageKey;
  final Future<String?> Function(String) _read;
  final Future<void> Function(String, String) _write;
  Map<String, String> _icons = {};
  bool canWrite = false;
  bool _disposed = false;
  String? error;
  Future<void>? _loading;
  Future<void> _pending = Future.value();

  PlaylistIcon iconFor(String id) =>
      PlaylistIcon.values
          .where((icon) => icon.name == _icons[id])
          .firstOrNull ??
      PlaylistIcon.automatic;
  Future<void> load() => _loading ??= () async {
    try {
      final raw = await _read(storageKey).timeout(const Duration(seconds: 3));
      if (_disposed) return;
      if (raw != null) {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        if (data['schemaVersion'] != 1) throw const FormatException();
        _icons = Map<String, String>.from(data['icons'] as Map);
      }
      canWrite = true;
    } on Object {
      error = 'Saved playlist icons could not be read. Your existing choices have been preserved.';
    }
    if (!_disposed) notifyListeners();
  }();

  Future<bool> setIcon(String id, PlaylistIcon icon) async {
    await load();
    if (_disposed || !canWrite) return false;
    var success = false;
    _pending = _pending.then((_) async {
      if (_disposed) return;
      final next = {..._icons};
      if (icon == PlaylistIcon.automatic) {
        next.remove(id);
      } else {
        next[id] = icon.name;
      }
      try {
        await _write(
          storageKey,
          jsonEncode({'schemaVersion': 1, 'icons': next}),
        );
        if (_disposed) return;
        _icons = next;
        error = null;
        success = true;
      } on Object {
        error = 'Could not save this playlist icon. Try again.';
      }
      if (!_disposed) notifyListeners();
    });
    await _pending;
    return success;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
