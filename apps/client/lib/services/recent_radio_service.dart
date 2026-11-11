import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/recent_radio.dart';
import 'navidrome_client.dart';

/// One instance per authenticated client. Neither previews nor history cross sessions.
class RecentRadioService extends ChangeNotifier {
  RecentRadioService(
    this.client, {
    Future<String?> Function(String key)? read,
    Future<void> Function(String key, String value)? write,
    DateTime Function()? now,
  }) : _read = read ?? ((key) => SharedPreferencesAsync().getString(key)),
       _write =
           write ??
           ((key, value) => SharedPreferencesAsync().setString(key, value)),
       _now = now ?? DateTime.now {
    _subscription = client.listens.listen((_) {
      activityChanged = true;
      _notify();
    });
  }
  final NavidromeClient client;
  final Future<String?> Function(String) _read;
  final Future<void> Function(String, String) _write;
  final DateTime Function() _now;
  late final StreamSubscription<void> _subscription;
  String get storageKey =>
      'hyperstream.recentRadio.v1.${sha256.convert(utf8.encode(jsonEncode([client.baseUri.toString(), client.username])))}';
  RecentRadioDefinition definition = const RecentRadioDefinition();
  RadioPreview? preview;
  bool loading = false;
  bool activityChanged = false;
  int loadedCount = 0;
  String? error;
  String? storageNotice;
  bool _disposed = false;
  bool _canWrite = true;
  int _generation = 0;
  Future<void>? _initializing;
  Future<void>? _refreshing;
  Future<void> _saving = Future.value();

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize() => _initializing ??= () async {
    try {
      final value = await _read(storageKey).timeout(const Duration(seconds: 3));
      if (_disposed) return;
      if (value != null) {
        definition = RecentRadioDefinition.fromJson(
          jsonDecode(value) as Map<String, dynamic>,
        );
      }
    } on Object {
      // An unread/newer record must never be overwritten with defaults.
      _canWrite = false;
      storageNotice = 'Saved radio settings could not be read. Changes apply only to this session.';
    }
    _notify();
  }();

  Future<void> configure(RecentRadioDefinition value) async {
    await initialize();
    if (_disposed) return;
    // Validate at the boundary, including definitions constructed by callers.
    definition = RecentRadioDefinition.fromJson(value.toJson());
    _generation++;
    final encoded = jsonEncode(definition.toJson());
    if (_canWrite) {
      _saving = _saving.then((_) async {
        try {
          await _write(storageKey, encoded);
        } on Object {
          storageNotice =
              'Radio settings changed for this session but could not be saved.';
          _notify();
        }
      });
    }
    await refresh();
    await _saving;
  }

  Future<void> refresh() {
    if (_disposed) return Future.value();
    return _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
  }

  Future<void> _refresh() async {
    await initialize();
    if (_disposed) return;
    loading = true;
    error = null;
    _notify();
    try {
      while (!_disposed) {
        final generation = _generation;
        final requested = definition;
        loadedCount = 0;
        activityChanged = false;
        try {
          final tracks = await client.radioTracks(
            cancelled: () => _disposed || generation != _generation,
            onProgress: (count) {
              loadedCount = count;
              _notify();
            },
          );
          if (_disposed) return;
          if (generation != _generation) continue;
          preview = RadioPreview.evaluate(tracks, requested, _now());
          break;
        } on Object {
          if (_disposed) return;
          if (generation != _generation) continue;
          rethrow;
        }
      }
    } on Object catch (failure) {
      if (!_disposed) {
        error = failure is NavidromeException ? failure.message : 'Recent Radio could not refresh. Your last preview is still available.';
      }
    } finally {
      loading = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
