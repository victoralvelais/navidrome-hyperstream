import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/library.dart';
import '../models/recent_radio.dart';
import 'navidrome_client.dart';

/// A session-scoped, built-in radio. Local listens never trigger a catalog read.
class RecentRadioService extends ChangeNotifier {
  RecentRadioService(this.client, {DateTime Function()? now})
    : _now = now ?? DateTime.now {
    _subscription = client.localListens.listen(_onListen);
  }

  static const syncInterval = Duration(minutes: 30);
  static const definition = RecentRadioDefinition();
  final NavidromeClient client;
  final DateTime Function() _now;
  late final StreamSubscription<LocalListen> _subscription;
  Map<String, Track> _tracks = {};
  final _local = <String, (LocalListen, int)>{};
  RadioPreview? preview;
  DateTime? lastSyncedAt;
  bool loading = false;
  int loadedCount = 0;
  String? error;
  bool _disposed = false;
  bool _started = false;
  bool _appActive = true;
  int _revision = 0;
  DateTime? _nextSyncAt;
  Timer? _timer;
  Future<void>? _refreshing;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _onListen(LocalListen listen) {
    if (_disposed) return;
    final previous = _local[listen.track.id]?.$1;
    if (previous != null && !listen.startedAt.isAfter(previous.startedAt)) {
      return;
    }
    _local[listen.track.id] = (listen, ++_revision);
    final track = _tracks[listen.track.id] ?? listen.track;
    _tracks[track.id] = _overlay(track, listen);
    _evaluate();
    _notify();
  }

  Track _overlay(Track track, LocalListen listen) {
    final played = track.lastPlayedAt;
    if (played != null &&
        !played.isAfter(_now()) &&
        !played.isBefore(listen.startedAt)) {
      return track;
    }
    return track.withLastPlayedAt(listen.startedAt);
  }

  void _evaluate() {
    final now = _now();
    _local.removeWhere(
      (_, value) =>
          value.$1.startedAt.isBefore(now.subtract(const Duration(days: 30))),
    );
    preview = RadioPreview.evaluate(_tracks.values, definition, now);
  }

  /// First visit loads the catalog. Further visits only re-evaluate cached dates.
  Future<void> ensureLoaded() {
    if (_disposed) return Future.value();
    if (!_started) return refresh();
    if (preview != null) {
      _evaluate();
      _notify();
    }
    return _refreshing ?? Future.value();
  }

  /// Owned by the account screen, so scheduling continues on other app pages.
  void setAppActive(bool active) {
    if (_disposed) return;
    _appActive = active;
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    _timer = null;
    if (_disposed || !_appActive || loading || _nextSyncAt == null) return;
    final remaining = _nextSyncAt!.difference(_now());
    _timer = Timer(remaining.isNegative ? Duration.zero : remaining, () {
      unawaited(refresh());
    });
  }

  Future<void> refresh() {
    if (_disposed) return Future.value();
    return _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
  }

  Future<void> _refresh() async {
    _started = true;
    _timer?.cancel();
    loading = true;
    loadedCount = 0;
    error = null;
    final revision = _revision;
    _notify();
    try {
      final tracks = await client.radioTracks(
        cancelled: () => _disposed,
        onProgress: (count) {
          loadedCount = count;
          _notify();
        },
      );
      if (_disposed) return;
      final incoming = {for (final track in tracks) track.id: track};
      for (final entry in _local.entries.toList()) {
        final (listen, changedAt) = entry.value;
        final remote = incoming[entry.key];
        // A complete later scan owns membership (including server deletions).
        // A listen during this scan may describe a song its pages missed.
        if (remote == null && changedAt <= revision) {
          _local.remove(entry.key);
          continue;
        }
        final merged = _overlay(remote ?? listen.track, listen);
        incoming[entry.key] = merged;
        if (remote != null && identical(merged, remote)) {
          _local.remove(entry.key); // Server history has caught up.
        }
      }
      _tracks = incoming;
      lastSyncedAt = _now();
      _evaluate();
    } on Object catch (failure) {
      if (!_disposed) {
        error = failure is NavidromeException ? failure.message : 'Recent Radio could not sync. Your current list is still available.';
      }
    } finally {
      loading = false;
      // Failed attempts also wait 30 minutes, avoiding a tight retry loop.
      _nextSyncAt = _now().add(syncInterval);
      _schedule();
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
