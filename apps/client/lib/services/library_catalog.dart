import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/library.dart';
import 'app_preferences.dart';
import 'navidrome_client.dart';
import 'catalog_cache.dart';

/// Shared account catalog for radio and smart playlists. Local changes never scan.
class LibraryCatalog extends ChangeNotifier {
  LibraryCatalog(
    this.client, {
    DateTime Function()? now,
    this._cache,
    this.preferences,
  }) : _now = now ?? DateTime.now {
    _subscription = client.localListens.listen(_onListen);
    _favoritesSubscription = client.favoriteChanges.listen(_onFavorite);
    _ratingsSubscription = client.ratingChanges.listen(_onRating);
    // Restore existing metadata even if this session never opens a playlist.
    // Otherwise listens on Library/Home could be lost on the next restart.
    // The account screen also starts ensureLoaded to scan a cold cache in the background.
    if (_cache != null) unawaited(_restoreOnce());
  }

  static const syncInterval = Duration(minutes: 30);
  final NavidromeClient client;
  final AppPreferences? preferences;
  final DateTime Function() _now;
  final CatalogCache? _cache;
  Future<void>? _restoring;
  bool _restored = false;
  final _earlyListenCounts = <String, int>{};
  Timer? _saveTimer;
  late final StreamSubscription<LocalListen> _subscription;
  late final StreamSubscription<(String, bool)> _favoritesSubscription;
  late final StreamSubscription<(String, int)> _ratingsSubscription;
  Map<String, Track> _tracks = {};
  final _local = <String, (LocalListen, int, int)>{};
  final _favorites = <String, bool>{};
  final _ratings = <String, int>{};
  DateTime get currentTime => _now().toUtc();
  List<Track> tracks = const [];
  int revision = 0;
  DateTime evaluatedAt = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  DateTime? lastSyncedAt;
  bool loading = false;
  int loadedCount = 0;
  int? syncTotal;
  int? lastSyncTrackCount;

