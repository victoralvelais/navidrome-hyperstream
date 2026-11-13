import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/library.dart';
import 'navidrome_client.dart';

class CachedListen {
  const CachedListen(this.startedAt, this.minimumCount);
  final DateTime startedAt;
  final int minimumCount;
}

class CatalogSnapshot {
  CatalogSnapshot({
    required this.syncedAt,
    required List<Track> tracks,
    int? syncedTrackCount,
    Map<String, CachedListen> listens = const {},
    Map<String, bool> favorites = const {},
    Map<String, int> ratings = const {},
  }) : syncedTrackCount = syncedTrackCount ?? tracks.length,
       tracks = List.unmodifiable(tracks),
       listens = Map.unmodifiable(listens),
       favorites = Map.unmodifiable(favorites),
       ratings = Map.unmodifiable(ratings);
  final DateTime syncedAt;
  final int syncedTrackCount;
  final List<Track> tracks;
  final Map<String, CachedListen> listens;
  final Map<String, bool> favorites;
  final Map<String, int> ratings;
}

abstract interface class CatalogCache {
  Future<CatalogSnapshot?> read();
  Future<void> write(CatalogSnapshot snapshot);
}

/// Rebuildable, account-scoped metadata only. No credentials, stream URLs, or
/// audio. Atomic replacement keeps a partial write from replacing a good scan.
class FileCatalogCache implements CatalogCache {
  FileCatalogCache(
    NavidromeClient client, {
    Future<Directory> Function()? directory,
  }) : accountKey = sha256
           .convert(
             utf8.encode(
               jsonEncode([client.baseUri.toString(), client.username]),
             ),
           )
           .toString(),
       _directory = directory ?? getApplicationSupportDirectory;

  final String accountKey;
  final Future<Directory> Function() _directory;
  // Serialize across account screen replacements too. Returning to a server
  // must wait for its previous screen's final save before restoring the cache.
  static final _pending = <String, Future<void>>{};

  Future<File> _file() async {
    final root = await _directory();
    return File('${root.path}/catalog-v1/$accountKey.json');
  }

  @override
  Future<CatalogSnapshot?> read() async {
    try {
      await _pending[accountKey];
      final file = await _file();
      if (!await file.exists() || await file.length() > 128 * 1024 * 1024) {
        return null;
      }
      // Encoding/decoding 15k+ tracks runs off the UI isolate.
      return await compute(_decode, await file.readAsString());
    } on Object {
      return null; // Missing/corrupt caches fall back to a complete server scan.
    }
  }

  @override
  Future<void> write(CatalogSnapshot snapshot) {
    final previous = _pending[accountKey] ?? Future<void>.value();
    final writing = previous.then((_) async {
      final encoded = await compute(_encode, snapshot);
      final file = await _file();
      await file.parent.create(recursive: true);
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(encoded, flush: true);
      await temporary.rename(file.path);
    });
    // The next write/read still runs after a failed save. Preserve the error for
    // this caller without leaving an unhandled future in the serialization map.
    final settled = writing.catchError((Object _) {});
    _pending[accountKey] = settled;
    unawaited(
      settled.then((_) {
        if (identical(_pending[accountKey], settled)) {
          _pending.remove(accountKey);
        }
      }),
    );
    return writing;
  }
}

String _encode(CatalogSnapshot value) => jsonEncode({
  'schemaVersion': 1,
  'syncedAt': value.syncedAt.toUtc().toIso8601String(),
  'syncedTrackCount': value.syncedTrackCount,
  'tracks': [
    for (final track in value.tracks)
      {
        'id': track.id,
        'title': track.title,
        'artist': track.artist,
        'album': track.album,
        'duration': track.duration.inSeconds,
        'durationMs': track.duration.inMilliseconds,
        'track': track.number,
        'coverArt': track.coverArt,
        'starred': track.starred ? true : null,
        'created': track.addedAt?.toUtc().toIso8601String(),
        'played': track.lastPlayedAt?.toUtc().toIso8601String(),
        'playCount': track.playCount,
        'invalidActivityDates': track.invalidActivityDates,
        'albumId': track.albumId,
        'artistId': track.artistId,
        'suffix': track.container,
        'bitRate': track.bitRate,
        'userRating': track.userRating,
        'genres': [
          for (final name in track.genres) {'name': name},
        ],
        'year': track.year,
      },
  ],
  'listens': {
    for (final entry in value.listens.entries)
      entry.key: {
        'startedAt': entry.value.startedAt.toUtc().toIso8601String(),
        'minimumCount': entry.value.minimumCount,
      },
  },
  'favorites': value.favorites,
  'ratings': value.ratings,
});

CatalogSnapshot _decode(String raw) {
  final data = jsonDecode(raw) as Map<String, dynamic>;
  if (data['schemaVersion'] != 1) throw const FormatException();
  final syncedAt = activityDate(data['syncedAt']);
  if (syncedAt == null) throw const FormatException();
  final tracks = (data['tracks'] as List).map((entry) {
    final json = entry as Map<String, dynamic>;
    final track = Track.fromJson(json);
    return Track(
      id: track.id,
      title: track.title,
      artist: track.artist,
      album: track.album,
      duration: Duration(milliseconds: json['durationMs'] as int),
      number: track.number,
      coverArt: track.coverArt,
      starred: track.starred,
      addedAt: track.addedAt,
      lastPlayedAt: track.lastPlayedAt,
      playCount: track.playCount,
      invalidActivityDates: json['invalidActivityDates'] as bool,
      albumId: track.albumId,
      artistId: track.artistId,
      container: track.container,
      bitRate: track.bitRate,
      userRating: track.userRating,
      genres: track.genres,
      year: track.year,
    );
  }).toList();
  if (tracks.any((t) => t.id.isEmpty) ||
      tracks.map((t) => t.id).toSet().length != tracks.length) {
    throw const FormatException();
  }
  final listens = (data['listens'] as Map<String, dynamic>).map((id, entry) {
    final date = activityDate(entry['startedAt']);
    final count = entry['minimumCount'] as int;
    if (date == null || count < 0) throw const FormatException();
    return MapEntry(id, CachedListen(date, count));
  });
  return CatalogSnapshot(
    syncedAt: syncedAt,
    syncedTrackCount: data['syncedTrackCount'] as int?,
    tracks: tracks,
    listens: listens,
    favorites: (data['favorites'] as Map).cast<String, bool>(),
    ratings: ((data['ratings'] as Map?) ?? {}).map((key, value) {
      if (value is! int || value < 0 || value > 5) {
        throw const FormatException();
      }
      return MapEntry(key as String, value);
    }),
  );
}
