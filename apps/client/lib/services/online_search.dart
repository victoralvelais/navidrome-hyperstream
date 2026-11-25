import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/library.dart';
import 'mornye_provider.dart';
import 'mornye_sources.dart';
import 'music_provider.dart';
import 'music_sources.dart';

class OnlineSearchIssue {
  const OnlineSearchIssue(this.source, {this.verificationProvider});
  final OnlineSource source;
  final String? verificationProvider;
}

/// One query owns its transports, cancellation and deadlines. Each completion
/// publishes a ranked snapshot; slow/failed providers cannot hide other results.
class OnlineSearch extends ChangeNotifier {
  OnlineSearch(
    this.sources,
    this.query, {
    this.timeout = const Duration(seconds: 25),
  });
  final MusicSources sources;
  final String query;
  final Duration timeout;
  final _results = <String, SourceSearch>{};
  final _issues = <String, OnlineSearchIssue>{};
  final _pending = <String, OnlineSource>{};
  final _abort = <Completer<void>>{};
  bool _disposed = false;
  bool _started = false;
  String? error;
  List<Track> tracks = const [];
  List<SourceAlbum> albums = const [];
  List<OnlineSearchIssue> get issues =>
      _issues.values.toList()
        ..sort((a, b) => a.source.name.compareTo(b.source.name));
  List<OnlineSource> get pending => _pending.values.toList();
  bool get busy => _pending.isNotEmpty;

  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
    var targets = sources.onlineSources
        .where(
          (e) => sources.searchSource == null || e.id == sources.searchSource,
        )
        .toList();
    final link = Uri.tryParse(query);
    if (link != null && link.hasScheme) {
      targets = targets
          .where(
            (e) =>
                e.id.startsWith('mornye:') &&
                MornyeProvider.acceptsLink(e.id.substring(7), link),
          )
          .toList();
      if (targets.isEmpty) {
        error = 'Enable the matching music source and choose All sources for this link.';
      }
    }
    if (query.trim().isEmpty) return;
    _pending.addEntries(targets.map((e) => MapEntry(e.id, e)));
    notifyListeners();
    var next = 0;
    Future<void> worker() async {
      while (!_disposed && next < targets.length) {
        final target = targets[next++];
        await _load(target, verify: sources.searchSource != null);
      }
    }

    await Future.wait(
      List.generate(targets.length.clamp(0, 3), (_) => worker()),
    );
  }

  Future<void> retry(OnlineSearchIssue issue) async {
    if (_disposed || _pending.containsKey(issue.source.id)) return;
    _issues.remove(issue.source.id);
    _pending[issue.source.id] = issue.source;
    notifyListeners();
    await _load(issue.source, verify: true);
  }

  Future<void> _load(OnlineSource target, {required bool verify}) async {
    MusicProvider? provider;
    final cancel = Completer<void>();
    _abort.add(cancel);
    try {
      provider = sources.providerById(target.id);
      Future<SourceSearch> request() async {
        // Each request gets its own deadline; the user's verification browser
        // time is not charged against a network timeout.
        return provider!
            .search(query, abort: cancel.future)
            .timeout(
              timeout,
              onTimeout: () {
                if (!cancel.isCompleted) cancel.complete();
                throw TimeoutException('Source search timed out');
              },
            );
      }

      final result = verify && sources.extensions != null
          ? await sources.extensions!.withVerification(
              request,
              isCurrent: () => !_disposed && !cancel.isCompleted,
            )
          : await request();
      if (!_disposed) _results[target.id] = result;
    } on Object catch (failure) {
      if (!_disposed) {
        _issues[target.id] = OnlineSearchIssue(
          target,
          verificationProvider: failure is ProviderVerificationRequired
              ? failure.providerId
              : null,
        );
      }
    } finally {
      if (!cancel.isCompleted) cancel.complete();
      _abort.remove(cancel);
      provider?.close();
      if (!_disposed) {
        _pending.remove(target.id);
        _rank();
        notifyListeners();
      }
    }
  }

  void _rank() {
    final songRows = <(Track, double, int)>[];
    final albumRows = <(SourceAlbum, double, int)>[];
    final seenTracks = <String>{}, seenAlbums = <String>{};
    for (final result in _results.entries) {
      for (var i = 0; i < result.value.tracks.length; i++) {
        final track = result.value.tracks[i];
        final source = track.source;
        if (source == null ||
            source.sourceId != result.key ||
            !seenTracks.add('${source.sourceId}/${source.trackId}')) {
          continue;
        }
        songRows.add((
          track,
          relevance(
            query,
            track.title,
            track.artist,
            i,
            available: source.available,
          ),
          i,
        ));
      }
      for (var i = 0; i < result.value.albums.length; i++) {
        final album = result.value.albums[i];
        if (album.sourceId != result.key ||
            !seenAlbums.add('${album.sourceId}/${album.id}')) {
          continue;
        }
        albumRows.add((
          album,
          relevance(query, album.title, album.artist, i),
          i,
        ));
      }
    }
    songRows.sort((a, b) {
      final score = b.$2.compareTo(a.$2);
      if (score != 0) return score;
      final rank = a.$3.compareTo(b.$3);
      return rank != 0 ? rank : a.$1.id.compareTo(b.$1.id);
    });
    albumRows.sort((a, b) {
      final score = b.$2.compareTo(a.$2);
      if (score != 0) return score;
      final rank = a.$3.compareTo(b.$3);
      return rank != 0
          ? rank
          : '${a.$1.sourceId}/${a.$1.id}'.compareTo(
              '${b.$1.sourceId}/${b.$1.id}',
            );
    });
    tracks = List.unmodifiable(songRows.map((r) => r.$1));
    albums = List.unmodifiable(albumRows.map((r) => r.$1));
  }

  static final _words = RegExp(r'[\p{L}\p{N}]+', unicode: true);
  static String _normalized(String value) =>
      _words.allMatches(value.toLowerCase()).map((m) => m.group(0)!).join(' ');

  /// Metadata relevance dominates provider rank. No service supplies a
  /// comparable universal score, so rank is only a modest tie-breaker.
  static double relevance(
    String query,
    String title,
    String artist,
    int rank, {
    bool available = true,
  }) {
    final q = _normalized(query),
        t = _normalized(title),
        a = _normalized(artist);
    if (q.isEmpty) return 0;
    final tokens = q.split(' ').toSet();
    final fields = '$t $a'.split(' ').toSet();
    final coverage = tokens.where(fields.contains).length / tokens.length;
    var score = coverage * 500 + 40 / (rank + 1);
    if (t == q) {
      score += 250;
    } else if (t.contains(q)) {
      score += 140;
    }
    if (a == q) {
      score += 130;
    } else if (a.contains(q)) {
      score += 80;
    }
    if ('$t $a' == q || '$a $t' == q) score += 280;
    if (!available) score -= 200;
    return score;
  }

  @override
  void dispose() {
    _disposed = true;
    for (final cancel in _abort) {
      if (!cancel.isCompleted) cancel.complete();
    }
    _abort.clear();
    super.dispose();
  }
}
