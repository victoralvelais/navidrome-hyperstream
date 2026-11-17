import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/library.dart';
import '../models/source_reference.dart';
import 'mornye_sources.dart';
import 'music_provider.dart';
import 'source_stream_proxy.dart';
import 'remote_transfer_background.dart';

class MornyeProvider implements MusicProvider {
  MornyeProvider(this.sources, this.extensionId, this.proxy);
  final MornyeSources sources;
  final String extensionId;
  final SourceStreamProxy proxy;
  @override
  String get id => 'mornye:$extensionId';
  @override
  String get name => sources.name(extensionId);

  Future<dynamic> _call(String method, List<dynamic> args) => sources.execute({
    'op': 'call',
    'id': extensionId,
    'method': method,
    'args': args,
  });

  @override
  Future<SourceSearch> search(String query) async {
    final link = Uri.tryParse(query);
    if (link != null && link.hasScheme) {
      if (!acceptsLink(extensionId, link)) {
        throw const SourceException(
          'Choose the matching source for this music link. Public song, album and playlist links are supported.',
        );
      }
      final kindIndex = link.pathSegments.indexWhere(
        (p) => ['playlist', 'album', 'track'].contains(p),
      );
      final kind = kindIndex >= 0 && kindIndex + 1 < link.pathSegments.length
          ? link.pathSegments[kindIndex]
          : null;
      final collectionId = kind == null
          ? null
          : link.pathSegments[kindIndex + 1];
      final response = kind == null
          ? await _call('handleUrl', [query])
          : await _call(
              switch (kind) {
                'playlist' => 'getPlaylist',
                'album' => 'getAlbum',
                _ => 'getTrack',
              },
              [collectionId],
            );
      final result = kind == 'track' ? {'track': response} : response;
      if (result is! Map) {
        throw const SourceException('This link did not return music.');
      }
      final tracks = result['tracks'] ?? result['track_list'];
      if (tracks is List) {
        final collection = result['album'] is Map
            ? result['album'] as Map
            : result;
        return SourceSearch(
          tracks: const [],
          albums: [
            SourceAlbum(
              id: collectionId == null
                  ? 'link:$query'
                  : '${kind == 'playlist' ? 'playlist:' : ''}$collectionId',
              sourceId: id,
              title: _string(collection['name'], 'Shared playlist'),
              artist: _string(
                collection['artists'],
                kind == 'playlist' || result['type'] == 'playlist'
                    ? 'Playlist'
                    : name,
              ),
              artwork: publicArtwork(
                collection['cover_url'] ?? result['cover_url'],
              ),
              trackCount: _count(collection['total_tracks']) ?? tracks.length,
            ),
          ],
        );
      }
      final track = result['track'];
      if (track is Map) {
        return SourceSearch(
          tracks: [parseTrack(extensionId, track)],
          albums: const [],
        );
      }
      throw const SourceException(
        'This link has no playable songs. Try a public song, album or playlist link.',
      );
    }
    final response = await _call('customSearch', [
      query,
      {'limit': 30, 'type': 'all'},
    ]);
    return parseSearch(extensionId, response);
  }

  static bool acceptsLink(String id, Uri uri) {
    if (uri.scheme != 'https' || uri.userInfo.isNotEmpty) return false;
    final host = uri.host.toLowerCase();
    return switch (id) {
      'spotify-web' => host == 'open.spotify.com',
      'tidal-web' => [
        'tidal.com',
        'www.tidal.com',
        'listen.tidal.com',
      ].contains(host),
      'qobuz-web' => [
        'qobuz.com',
        'www.qobuz.com',
        'open.qobuz.com',
        'play.qobuz.com',
      ].contains(host),
      _ => false,
    };
  }

