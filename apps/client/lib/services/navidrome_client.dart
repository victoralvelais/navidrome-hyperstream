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
  const NavidromeException(this.message);
  final String message;

  @override
  String toString() => message;
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

  Uri _endpoint(String method, [Map<String, String> parameters = const {}]) {
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

  Future<http.Response> _get(Uri uri) async {
    try {
      // Do not forward credential-bearing requests through HTTP redirects.
      // Users should configure the final server URL (including its subpath).
      final request = http.Request('GET', uri)..followRedirects = false;
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
        throw const NavidromeException('Check your username and password.');
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
    Map<String, String> parameters = const {},
  ]) async {
    final response = await _get(_endpoint(method, parameters));
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
        });
      }
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

  Future<List<Album>> albums({int offset = 0, int size = 40}) async {
    final data = await _request('getAlbumList2', {
      'type': 'newest',
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

  // Search the server's entire library, independently of the album browser.
  // OpenSubsonic search3 has separate counts and offsets for each result type.
  Future<LibrarySearchResults> search(
    String query, {
    int albumOffset = 0,
    int songOffset = 0,
    int albumCount = 20,
    int songCount = 20,
  }) async {
    if (query.trim().isEmpty) return const LibrarySearchResults();
    final data = await _request('search3', {
      'query': query.trim(),
      'artistCount': '0',
      'albumCount': '$albumCount',
      'albumOffset': '$albumOffset',
      'songCount': '$songCount',
      'songOffset': '$songOffset',
    });
    try {
      final results = data['searchResult3'] as Map<String, dynamic>;
      return LibrarySearchResults(
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

  // These URLs are passed only to the native player, never persisted or logged.
  // Request the existing file without a second lossy transcode.
  Uri streamUri(String trackId) =>
      _endpoint('stream', {'id': trackId, 'format': 'raw'});

  Future<Uint8List> coverArt(String id) async =>
      (await _get(_endpoint('getCoverArt', {'id': id, 'size': '400'})))
          .bodyBytes;

  void close() => _http.close();
}
