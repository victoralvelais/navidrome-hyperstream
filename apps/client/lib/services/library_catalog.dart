import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/library.dart';
import 'navidrome_client.dart';

/// Shared account catalog for radio and smart playlists. Local changes never scan.
class LibraryCatalog extends ChangeNotifier {
  LibraryCatalog(this.client, {DateTime Function()? now})
    : _now = now ?? DateTime.now {
    _subscription = client.localListens.listen(_onListen);
    _favoritesSubscription = client.favoriteChanges.listen(_onFavorite);
  }

  static const syncInterval = Duration(minutes: 30);
  final NavidromeClient client;
  final DateTime Function() _now;
  late final StreamSubscription<LocalListen> _subscription;
  late final StreamSubscription<(String, bool)> _favoritesSubscription;
  Map<String, Track> _tracks = {};
  final _local = <String, (LocalListen, int, int)>{};
  final _favorites = <String, bool>{};
  DateTime get currentTime => _now().toUtc();
  List<Track> tracks = const [];
  int revision = 0;
  DateTime evaluatedAt = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
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
    final track = _tracks[listen.track.id] ?? listen.track;
    final minimumCount = track.playCount + 1;
    _local[listen.track.id] = (listen, ++_revision, minimumCount);
    _tracks[track.id] = _overlay(track, listen, minimumCount);
    _evaluate();
    _notify();
  }

  void _onFavorite((String, bool) change) {
    if (_disposed) return;
    _favorites[change.$1] = change.$2;
    final track = _tracks[change.$1];
    if (track == null) return;
    _tracks[track.id] = track.withActivity(favorite: change.$2);
    _evaluate();
    _notify();
  }

  Track _overlay(Track track, LocalListen listen, int minimumCount) {
    final played = track.lastPlayedAt;
    if (played != null &&
        !played.isAfter(_now()) &&
        !played.isBefore(listen.startedAt) &&
        track.playCount >= minimumCount) {
      return track;
    }
    return track.withActivity(
      playedAt:
          played != null &&
              !played.isAfter(_now()) &&
              played.isAfter(listen.startedAt)
          ? played
          : listen.startedAt,
      playCount: track.playCount > minimumCount
          ? track.playCount
          : minimumCount,
    );
  }

  void _evaluate() {
    final now = _now();
    tracks = List.unmodifiable(_tracks.values);
    evaluatedAt = now.toUtc();
    revision++;
  }

  /// First visit loads the catalog. Further visits only re-evaluate cached dates.
  Future<void> ensureLoaded() {
    if (_disposed) return Future.value();
    if (!_started) return refresh();
    if (revision > 0) {
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
        final (listen, changedAt, minimumCount) = entry.value;
        final remote = incoming[entry.key];
        // A complete later scan owns membership (including server deletions).
        // A listen during this scan may describe a song its pages missed.
        if (remote == null && changedAt <= revision) {
          _local.remove(entry.key);
          continue;
        }
        final merged = _overlay(remote ?? listen.track, listen, minimumCount);
        incoming[entry.key] = merged;
        if (remote != null && identical(merged, remote)) {
          _local.remove(entry.key); // Server history has caught up.
        }
      }
      for (final entry in _favorites.entries.toList()) {
        final track = incoming[entry.key];
        if (track == null || track.starred == entry.value) {
          _favorites.remove(entry.key);
        } else {
          incoming[entry.key] = track.withActivity(favorite: entry.value);
        }
      }
      _tracks = incoming;
      lastSyncedAt = _now();
      _evaluate();
    } on Object catch (failure) {
      if (!_disposed) {
        error = failure is NavidromeException ? failure.message : 'The library could not sync. Your current list is still available.';
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
    unawaited(_favoritesSubscription.cancel());
    super.dispose();
  }
}
