import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/smart_playlist.dart';
import 'navidrome_client.dart';

/// Non-secret definitions only. One serialized document per server/user.
class SmartPlaylistStore extends ChangeNotifier {
  SmartPlaylistStore(
    NavidromeClient client, {
    Future<String?> Function(String)? read,
    Future<void> Function(String, String)? write,
  }) : storageKey =
           'hyperstream.smartPlaylists.v1.${sha256.convert(utf8.encode(jsonEncode([client.baseUri.toString(), client.username])))}',
       _read = read ?? ((key) => SharedPreferencesAsync().getString(key)),
       _write =
           write ??
           ((key, value) => SharedPreferencesAsync().setString(key, value));

  final String storageKey;
  final Future<String?> Function(String) _read;
  final Future<void> Function(String, String) _write;
  List<SmartPlaylistDefinition> items = const [];
  bool loaded = false;
  bool canWrite = false;
  String? error;
  bool _disposed = false;
  Future<void>? _loading;
  Future<void> _pending = Future.value();

  static String newId() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() => _loading ??= () async {
    try {
      final raw = await _read(storageKey).timeout(const Duration(seconds: 3));
      if (_disposed) return;
      if (raw != null) {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        if (data['schemaVersion'] != 1) throw const FormatException();
        final list = data['playlists'] as List;
        if (list.length > 500) throw const FormatException();
        final parsed = list
            .map(
              (entry) => SmartPlaylistDefinition.fromJson(
                entry as Map<String, dynamic>,
              ),
            )
            .toList();
        if (parsed.map((item) => item.id).toSet().length != parsed.length) {
          throw const FormatException();
        }
        items = List.unmodifiable(parsed);
      }
      canWrite = true;
    } on Object {
      // Preserve unread, malformed and newer data. Never overwrite with defaults.
      error = 'Saved smart playlists could not be read. Reopen the app to try again; your saved data has been preserved.';
    } finally {
      loaded = true;
      _notify();
    }
  }();

  Future<bool> save(SmartPlaylistDefinition value) {
    value.validate();
    return _change(
      (items) => [...items.where((item) => item.id != value.id), value],
    );
  }

  Future<bool> remove(String id) =>
      _change((items) => items.where((item) => item.id != id).toList());

  /// Read the latest definition inside the write queue. Concurrent reshuffles
  /// advance independently and can never resurrect a deleted playlist.
  Future<bool> reshuffle(String id) => _change(
    (items) => [
      for (final item in items) item.id == id ? item.reshuffled() : item,
    ],
  );

  Future<bool> _change(
    List<SmartPlaylistDefinition> Function(List<SmartPlaylistDefinition>) edit,
  ) async {
    await load();
    if (_disposed || !canWrite) return false;
    var success = false;
    _pending = _pending.then((_) async {
      if (_disposed) return;
      final next = edit(items);
      if (next.length > 500) {
        error = 'You can save up to 500 smart playlists per account.';
        _notify();
        return;
      }
      try {
        await _write(
          storageKey,
          jsonEncode({
            'schemaVersion': 1,
            'playlists': next.map((item) => item.toJson()).toList(),
          }),
        );
        if (_disposed) return;
        items = List.unmodifiable(next);
        error = null;
        success = true;
      } on Object {
        error = 'Could not save your smart playlists. Keep the editor open and try again.';
      }
      _notify();
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