  @override
  Future<List<Track>> album(SourceAlbum album) async {
    final fromLink = album.id.startsWith('link:');
    final playlist = album.id.startsWith('playlist:');
    final result = await _call(
      fromLink
          ? 'handleUrl'
          : playlist
          ? 'getPlaylist'
          : 'getAlbum',
      [
        fromLink
            ? album.id.substring(5)
            : playlist
            ? album.id.substring(9)
            : album.id,
      ],
    );
    if (result is! Map) {
      throw const SourceException('This collection could not load.');
    }
    final raw = result['tracks'] ?? result['track_list'];
    if (raw is! List) {
      throw const SourceException('This collection did not return its songs.');
    }
    final expected = _count(result['total_tracks']) ?? album.trackCount;
    if (expected != null && raw.length != expected) {
      throw const SourceException(
        'This source returned an incomplete collection. Try again before downloading it.',
      );
    }
    // Playlist order and repeated songs are intentional. Never album-sort them.
    return raw
        .whereType<Map>()
        .map(
          (e) => parseTrack(
            extensionId,
            e,
            album: fromLink || playlist ? null : album,
          ),
        )
        .toList();
  }

  @override
  Uri streamUri(SourceReference track) => proxy.uri(track);

  @override
  Future<http.StreamedResponse> download(
    SourceReference track,
    Future<void> abort,
  ) async {
    final audio = await MornyeAcquisition(sources).download(track, abort);
    Stream<List<int>> content() async* {
      try {
        yield* audio.file.openRead();
      } finally {
        await audio.dispose();
      }
    }

    return http.StreamedResponse(
      content(),
      200,
      contentLength: await audio.file.length(),
      headers: {'content-type': audioMime(audio.file.path)},
    );
  }

  @override
  void close() {}

  static SourceSearch parseSearch(String id, dynamic result) {
    final raw = result is List
        ? result
        : result is Map
        ? result['tracks'] ?? result['results'] ?? []
        : [];
    final albums = result is Map
        ? result['albums']
        : raw is List
        ? raw
              .whereType<Map>()
              .where((e) => ['album', 'playlist'].contains(e['item_type']))
              .toList()
        : null;
    return SourceSearch(
      tracks: raw is List
          ? raw
                .whereType<Map>()
                .where(
                  (e) =>
                      e['id'] != null &&
                      (e['item_type'] == null || e['item_type'] == 'track'),
                )
                .map((e) => parseTrack(id, e))
                .toList()
          : [],
      albums: albums is List
          ? albums
                .whereType<Map>()
                .where((e) => e['id'] != null)
                .map(
                  (e) => SourceAlbum(
                    id: '${e['item_type'] == 'playlist' ? 'playlist:' : ''}${e['id']}',
                    sourceId: 'mornye:$id',
                    title: _string(e['name'], 'Album'),
                    artist: _string(
                      e['artists'] ?? e['artist'],
                      'Unknown artist',
                    ),
                    artwork: publicArtwork(e['cover_url'] ?? e['images']),
                    trackCount: _count(e['total_tracks']),
                  ),
                )
                .toList()
          : [],
    );
  }

  static Track parseTrack(String id, Map raw, {SourceAlbum? album}) {
    final trackId = raw['id']?.toString() ?? '';
    if (trackId.isEmpty) {
      throw const SourceException(
        'This source returned a song without an identity.',
      );
    }
    final albumId = raw['album_id']?.toString() ?? album?.id;
    final source = SourceReference(
      sourceId: 'mornye:$id',
      trackId: trackId,
      albumId: albumId,
      artwork:
          publicArtwork(
            raw['cover_url'] ?? raw['images'] ?? raw['image_url'],
          ) ??
          album?.artwork,
      isrc: raw['isrc'] as String?,
      disc: (_integer(raw['disc_number']) ?? 1).clamp(1, 999),
      available: raw['is_playable'] != false && raw['available'] != false,
    );
    return Track(
      id: 'external:${source.sourceId}:$trackId',
      title: _string(raw['name'] ?? raw['title'], 'Untitled track'),
      artist: _string(raw['artists'] ?? raw['artist'], 'Unknown artist'),
      album: _string(raw['album_name'] ?? raw['album'], album?.title ?? ''),
      duration: Duration(milliseconds: _integer(raw['duration_ms']) ?? 0),
      number: _integer(raw['track_number']),
      albumId: albumId,
      source: source,
    );
  }
}

String _string(dynamic value, String fallback) =>
    value is String && value.isNotEmpty ? value : fallback;
int? _integer(dynamic value) =>
    value is num ? value.toInt() : int.tryParse('$value');
