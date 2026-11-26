import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/library.dart';
import '../models/source_reference.dart';
import 'playback_diagnostics.dart';

class SourceException implements Exception {
  const SourceException(this.message, {this.retryable = true, this.facts});
  final String message;
  final bool retryable;
  final PlaybackFailureFacts? facts;
  @override
  String toString() => message;
}

class SourceAlbum {
  const SourceAlbum({
    required this.id,
    required this.sourceId,
    required this.title,
    required this.artist,
    this.artwork,
    this.trackCount,
  });
  final String id;
  final String sourceId;
  final String title;
  final String artist;
  final Uri? artwork;
  final int? trackCount;
}

class SourceSearch {
  const SourceSearch({required this.tracks, required this.albums});
  final List<Track> tracks;
  final List<SourceAlbum> albums;
}

abstract interface class MusicProvider {
  String get id;
  String get name;
  Future<SourceSearch> search(String query, {Future<void>? abort});
  Future<List<Track>> album(SourceAlbum album);
  Uri streamUri(SourceReference track);
  Future<http.StreamedResponse> download(
    SourceReference track,
    Future<void> abort,
  );
  void close();
}

/// Monochrome's tracks API returns stable catalog IDs and range-capable files.
/// Each request uses this provider's transport, isolated from Navidrome auth.
class MonochromeProvider implements MusicProvider {
  MonochromeProvider({
    required this.id,
    required this.baseUri,
    http.Client? client,
  }) : _client = client ?? http.Client();
  @override
  final String id;
  final Uri baseUri;
  final http.Client _client;
  @override
  String get name => 'Monochrome';

  Uri _uri(List<String> path, [Map<String, String>? query]) => baseUri.replace(
    pathSegments: [
      ...baseUri.pathSegments.where((part) => part.isNotEmpty),
      ...path,
    ],
    queryParameters: query,
  );

  Future<Map<String, dynamic>> _json(Uri uri, {Future<void>? cancelled}) async {
    final abort = Completer<void>();
    void cancel() {
      if (!abort.isCompleted) abort.complete();
    }

    if (cancelled != null) unawaited(cancelled.then((_) => cancel()));
    final timer = Timer(const Duration(seconds: 20), cancel);
    try {
      final request =
          http.AbortableRequest('GET', uri, abortTrigger: abort.future)
            ..headers['Accept'] = 'application/json'
            ..followRedirects = false;
      final response = await _client.send(request);
      if (response.statusCode != 200) {
        await response.stream.listen(null).cancel();
        throw SourceException(
          response.statusCode == 429
              ? 'This source is rate-limited. Try again later.'
              : 'This source could not answer the request. Try again.',
        );
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.stream) {
        bytes.add(chunk);
        if (bytes.length > 8 * 1024 * 1024) {
          throw const SourceException('The source response is too large.');
        }
      }
      final value = jsonDecode(utf8.decode(bytes.takeBytes()));
      if (value is! Map<String, dynamic>) throw const FormatException();
      return value;
    } on SourceException {
      rethrow;
    } on Object {
      throw const SourceException(
        'Could not reach this music source. Check your connection and try again.',
      );
    } finally {
      timer.cancel();
      if (!abort.isCompleted) abort.complete();
    }
  }

  @override
  Future<SourceSearch> search(String query, {Future<void>? abort}) async {
    final data = await _json(
      _uri(['search'], {'q': query.trim()}),
      cancelled: abort,
    );
    try {
      return SourceSearch(
        tracks: List.unmodifiable(
          (data['tracks'] as List).map(
            (value) => _track(value as Map<String, dynamic>),
          ),
        ),
        albums: List.unmodifiable(
          (data['releases'] as List).map(
            (value) => _album(value as Map<String, dynamic>),
          ),
        ),
      );
    } on Object {
      throw const SourceException(
        'This source returned an unsupported search response.',
      );
    }
  }