  /// The final page and metadata validation must finish before showing 100%.
  double? get syncProgress {
    if (!loading) return error == null && lastSyncedAt != null ? 1 : null;
    final total = syncTotal;
    if (total == null || total == 0) return null;
    return (loadedCount / total).clamp(0.0, 0.99);
  }

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
    if (!_restored) {
      _earlyListenCounts[track.id] = (_earlyListenCounts[track.id] ?? 0) + 1;
    }
    _local[listen.track.id] = (listen, ++_revision, minimumCount);
    _tracks[track.id] = _overlay(track, listen, minimumCount);
    _evaluate();
    _saveSoon();
    _notify();
  }

  void _onFavorite((String, bool) change) {
    if (_disposed) return;
    _favorites[change.$1] = change.$2;
    final track = _tracks[change.$1];
    if (track == null) return;
    _tracks[track.id] = track.withActivity(favorite: change.$2);
    _evaluate();
    _saveSoon();
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

  void _onRating((String, int) change) {
    if (_disposed) return;
    _ratings[change.$1] = change.$2;
    final track = _tracks[change.$1];
    if (track == null) return;
    _tracks[track.id] = track.withActivity(rating: change.$2);
    _evaluate();
    _saveSoon();
    _notify();
  }

  void _evaluate() {
    final now = _now();
    tracks = List.unmodifiable(_tracks.values);
    evaluatedAt = now.toUtc();
    revision++;
  }

  /// A saved catalog is immediately playable, even while a due sync runs.
  Future<void> ensureLoaded() async {
    if (_disposed) return;
    await _restoreOnce();
    if (_disposed) return;
    if (!_started) return refresh();
    if (revision > 0) {
      _evaluate();
      _notify();
    }
    if (lastSyncedAt == null) await _refreshing;
  }

  Future<void> _restoreOnce() =>
      _restoring ??= _restore().catchError((Object _) {}).whenComplete(() {
        _restored = true;
        _earlyListenCounts.clear();
      });

  Future<void> _restore() async {
    final saved = await _cache?.read();
    if (saved == null || saved.syncedAt.isAfter(_now())) return;
    final changedWhileRestoring =
        _local.isNotEmpty || _favorites.isNotEmpty || _ratings.isNotEmpty;
    if (_disposed && !changedWhileRestoring) return;
    final incoming = {for (final track in saved.tracks) track.id: track};
    for (final entry in _earlyListenCounts.entries) {
      final local = _local[entry.key];
      final prior = incoming[entry.key];
      if (local != null &&
          prior != null &&
          (prior.lastPlayedAt == null ||
              local.$1.startedAt.isAfter(prior.lastPlayedAt!))) {
        final mergedCount = prior.playCount + entry.value;
        if (mergedCount > local.$3) {
          _local[entry.key] = (local.$1, local.$2, mergedCount);
        }
      }
    }
    for (final entry in saved.listens.entries) {
      final track = incoming[entry.key];
      if (track == null || _local.containsKey(entry.key)) continue;
      _local[entry.key] = (
        LocalListen(track, entry.value.startedAt),
        0,
        entry.value.minimumCount,
      );
    }
    for (final entry in _local.entries) {
      final (listen, _, count) = entry.value;
      incoming[entry.key] = _overlay(
        incoming[entry.key] ?? listen.track,
        listen,
        count,
      );
    }
    for (final entry in saved.favorites.entries) {
      _favorites.putIfAbsent(entry.key, () => entry.value);
    }
    for (final entry in _favorites.entries) {
      final track = incoming[entry.key];
      if (track != null) {
        incoming[entry.key] = track.withActivity(favorite: entry.value);
      }
    }
    for (final entry in saved.ratings.entries) {
      _ratings.putIfAbsent(entry.key, () => entry.value);
    }
    for (final entry in _ratings.entries) {
      final track = incoming[entry.key];
      if (track != null) {
        incoming[entry.key] = track.withActivity(rating: entry.value);
      }
    }
    _tracks = incoming;
    _started = saved.librarySynced;
    lastSyncedAt = saved.librarySynced ? saved.syncedAt : null;
    lastSyncTrackCount = saved.librarySynced ? saved.syncedTrackCount : null;
    _nextSyncAt = saved.librarySynced ? saved.syncedAt.add(syncInterval) : null;
    _evaluate();
    if (changedWhileRestoring) _saveSoon();
    _schedule();
    _notify();
  }

  void _saveSoon() {
    if (_cache == null || _disposed) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(
      const Duration(seconds: 1),
      () => unawaited(flushCache()),
    );
  }

  Future<void> flushCache() async {
    // A slow cache read must merge older history before a new listen can save.
    // Finish that merge on disposal too, so an account switch cannot replace a
    // full saved history with the few listens recorded during startup.
    final restored = _restoreOnce();
    _saveTimer?.cancel();
    _saveTimer = null;
    final cache = _cache;
    if (cache == null) return;
    final snapshot = restored.then((_) {
      _saveTimer?.cancel();
      _saveTimer = null;
      final syncedAt = lastSyncedAt;
      return CatalogSnapshot(
        syncedAt: syncedAt ?? _now(),
        librarySynced: syncedAt != null,
        syncedTrackCount: lastSyncTrackCount ?? 0,
        tracks: tracks,
        listens: {
          for (final entry in _local.entries)
            entry.key: CachedListen(entry.value.$1.startedAt, entry.value.$3),
        },
        favorites: _favorites,
        ratings: _ratings,
      );
    });
    try {
      if (cache is FileCatalogCache) {
        await cache.writePending(snapshot);
      } else {
        await cache.write(await snapshot);
      }
    } on Object {
      if (!_disposed) {
        error = 'The library is available, but its on-device cache could not be saved.';
        _notify();
      }
    }
  }

  /// Owned by the account screen, so scheduling continues on other app pages.
  void setAppActive(bool active) {
    if (_disposed) return;
    _appActive = active;
    if (!active && _saveTimer != null) unawaited(flushCache());
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
    await _restoreOnce();
    if (_disposed) return;
    _started = true;
    _timer?.cancel();
    loading = true;
    loadedCount = 0;
    syncTotal = null;
    error = null;
    final revision = _revision;
    final batchSize =
        preferences?.catalogBatchSize ?? AppPreferences.defaultCatalogBatchSize;
    var syncFinished = false;
    _notify();
    // Progress metadata must not delay the catalog. A slow count may finish
    // after this sync or a subsequent one, so only accept it while this run lives.
    unawaited(
      client.catalogTrackCount(cancelled: () => _disposed || syncFinished).then(
        (total) {
          if (_disposed || syncFinished) return;
          syncTotal = total != null && total >= loadedCount ? total : null;
          _notify();
        },
      ),
    );
    try {
      final tracks = await client.radioTracks(
        pageSize: batchSize,
        cancelled: () => _disposed,
        onProgress: (count) {
          loadedCount = count;
          // The library may have grown since the count query. Keep paging and
          // withdraw the stale total rather than invent a larger denominator.
          if (syncTotal != null && count > syncTotal!) syncTotal = null;
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
        if (remote == null &&
            changedAt <= revision &&
            listen.track.source == null) {
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
      for (final entry in _ratings.entries.toList()) {
        final track = incoming[entry.key];
        if (track == null || track.userRating == entry.value) {
          _ratings.remove(entry.key);
        } else {
          incoming[entry.key] = track.withActivity(rating: entry.value);
        }
      }
      _tracks = incoming;
      loadedCount = tracks.length;
      lastSyncTrackCount = tracks.length;
      syncTotal = tracks.length;
      lastSyncedAt = _now();
      _evaluate();
      unawaited(flushCache());
    } on Object catch (failure) {
      if (!_disposed) {
        error = failure is NavidromeException ? failure.message : 'The library could not sync. Your current list is still available.';
      }
    } finally {
      syncFinished = true;
      loading = false;
      // Failed attempts also wait 30 minutes, avoiding a tight retry loop.
      _nextSyncAt = _now().add(syncInterval);
      _schedule();
      _notify();
    }
  }

  @override
  void dispose() {
    if (_saveTimer != null) unawaited(flushCache());
    _disposed = true;
    _timer?.cancel();
    unawaited(_subscription.cancel());
    unawaited(_favoritesSubscription.cancel());
    unawaited(_ratingsSubscription.cancel());
    super.dispose();
  }
}
