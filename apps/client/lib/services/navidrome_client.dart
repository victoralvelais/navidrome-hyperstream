import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../models/library.dart';

/// User-facing failures deliberately exclude request URLs and server messages:
/// OpenSubsonic URLs contain replayable authentication tokens.
class NavidromeException implements Exception {
  const NavidromeException(this.message, {this.authenticationRejected = false});
  final String message;
  final bool authenticationRejected;

  @override
  String toString() => message;
}

/// A qualified local listen, independent of acknowledgement by the server.
class LocalListen {
  const LocalListen(this.track, this.startedAt);
  final Track track;
  final DateTime startedAt;
}

class NavidromeClient {
  NavidromeClient({
    required String serverUrl,
    required this.username,
    required this._password,
    http.Client? httpClient,
  }) : baseUri = parseServerUrl(serverUrl),
       _http = httpClient ?? http.Client();

  final Uri baseUri;
  final String username;
  final String _password;
  final http.Client _http;
  final Random _random = Random.secure();
  final _listens = StreamController<LocalListen>.broadcast();
  final _favoriteChanges = StreamController<(String, bool)>.broadcast();
  bool _closed = false;
  String? _countToken;
  String? serverType;
  String? serverVersion;
  bool openSubsonic = false;
  Stream<LocalListen> get localListens => _listens.stream;
  Stream<(String, bool)> get favoriteChanges => _favoriteChanges.stream;

  void recordLocalListen(Track track, DateTime startedAt) {
    if (!_closed) _listens.add(LocalListen(track, startedAt.toUtc()));
  }