  @override
  Future<List<Track>> album(SourceAlbum album) async {
    if (album.sourceId != id) {
      throw const SourceException(
        'The selected source changed. Search for this album again.',
      );
    }
    final data = await _json(_uri(['releases', _id(album.id)]));
    try {
      final release = _album(data);
      final values = data['tracks'] as List;
      if (release.id != album.id ||
          values.isEmpty ||
          (release.trackCount != null && release.trackCount != values.length)) {
        throw const FormatException();
      }
      final tracks = values
          .map((value) => _track(value as Map<String, dynamic>, album: release))
          .toList();
      if (tracks.map((track) => track.id).toSet().length != tracks.length) {
        throw const FormatException();
      }
      tracks.sort((a, b) {
        final disc = a.source!.disc.compareTo(b.source!.disc);
        return disc == 0 ? (a.number ?? 0).compareTo(b.number ?? 0) : disc;
      });
      return List.unmodifiable(tracks);
    } on Object {
      throw const SourceException(
        'The complete album could not be loaded. Try again before playing or importing it.',
      );
    }
  }

  SourceAlbum _album(Map<String, dynamic> data) => SourceAlbum(
    sourceId: id,
    id: _id(data['releaseId'] ?? data['id']),
    title: data['title'] as String,
    artist: _artist(data),
    artwork: publicArtwork(data['artwork']),
    trackCount: (data['trackCount'] as num?)?.toInt(),
  );

  Track _track(Map<String, dynamic> data, {SourceAlbum? album}) {
    final trackId = _id(data['trackId'] ?? data['id']);
    return Track(
      id: 'external:$id:$trackId',
      title: data['title'] as String,
      artist: _artist(data),
      album: album?.title ?? data['albumTitle'] as String? ?? '',
      duration: Duration(
        milliseconds: (data['duration'] as num?)?.round() ?? 0,
      ),
      number: (data['trackNumber'] as num?)?.toInt(),
      source: SourceReference(
        sourceId: id,
        trackId: trackId,
        albumId: album?.id ?? data['releaseId']?.toString(),
        artwork: publicArtwork(data['artwork']) ?? album?.artwork,
        isrc: data['isrc'] as String?,
        disc: (data['discNumber'] as num?)?.toInt() ?? 1,
        available: data['playable'] != false,
      ),
    );
  }

  String _id(Object? value) {
    final id = value?.toString() ?? '';
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(id)) {
      throw const FormatException();
    }
    return id;
  }

  String _artist(Map<String, dynamic> data) {
    final names = data['artistNames'] as List?;
    if (names != null && names.isNotEmpty) {
      return names.cast<String>().join(', ');
    }
    final artists = data['artists'] as List? ?? [];
    return artists.isEmpty
        ? 'Unknown artist'
        : artists.map((a) => (a as Map)['name'] as String).join(', ');
  }

  @override
  Uri streamUri(SourceReference track) {
    if (!track.available) {
      throw const SourceException(
        'This recording is unavailable from the selected source.',
      );
    }
    if (track.sourceId != id) {
      throw const SourceException(
        'This recording belongs to a different source.',
      );
    }
    return _uri(['track', _id(track.trackId)]);
  }

  @override
  Future<http.StreamedResponse> download(
    SourceReference track,
    Future<void> abort,
  ) async {
    final cancelled = Completer<void>();
    void cancel() {
      if (!cancelled.isCompleted) cancelled.complete();
    }

    unawaited(abort.then((_) => cancel()));
    final timeout = Timer(const Duration(seconds: 30), cancel);
    try {
      final response = await _client.send(
        http.AbortableRequest(
          'GET',
          streamUri(track),
          abortTrigger: cancelled.future,
        )..followRedirects = false,
      );
      if (response.statusCode != 200) {
        await response.stream.listen(null).cancel();
        throw const SourceException(
          'The source could not provide the complete audio file. Try again later.',
        );
      }
      return response;
    } on SourceException {
      rethrow;
    } on Object {
      throw const SourceException(
        'The external audio download could not start.',
      );
    } finally {
      timeout.cancel();
    }
  }

  @override
  void close() => _client.close();
}
