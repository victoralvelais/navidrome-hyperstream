import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/library.dart';
import 'navidrome_client.dart';

/// Queue metadata only. Authenticated URLs, audio and listen credit are never saved.
class PlaybackSnapshot {
  const PlaybackSnapshot({
    required this.tracks,
    required this.coverArtIds,
    required this.index,
    required this.position,
    this.shuffleOrder = const [],
    this.repeat = 'off',
    this.speed = 1,
  });

  final List<Track> tracks;
  final List<String?> coverArtIds;
  final int index;
  final Duration position;
  // Empty means shuffle is off; otherwise this is a permutation of queue positions.
  final List<int> shuffleOrder;
  final String repeat;
  final double speed;

  Duration get safePosition {
    final duration = tracks[index].duration;
    if (position < Duration.zero) return Duration.zero;
    // A completed queue reopens at the beginning of its last song, paused.
    if (duration > Duration.zero && position >= duration) return Duration.zero;
    return position;
  }

  Map<String, Object?> get progress => {
    'index': index,
    'positionMs': position.inMilliseconds,
    'repeat': repeat,
    'speed': speed,
  };

  void validate() {
    if (tracks.isEmpty ||
        tracks.length > 100000 ||
        index < 0 ||
        index >= tracks.length ||
        coverArtIds.length != tracks.length ||
        !const ['off', 'one', 'all'].contains(repeat) ||
        !speed.isFinite ||
        speed < .5 ||
        speed > 2 ||
        position.isNegative ||
        position.inDays > 365 ||
        tracks.any((track) => track.id.isEmpty || track.duration.isNegative)) {
      throw const FormatException('Invalid saved playback');
    }
    if (shuffleOrder.isNotEmpty &&
        (shuffleOrder.length != tracks.length ||
            shuffleOrder.toSet().length != tracks.length ||
            shuffleOrder.any((i) => i < 0 || i >= tracks.length))) {
      throw const FormatException('Invalid saved order');
    }
  }
}

abstract interface class PlaybackStore {
  Future<PlaybackSnapshot?> read();
  Future<void> write(PlaybackSnapshot snapshot);
  Future<void> clear();
}