  static Uri parseServerUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const NavidromeException(
        'Enter an http:// or https:// server address without credentials, '
        'query parameters, or a fragment.',
      );
    }
    // A trailing slash preserves a reverse proxy's path prefix on resolve().
    return uri.replace(path: '${uri.path.replaceFirst(RegExp(r'/+$'), '')}/');
  }

  Uri _endpoint(String method, [Map<String, dynamic> parameters = const {}]) {
    final salt = List.generate(
      16,
      (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    return baseUri
        .resolve('rest/$method.view')
        .replace(
          queryParameters: {
            'u': username,
            't': md5.convert(utf8.encode('$_password$salt')).toString(),
            's': salt,
            'v': '1.16.1',
            'c': 'hyperstream',
            'f': 'json',
            ...parameters,
          },
        );
  }

  Future<http.Response> _get(Uri uri, {bool post = false}) async {
    try {
      // Do not forward credential-bearing requests through HTTP redirects.
      // Users should configure the final server URL (including its subpath).
      final request = http.Request(
        post ? 'POST' : 'GET',
        post ? uri.replace(query: '') : uri,
      )..followRedirects = false;
      if (post) {
        request.headers['content-type'] = 'application/x-www-form-urlencoded';
        request.body = uri.query;
      }
      final response = await _http
          .send(request)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode >= 300 && response.statusCode < 400) {
        throw const NavidromeException(
          'The server redirected this request. Enter its final address.',
        );
      }
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const NavidromeException(
          'Check your username and password.',
          authenticationRejected: true,
        );
      }
      if (response.statusCode != 200) {
        throw NavidromeException(
          'The server returned HTTP ${response.statusCode}.',
        );
      }
      return response;
    } on NavidromeException {
      rethrow;
    } on TimeoutException {
      throw const NavidromeException(
        'The server took too long to respond. Try again.',
      );
    } on Exception {
      throw const NavidromeException(
        'Could not reach the server. Check its address and your connection.',
      );
    }
  }

  Future<Map<String, dynamic>> _request(
    String method, [
    Map<String, dynamic> parameters = const {},
  ]) async {
    final response = await _get(
      _endpoint(method, parameters),
      post: parameters.values.any((value) => value is List),
    );
    try {
      final body =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final envelope = body['subsonic-response'] as Map<String, dynamic>;
      if (envelope['status'] != 'ok') {
        final error = envelope['error'] as Map<String, dynamic>?;
        final code = error?['code'];
        throw NavidromeException(switch (code) {
          40 || 41 || 44 => 'Check your username and password.',
          50 => 'Your account does not have permission for this action.',
          70 => 'This item is no longer available on the server.',
          _ => 'Navidrome could not complete the request.',
        }, authenticationRejected: code == 40 || code == 41 || code == 44);
      }
      serverType = envelope['type'] as String? ?? serverType;
      serverVersion = envelope['serverVersion'] as String? ?? serverVersion;
      openSubsonic = envelope['openSubsonic'] == true || openSubsonic;
      return envelope;
    } on NavidromeException {
      rethrow;
    } on Object {
      throw const NavidromeException(
        'The server returned an unexpected response. Check the Navidrome address.',
      );
    }
  }

  Future<void> ping() async => _request('ping');

  /// Optional native count for the same user's non-missing songs as search3.
  /// Failure never prevents the OpenSubsonic catalog sync. Tokens stay in memory.
  Future<int?> catalogTrackCount({required bool Function() cancelled}) async {
    bool stopped() => _closed || cancelled();
    if (stopped() || serverType?.toLowerCase() != 'navidrome') return null;
    try {
      // A cached expired token may be replaced once. Permission/proxy/network
      // failures fall back to unknown progress without changing sign-in state.
      for (var attempt = 0; attempt < 2 && !stopped(); attempt++) {
        final hadToken = _countToken != null;
        if (!hadToken) {
          final request = http.Request('POST', baseUri.resolve('auth/login'))
            ..followRedirects = false
            ..headers['content-type'] = 'application/json'
            ..body = jsonEncode({'username': username, 'password': _password});
          final response = await _countRequest(request);
          if (stopped() || response.statusCode != 200) return null;
          final data = jsonDecode(utf8.decode(response.bodyBytes));
          if (data is! Map<String, dynamic> ||
              data['username'] is! String ||
              (data['username'] as String).toLowerCase() !=
                  username.toLowerCase()) {
            return null;
          }
          final token = data['token'];
          if (token is! String ||
              token.isEmpty ||
              token.length > 8192 ||
              !RegExp(r'^[A-Za-z0-9._~-]+$').hasMatch(token)) {
            return null;
          }
          _countToken = token;
        }
        if (stopped()) return null;
        final request =
            http.Request(
                'GET',
                baseUri
                    .resolve('api/song')
                    .replace(
                      queryParameters: {
                        '_start': '0',
                        '_end': '1',
                        'missing': 'false',
                      },
                    ),
              )
              ..followRedirects = false
              ..headers['x-nd-authorization'] = 'Bearer $_countToken';
        final response = await _countRequest(request);
        if (stopped()) return null;
        if (response.statusCode == 401) {
          _countToken = null;
          if (hadToken && attempt == 0) continue;
          return null;
        }
        if (response.statusCode != 200) return null;
        final header = response.headers['x-total-count']?.trim();
        if (header == null || !RegExp(r'^\d+$').hasMatch(header)) return null;
        final count = int.tryParse(header);
        final rows = jsonDecode(utf8.decode(response.bodyBytes));
        if (count == null ||
            count < 0 ||
            rows is! List ||
            rows.length > 1 ||
            (count == 0) != rows.isEmpty ||
            rows.any(
              (row) =>
                  row is! Map<String, dynamic> ||
                  row['id'] is! String ||
                  (row['id'] as String).isEmpty ||
                  row['missing'] == true,
            )) {
          return null;
        }
        return count;
      }
    } on Object {
      // Optional native API: never expose URLs, tokens or server response text.
    }
    return null;
  }

  Future<http.Response> _countRequest(http.Request request) => _http
      .send(request)
      .then(http.Response.fromStream)
      .timeout(const Duration(seconds: 4));

  /// No retries: a lost response may follow a successfully recorded listen.
  Future<void> scrobble(String trackId, DateTime startedAt) async {
    if (_closed) throw const NavidromeException('This connection has closed.');
    await _request('scrobble', {
      'id': trackId,
      'time': '${startedAt.toUtc().millisecondsSinceEpoch}',
      'submission': 'true',
    });
  }

  Future<Track> song(String id) async {
    final data = await _request('getSong', {'id': id});
    try {
      return Track.fromJson(data['song'] as Map<String, dynamic>);
    } on Object {
      throw const NavidromeException('The server returned an invalid song.');
    }
  }

  Future<List<Track>> instantMix(String id) async {
    final data = await _request('getSimilarSongs2', {'id': id, 'count': '50'});
    try {
      final songs =
          (data['similarSongs2'] as Map<String, dynamic>?)?['song'] as List? ??
          [];
      final result = <String, Track>{};
      for (final song in songs) {
        final track = Track.fromJson(song as Map<String, dynamic>);
        if (track.id != id) result[track.id] = track;
      }
      if (result.isEmpty) {
        throw const NavidromeException(
          'No similar songs were returned. Your server needs matching music and a configured similarity provider.',
        );
      }
      return result.values.toList();
    } on NavidromeException {
      rethrow;
    } on Object {
      throw const NavidromeException('The server returned an invalid mix.');
    }
  }

  Future<void> setRating(String id, int rating) async {
    if (rating < 0 || rating > 5) {
      throw const NavidromeException('Choose a rating from 0 to 5.');
    }
    await _request('setRating', {'id': id, 'rating': '$rating'});
  }

  Future<String?> lyrics(Track track) async {
    try {
      final data = await _request('getLyricsBySongId', {'id': track.id});
      final entries =
          (data['lyricsList'] as Map<String, dynamic>?)?['structuredLyrics']
              as List? ??
          [];
      for (final entry in entries) {
        final lines = (entry as Map<String, dynamic>)['line'] as List? ?? [];
        final text = lines
            .map(
              (line) =>
                  (line as Map<String, dynamic>)['value'] as String? ?? '',
            )
            .join('\n')
            .trim();
        if (text.isNotEmpty) return text;
      }
    } on NavidromeException catch (error) {
      if (error.authenticationRejected) rethrow;
      // Older servers expose only the artist/title lyrics endpoint.
    } on Object {
      throw const NavidromeException('The server returned invalid lyrics.');
    }
    final data = await _request('getLyrics', {
      'artist': track.artist,
      'title': track.title,
    });
    final lyrics =
        (data['lyrics'] as Map<String, dynamic>?)?['value'] as String?;
    return lyrics?.trim().isEmpty == true ? null : lyrics;
  }

  Future<List<Track>> radioTracks({
    required bool Function() cancelled,
    void Function(int)? onProgress,
  }) async {
    final songs = <String, Track>{};
    var offset = 0;
    while (!cancelled()) {
      final page = await search(
        '',
        browse: true,
        albumCount: 0,
        songOffset: offset,
        songCount: 500,
      );
      if (cancelled()) return [];
      if (page.tracks.isEmpty) break;
      final before = songs.length;
      for (final track in page.tracks) {
        songs[track.id] = track;
      }
      if (songs.length == before) {
        throw const NavidromeException(
          'The server repeated a song page. Recent Radio could not load the complete library.',
        );
      }
      offset += page.tracks.length;
      onProgress?.call(songs.length);
      // Continue through short pages: servers may cap the requested page size.
    }
    if (cancelled()) return [];
    if (songs.isNotEmpty && !songs.values.any((s) => s.addedAt != null)) {
      throw const NavidromeException(
        'This server did not provide track addition dates for Recent Radio.',
      );
    }
    if (songs.values.any(
      (s) =>
          s.playCount > 0 && s.lastPlayedAt == null && !s.invalidActivityDates,
    )) {
      throw const NavidromeException(
        'This server returned play counts without play dates. Recent Radio needs both track addition and listening dates.',
      );
    }
    if (songs.isNotEmpty &&
        !songs.values.any((s) => s.lastPlayedAt != null) &&
        !(serverType?.toLowerCase() == 'navidrome' && openSubsonic)) {
      throw const NavidromeException(
        'Listening dates could not be verified on this server. Recent Radio needs OpenSubsonic track history.',
      );
    }
    return songs.values.toList();
  }

  Future<List<Album>> albums({
    int offset = 0,
    int size = 40,
    bool recent = false,
  }) async {
    final data = await _request('getAlbumList2', {
      'type': recent ? 'recent' : 'newest',
      'offset': '$offset',
      'size': '$size',
    });
    try {
      final container = data['albumList2'] as Map<String, dynamic>;
      final items = container['album'] as List<dynamic>? ?? [];
      return items
          .map((item) => Album.fromJson(item as Map<String, dynamic>))
          .toList();
    } on Object {
      throw const NavidromeException(
        'The server returned an invalid album list.',
      );
    }
  }

  Future<List<Track>> tracks(String albumId) async {
    final data = await _request('getAlbum', {'id': albumId});
    try {
      final album = data['album'] as Map<String, dynamic>;
      final items = album['song'] as List<dynamic>? ?? [];
      return items
          .map((item) => Track.fromJson(item as Map<String, dynamic>))
          .toList();
    } on Object {
      throw const NavidromeException(
        'The server returned an invalid track list.',
      );
    }
  }

  Future<List<Album>> discoverAlbums({
    String type = 'random',
    String? genre,
    int offset = 0,
    int size = 40,
  }) async {
    if (![
          'random',
          'newest',
          'frequent',
          'byGenre',
          'starred',
        ].contains(type) ||
        (type == 'byGenre' && (genre == null || genre.isEmpty))) {
      throw const NavidromeException('Choose a discovery category.');
    }
    final data = await _request('getAlbumList2', {
      'type': type,
      'offset': '$offset',
      'size': '$size',
      'genre': ?genre,
    });
    try {
      return (((data['albumList2'] as Map<String, dynamic>)['album']
                  as List?) ??
              [])
          .map((a) => Album.fromJson(a as Map<String, dynamic>))
          .toList();
    } on Object {
      throw const NavidromeException(
        'The server returned an invalid album list.',
      );
    }
  }

  Future<List<String>> genres() async {
    final data = await _request('getGenres');
    try {
      final items =
          ((data['genres'] as Map<String, dynamic>)['genre'] as List?) ?? [];
      final genres =
          items
              .where((g) => (g['albumCount'] as num? ?? 0) > 0)
              .map((g) => g['value'] as String)
              .where((g) => g.trim().isNotEmpty)
              .toSet()
              .toList()
            ..sort();
      return genres;
    } on Object {
      throw const NavidromeException('The server returned invalid genres.');
    }
  }

  // Search the server's entire library, independently of the album browser.
  // OpenSubsonic search3 has separate counts and offsets for each result type.
  Future<LibrarySearchResults> search(
    String query, {
    int albumOffset = 0,
    int songOffset = 0,
    int albumCount = 20,
    int songCount = 20,
    int artistCount = 0,
    int artistOffset = 0,
    bool browse = false,
  }) async {
    if (query.trim().isEmpty && !browse) return const LibrarySearchResults();
    final data = await _request('search3', {
      'query': query.trim(),
      'artistCount': '$artistCount',
      'artistOffset': '$artistOffset',
      'albumCount': '$albumCount',
      'albumOffset': '$albumOffset',
      'songCount': '$songCount',
      'songOffset': '$songOffset',
    });
    try {
      final results = data['searchResult3'] as Map<String, dynamic>;
      return LibrarySearchResults(
        artists: (results['artist'] as List<dynamic>? ?? [])
            .map((item) => Artist.fromJson(item as Map<String, dynamic>))
            .toList(),
        albums: (results['album'] as List<dynamic>? ?? [])
            .map((item) => Album.fromJson(item as Map<String, dynamic>))
            .toList(),
        tracks: (results['song'] as List<dynamic>? ?? [])
            .map((item) => Track.fromJson(item as Map<String, dynamic>))
            .toList(),
      );
    } on Object {
      throw const NavidromeException(
        'The server returned invalid search results.',
      );
    }
  }

  Future<List<Album>> artistAlbums(String id) async {
    final data = await _request('getArtist', {'id': id});
    try {
      final artist = data['artist'] as Map<String, dynamic>;
      return (artist['album'] as List<dynamic>? ?? [])
          .map((item) => Album.fromJson(item as Map<String, dynamic>))
          .toList();
    } on Object {
      throw const NavidromeException('The server returned an invalid artist.');
    }
  }

  Future<List<MusicPlaylist>> playlists() async {
    final data = await _request('getPlaylists');
    try {
      final container = data['playlists'] as Map<String, dynamic>;
      return (container['playlist'] as List<dynamic>? ?? [])
          .map((item) => MusicPlaylist.fromJson(item as Map<String, dynamic>))
          .toList();
    } on Object {
      throw const NavidromeException(
        'The server returned an invalid playlist list.',
      );
    }
  }

  MusicPlaylist _playlistFrom(Map<String, dynamic> data) {
    try {
      return MusicPlaylist.fromJson(data['playlist'] as Map<String, dynamic>);
    } on Object {
      throw const NavidromeException(
        'The server returned an invalid playlist.',
      );
    }
  }

  Future<MusicPlaylist> playlist(String id) async =>
      _playlistFrom(await _request('getPlaylist', {'id': id}));

  Future<MusicPlaylist> createPlaylist(
    String name, {
    String? songId,
    List<String>? songIds,
  }) async {
    if (name.trim().isEmpty) {
      throw const NavidromeException('Enter a playlist name.');
    }
    return _playlistFrom(
      await _request('createPlaylist', {
        'name': name.trim(),
        'songId': ?(songIds ?? songId),
      }),
    );
  }

  Future<void> renamePlaylist(String id, String name) async {
    if (name.trim().isEmpty) {
      throw const NavidromeException('Enter a playlist name.');
    }
    await _request('updatePlaylist', {'playlistId': id, 'name': name.trim()});
  }

  Future<void> addToPlaylist(String id, String songId) async {
    await _request('updatePlaylist', {'playlistId': id, 'songIdToAdd': songId});
  }

  Future<void> addSongsToPlaylist(String id, List<String> songIds) async {
    if (songIds.isEmpty) return;
    await _request('updatePlaylist', {
      'playlistId': id,
      'songIdToAdd': songIds,
    });
  }

  Future<void> removeFromPlaylist(MusicPlaylist snapshot, int index) async {
    if (index < 0 || index >= snapshot.tracks.length) {
      throw const NavidromeException('This song is no longer in the playlist.');
    }
    // Subsonic removes by zero-based position, not song ID. Recheck before
    // editing so a stale screen does not remove a different song or duplicate.
    // The protocol offers no atomic compare-and-update across other clients.
    final current = await playlist(snapshot.id);
    if (current.tracks.length != snapshot.tracks.length ||
        current.tracks.indexed.any(
          (entry) => entry.$2.id != snapshot.tracks[entry.$1].id,
        )) {
      throw const NavidromeException(
        'This playlist changed. Refresh it before removing songs.',
      );
    }
    await _request('updatePlaylist', {
      'playlistId': snapshot.id,
      'songIndexToRemove': '$index',
    });
  }

  Future<LibrarySearchResults> favorites() async {
    final data = await _request('getStarred2');
    try {
      final container = data['starred2'] as Map<String, dynamic>;
      return LibrarySearchResults(
        albums: (container['album'] as List<dynamic>? ?? [])
            .map((item) => Album.fromJson(item as Map<String, dynamic>))
            .toList(),
        tracks: (container['song'] as List<dynamic>? ?? [])
            .map((item) => Track.fromJson(item as Map<String, dynamic>))
            .toList(),
      );
    } on Object {
      throw const NavidromeException('The server returned invalid favorites.');
    }
  }

  Future<void> setFavorite(
    String id, {
    required bool album,
    required bool favorite,
  }) async {
    await _request(favorite ? 'star' : 'unstar', {
      album ? 'albumId' : 'id': id,
    });
    if (!album && !_closed) _favoriteChanges.add((id, favorite));
  }

  // These URLs are passed only to the native player, never persisted or logged.
  // Request the existing file without a second lossy transcode.
  Uri streamUri(String trackId) =>
      _endpoint('stream', {'id': trackId, 'format': 'raw'});

  Future<Uint8List> coverArt(String id) async =>
      (await _get(_endpoint('getCoverArt', {'id': id, 'size': '400'})))
          .bodyBytes;

  void close() {
    _closed = true;
    _countToken = null;
    _http.close();
    unawaited(_listens.close());
    unawaited(_favoriteChanges.close());
  }
}