int? _count(dynamic value) {
  final count = _integer(value);
  return count != null && count > 0 ? count : null;
}

String audioMime(String file) => switch (file.toLowerCase().split('.').last) {
  'mp3' => 'audio/mpeg',
  'm4a' || 'mp4' => 'audio/mp4',
  'aac' => 'audio/aac',
  'ogg' || 'opus' => 'audio/ogg',
  _ => 'audio/flac',
};

class PreparedSourceAudio {
  PreparedSourceAudio(this.file, this.directory);
  final File file;
  final Directory directory;
  Future<void> dispose() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}

class MornyeAcquisition {
  MornyeAcquisition(this.sources);
  final MornyeSources sources;

  Future<(String, String)> match(
    SourceReference track,
    Future<void> abort,
  ) async {
    final catalog = track.sourceId.replaceFirst('mornye:', '');
    if (!sources.has(catalog)) {
      throw const SourceException(
        'Enable this song’s source in Music sources.',
      );
    }
    if (catalog != 'spotify-web') return (catalog, track.trackId);
    final audio = sources.audioProvider;
    if (audio == null || !sources.has(audio)) {
      throw const SourceException(
        'Choose Tidal or Qobuz as your audio source in Music sources.',
      );
    }
    final original = await sources.execute({
      'op': 'call',
      'id': catalog,
      'method': 'getTrack',
      'args': [track.trackId],
    }, abort: abort);
    if (original is! Map) {
      throw const SourceException('The source could not identify this song.');
    }
    final result = await sources.execute({
      'op': 'call',
      'id': audio,
      'method': 'checkAvailability',
      'args': [
        original['isrc'] ?? '',
        original['name'] ?? '',
        original['artists'] ?? '',
        {
          'spotify_id': track.trackId,
          'duration_ms': original['duration_ms'] ?? 0,
          'track': original,
        },
      ],
    }, abort: abort);
    if (result is! Map ||
        result['available'] != true ||
        result['track_id'] == null) {
      throw const SourceException(
        'No matching recording was found on your audio source. Try another source.',
      );
    }
    return (audio, result['track_id'].toString());
  }

  Future<Map<String, dynamic>> resolve(
    SourceReference track,
    Future<void> abort,
  ) async {
    final (id, trackId) = await match(track, abort);
    final result = await sources.execute({
      'op': 'call',
      'id': id,
      'method': 'hyperstreamResolve',
      'args': [trackId, id == 'tidal-web' ? 'HIGH' : 'LOSSLESS'],
    }, abort: abort);
    if (result is! Map) {
      throw const SourceException('This source did not return playable audio.');
    }
    return Map<String, dynamic>.from(result);
  }

  Future<PreparedSourceAudio> download(
    SourceReference track,
    Future<void> abort,
  ) async {
    final directory = await Directory('${sources.root!.path}/downloads')
        .createTemp('audio-');
    var cancelled = false;
    unawaited(abort.then((_) => cancelled = true));
    try {
      await RemoteTransferBackground().prepareDirectory(directory);
      final (id, trackId) = await match(track, abort);
      if (cancelled) throw const SourceException('Import cancelled.');
      final result = await sources.execute({
        'op': 'download',
        'id': id,
        'method': 'hyperstreamDownload',
        'directory': directory.path,
        'args': [trackId, 'LOSSLESS', '${directory.path}/source.flac'],
      }, abort: abort);
      if (cancelled) throw const SourceException('Import cancelled.');
      if (result is! Map ||
          result['success'] != true ||
          result['file_path'] is! String) {
        throw const SourceException(
          'The provider did not finish downloading this song.',
        );
      }
      final file = File(result['file_path'] as String);
      final path = await file.resolveSymbolicLinks();
      final root = await directory.resolveSymbolicLinks();
      if (!path.startsWith('$root${Platform.pathSeparator}') ||
          await file.length() == 0) {
        throw const SourceException(
          'The provider returned an invalid audio file.',
        );
      }
      return PreparedSourceAudio(file, directory);
    } on Object {
      if (await directory.exists()) await directory.delete(recursive: true);
      rethrow;
    }
  }
}