/// A large queue is written only when its membership/order changes. Small
/// checkpoints reference that queue's generation, so an interrupted pair of
/// atomic writes can never apply an old position to a new queue.
class FilePlaybackStore implements PlaybackStore {
  FilePlaybackStore(
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
  static final _pending = <String, Future<void>>{};
  PlaybackSnapshot? _last;
  String? _generation;

  Future<Directory> _folder() async =>
      Directory('${(await _directory()).path}/playback-v1/$accountKey');

  Future<T> _serialize<T>(Future<T> Function() action) {
    final result = (_pending[accountKey] ?? Future<void>.value()).then(
      (_) => action(),
    );
    final settled = result.then<void>((_) {}, onError: (Object _) {});
    _pending[accountKey] = settled;
    unawaited(
      settled.then((_) {
        if (identical(_pending[accountKey], settled)) {
          _pending.remove(accountKey);
        }
      }),
    );
    return result;
  }

  @override
  Future<PlaybackSnapshot?> read() => _serialize(() async {
    final folder = await _folder();
    final file = File('${folder.path}/queue.json');
    if (!await file.exists()) return null;
    if (await file.length() > 128 * 1024 * 1024) throw const FormatException();
    final decoded = await compute(_decodeQueue, await file.readAsString());
    var snapshot = decoded.$2;
    final checkpoint = File('${folder.path}/position.json');
    if (await checkpoint.exists()) {
      try {
        if (await checkpoint.length() > 4096) throw const FormatException();
        final data =
            jsonDecode(await checkpoint.readAsString()) as Map<String, dynamic>;
        if (data['generation'] == decoded.$1 && data['schemaVersion'] == 1) {
          snapshot = _withProgress(snapshot, data);
        }
      } on FormatException {
        // A bad checkpoint still leaves the queue's initial position usable.
      } on TypeError {
        // Same fallback for malformed scalar types.
      }
    }
    _generation = decoded.$1;
    _last = snapshot;
    return snapshot;
  });

  @override
  Future<void> write(PlaybackSnapshot snapshot) => _serialize(() async {
    final folder = await _folder();
    await folder.create(recursive: true);
    final changed =
        _last == null ||
        !identical(_last!.tracks, snapshot.tracks) ||
        !listEquals(_last!.coverArtIds, snapshot.coverArtIds) ||
        !listEquals(_last!.shuffleOrder, snapshot.shuffleOrder);
    if (changed) {
      snapshot.validate();
      final generation =
          '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
      final encoded = await compute(_encodeQueue, (generation, snapshot));
      await _replace(File('${folder.path}/queue.json'), encoded);
      _generation = generation;
    }
    await _replace(
      File('${folder.path}/position.json'),
      jsonEncode({
        'schemaVersion': 1,
        'generation': _generation,
        ...snapshot.progress,
      }),
    );
    _last = snapshot;
  });

  @override
  Future<void> clear() => _serialize(() async {
    final folder = await _folder();
    // Delete only our named files; no recursive filesystem operations.
    for (final name in [
      'queue.json',
      'position.json',
      'queue.json.tmp',
      'position.json.tmp',
    ]) {
      final file = File('${folder.path}/$name');
      if (await file.exists()) await file.delete();
    }
    _last = null;
    _generation = null;
  });
}

Future<void> _replace(File file, String contents) async {
  final temporary = File('${file.path}.tmp');
  await temporary.writeAsString(contents, flush: true);
  await temporary.rename(file.path);
}

String _encodeQueue((String, PlaybackSnapshot) value) => jsonEncode({
  'schemaVersion': 1,
  'generation': value.$1,
  ...value.$2.progress,
  'shuffleOrder': value.$2.shuffleOrder,
  'coverArtIds': value.$2.coverArtIds,
  'tracks': [
    for (final track in value.$2.tracks)
      {
        'id': track.id,
        'title': track.title,
        'artist': track.artist,
        'album': track.album,
        'duration': track.duration.inSeconds,
        'track': track.number,
        'coverArt': track.coverArt,
        'starred': track.starred ? true : null,
        'created': track.addedAt?.toUtc().toIso8601String(),
        'played': track.lastPlayedAt?.toUtc().toIso8601String(),
        'playCount': track.playCount,
        'albumId': track.albumId,
        'artistId': track.artistId,
        'suffix': track.container,
        'bitRate': track.bitRate,
        'userRating': track.userRating,
      },
  ],
});

(String, PlaybackSnapshot) _decodeQueue(String raw) {
  final data = jsonDecode(raw) as Map<String, dynamic>;
  if (data['schemaVersion'] != 1 || data['generation'] is! String) {
    throw const FormatException();
  }
  final entries = data['tracks'] as List;
  if (entries.length > 100000) throw const FormatException();
  final snapshot = PlaybackSnapshot(
    tracks: List.unmodifiable(
      entries.map((e) => Track.fromJson(e as Map<String, dynamic>)),
    ),
    coverArtIds: List<String?>.unmodifiable(data['coverArtIds'] as List),
    shuffleOrder: List<int>.unmodifiable(data['shuffleOrder'] as List),
    index: data['index'] as int,
    position: Duration(milliseconds: data['positionMs'] as int),
    repeat: data['repeat'] as String,
    speed: (data['speed'] as num).toDouble(),
  );
  snapshot.validate();
  return (data['generation'] as String, snapshot);
}

PlaybackSnapshot _withProgress(
  PlaybackSnapshot queue,
  Map<String, dynamic> data,
) {
  final snapshot = PlaybackSnapshot(
    tracks: queue.tracks,
    coverArtIds: queue.coverArtIds,
    shuffleOrder: queue.shuffleOrder,
    index: data['index'] as int,
    position: Duration(milliseconds: data['positionMs'] as int),
    repeat: data['repeat'] as String,
    speed: (data['speed'] as num).toDouble(),
  );
  snapshot.validate();
  return snapshot;
}
