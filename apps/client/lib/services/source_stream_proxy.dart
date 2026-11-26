import 'dart:async';
import 'dart:io';

import '../models/source_reference.dart';
import 'mornye_provider.dart';
import 'mornye_sources.dart';
import 'music_provider.dart';

/// Lazy, range-preserving URLs for the native queue. Only the loopback listener
/// knows these per-launch tokens; resolved provider URLs never enter queue JSON.
class SourceStreamProxy {
  SourceStreamProxy(
    this.sources, {
    this.resolve,
    this.onMedia,
    HttpClient Function()? client,
  }) : _client = client ?? HttpClient.new;
  final HttpClient Function() _client;
  final Future<SourceStreamMedia> Function(SourceReference)? resolve;
  final MornyeSources sources;
  final void Function(SourceReference, SourcePlaybackInfo)? onMedia;
  HttpServer? _server;
  var _token = MornyeSources.nonce();
  final _tracks = <String, SourceReference>{};
  var _media = <String, Future<SourceStreamMedia>>{};
  var _clients = <HttpClient>{};
  var _closed = Completer<void>();
  bool get started => _server != null;
  Future<void> start() async {
    if (_server != null) return;
    if (_closed.isCompleted) _closed = Completer<void>();
    _server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
      shared: false,
    );
    _server!.listen((request) => unawaited(_serve(request)));
  }

  Uri uri(SourceReference track) {
    if (_server == null) {
      throw const SourceException(
        'Music playback is still starting. Try again.',
      );
    }
    final id = '${track.sourceId}/${track.trackId}';
    _tracks[id] = track;
    return Uri(
      scheme: 'http',
      host: '127.0.0.1',
      port: _server!.port,
      pathSegments: [_token, id],
    );
  }

  Future<SourceStreamMedia> _resolve(
    String id,
    SourceReference track,
    Map<String, Future<SourceStreamMedia>> cache,
    Future<void> abort, {
    bool refresh = false,
  }) async {
    if (refresh) {
      final old = cache.remove(id);
      if (old != null) {
        try {
          await (await old).file?.dispose();
        } on Object {
          /* In use by an older request. */
        }
      }
    }
    final existing = cache[id];
    if (existing != null) return existing;
    // Insert before running the resolver, including a synchronous failure.
    final pending = Future<SourceStreamMedia>.microtask(() async {
      if (resolve != null) return await resolve!(track);
      final acquisition = MornyeAcquisition(sources);
      Future<PreparedSourceAudio> prepare() =>
          acquisition.download(track, abort, forPlayback: true);
      final result = await acquisition.resolve(track, abort);
      if (result['prepare'] == true) {
        return SourceStreamMedia(file: await prepare());
      }
      final uri = Uri.tryParse(result['url'] as String? ?? '');
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          InternetAddress.tryParse(uri.host) != null ||
          uri.host == 'localhost') {
        throw const SourceException(
          'This source did not return a valid stream.',
        );
      }
      return SourceStreamMedia(
        uri: uri,
        sourceId: result['sourceId'] as String?,
        format: result['format'] as String?,
        headers: result['headers'] is Map
            ? Map<String, dynamic>.from(result['headers'] as Map)
            : const {},
        prepare: result['prepareOnFailure'] == true ? prepare : null,
      );
    });
    cache[id] = pending;
    try {
      return await pending;
    } on Object {
      if (identical(cache[id], pending)) cache.remove(id);
      rethrow;
    }
  }

  Future<void> _serve(HttpRequest request) async {
    // Old requests keep their own cache/cancellation generation. A late failure
    // must never remove a replacement stream or overwrite its error state.
    final closed = _closed;
    final cache = _media;
    final clients = _clients;
    final client = _client()..connectionTimeout = const Duration(seconds: 30);
    clients.add(client);
    String? id;
    SourceStreamMedia? usedMedia;
    var servingAudio = false;
    void ready() {
      servingAudio = true;
      if (!closed.isCompleted) {
        sources.issue.value = null;
        final track = _tracks[request.uri.pathSegments[1]];
        final media = usedMedia;
        if (track != null && media != null) {
          onMedia?.call(
            track,
            SourcePlaybackInfo(
              sourceId:
                  media.file?.sourceId ?? media.sourceId ?? track.sourceId,
              format: media.file?.file.path.split('.').last ?? media.format,
            ),
          );
        }
      }
    }

    try {
      final parts = request.uri.pathSegments;
      final track = parts.length == 2 && parts[0] == _token
          ? _tracks[parts[1]]
          : null;
      if (track == null || !['GET', 'HEAD'].contains(request.method)) {
        request.response.statusCode = HttpStatus.notFound;
        return;
      }
      id = '${parts[1]}@${sources.revision}';
      if (!sources.has(track.sourceId.replaceFirst('mornye:', ''))) {
        throw const SourceException('Enable this provider in Music sources.');
      }
      var media = await _resolve(id, track, cache, closed.future);
      if (closed.isCompleted) return;
      usedMedia = media;
      if (media.file == null &&
          DateTime.now().difference(media.created) >
              const Duration(minutes: 5)) {
        media = await _resolve(id, track, cache, closed.future, refresh: true);
        if (closed.isCompleted) return;
        usedMedia = media;
      }
      if (media.file case final prepared?) {
        await _serveFile(request, prepared.file, onReady: ready);
      } else {
        HttpClientResponse? upstream;
        for (var attempt = 0; attempt < 2; attempt++) {
          upstream = await _open(client, request, media);
          if (closed.isCompleted) return;
          if (![401, 403].contains(upstream.statusCode) || attempt == 1) break;
          await upstream.drain<void>();
          media = await _resolve(
            id,
            track,
            cache,
            closed.future,
            refresh: true,
          );
          if (closed.isCompleted) return;
          usedMedia = media;
          if (media.file != null) {
            await _serveFile(request, media.file!.file, onReady: ready);
            return;
          }
        }
        if (upstream == null ||
            ![200, 206, 416].contains(upstream.statusCode)) {
          if (media.prepare != null) {
            await upstream?.drain<void>();
            if (closed.isCompleted) return;
            // Share preparation with concurrent HEAD/range requests.
            final prepared = media.prepared ??= media.prepare!().then(
              (file) => SourceStreamMedia(file: file),
            );
            cache[id] = prepared;
            try {
              media = await prepared;
            } on Object {
              if (identical(cache[id], prepared)) cache.remove(id);
              rethrow;
            }
            if (closed.isCompleted) return;
            usedMedia = media;
            await _serveFile(request, media.file!.file, onReady: ready);
            if (!closed.isCompleted) sources.issue.value = null;
            return;
          }
          throw const SourceException(
            'The audio source is unavailable. Try another source.',
          );
        }
        ready();
        request.response.statusCode = upstream.statusCode;
        for (final name in [
          HttpHeaders.contentTypeHeader,
          HttpHeaders.contentLengthHeader,
          HttpHeaders.contentRangeHeader,
          HttpHeaders.acceptRangesHeader,
        ]) {
          final value = upstream.headers.value(name);
          if (value != null) request.response.headers.set(name, value);
        }
        if (request.method == 'GET') {
          await request.response.addStream(
            upstream.timeout(const Duration(seconds: 60)),
          );
        } else {
          await upstream.drain<void>();
        }
      }
      if (!closed.isCompleted) sources.issue.value = null;
    } on Object catch (error) {
      // Do not keep a bad URL, missing prepared file or failed transport around
      // for the next native retry. Successful cached seeks are unaffected.
      if (!servingAudio && id != null && usedMedia != null) {
        final cached = cache[id];
        if (cached != null) {
          unawaited(() async {
            try {
              final media = await cached;
              if (identical(media, usedMedia) && identical(cache[id], cached)) {
                cache.remove(id);
                await media.file?.dispose();
              }
            } on Object {
              /* Resolution failures retire themselves. */
            }
          }());
        }
      }
      // Native players routinely cancel range reads when seeking/preloading.
      // Once valid audio is flowing, do not turn that into a resolver failure
      // or discard a successfully prepared file. Genuine playback failures
      // still reach the player's error stream and trigger a fresh session.
      if (!closed.isCompleted && !servingAudio) {
        sources.issue.value = error is SourceException
            ? error.message
            : 'Playback could not reach this music source. Try again.';
      }
      try {
        request.response.statusCode = HttpStatus.badGateway;
      } on Object {
        /* Headers already sent. */
      }
    } finally {
      client.close(force: true);
      clients.remove(client);
      try {
        await request.response.close();
      } on Object {
        /* Player disconnected. */
      }
      // Bound prepared media retained for seeks; unused temporary files are
      // removed as the listener moves through the queue.
      if (cache.length > 4) {
        final key = cache.keys.first;
        final old = cache.remove(key)!;
        try {
          await (await old).file?.dispose();
        } on Object {
          /* Still open. */
        }
      }
    }
  }

  static Future<HttpClientResponse> _open(
    HttpClient client,
    HttpRequest incoming,
    SourceStreamMedia media,
  ) async {
    var uri = media.uri!;
    for (var redirects = 0; redirects <= 5; redirects++) {
      final outgoing = await client.openUrl(incoming.method, uri);
      outgoing.followRedirects = false;
      for (final header in media.headers.entries) {
        // Only public request context from the reviewed resolver is forwarded.
        // No cookies, authorization, host override or player-supplied secrets.
        if ([
              'user-agent',
              'referer',
              'origin',
            ].contains(header.key.toLowerCase()) &&
            header.value is String &&
            !RegExp(r'[\r\n]').hasMatch(header.value as String)) {
          outgoing.headers.set(header.key, header.value);
        }
      }
      final range = incoming.headers.value(HttpHeaders.rangeHeader);
      if (range != null) outgoing.headers.set(HttpHeaders.rangeHeader, range);
      outgoing.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      final response = await outgoing.close().timeout(
        const Duration(seconds: 30),
      );
      if (![301, 302, 303, 307, 308].contains(response.statusCode)) {
        return response;
      }
      final location = response.headers.value(HttpHeaders.locationHeader);
      await response.drain<void>().timeout(const Duration(seconds: 10));
      final target = location == null ? null : uri.resolve(location);
      if (redirects == 5 ||
          target == null ||
          target.scheme != 'https' ||
          target.host.isEmpty ||
          target.userInfo.isNotEmpty ||
          InternetAddress.tryParse(target.host) != null ||
          target.host == 'localhost') {
        throw const SourceException(
          'This source returned an invalid audio redirect.',
        );
      }
      uri = target;
    }
    throw const SourceException('This source redirected too many times.');
  }

  static Future<void> _serveFile(
    HttpRequest request,
    File file, {
    void Function()? onReady,
  }) async {
    final size = await file.length();
    if (size == 0) {
      throw const SourceException('This source returned an empty audio file.');
    }
    final range = request.headers.value(HttpHeaders.rangeHeader);
    var start = 0;
    var end = size - 1;
    if (range != null) {
      final match = RegExp(r'^bytes=(\d+)-(\d*)$').firstMatch(range);
      if (match == null) {
        request.response.statusCode = 416;
        request.response.headers.set('Content-Range', 'bytes */$size');
        return;
      }
      start = int.parse(match[1]!);
      if (match[2]!.isNotEmpty) end = int.parse(match[2]!).clamp(0, size - 1);
      if (start > end || start >= size) {
        request.response.statusCode = 416;
        request.response.headers.set('Content-Range', 'bytes */$size');
        return;
      }
      request.response.statusCode = 206;
      request.response.headers.set('Content-Range', 'bytes $start-$end/$size');
    }
    onReady?.call();
    request.response.headers.set('Content-Type', audioMime(file.path));
    request.response.headers.set('Accept-Ranges', 'bytes');
    request.response.contentLength = end - start + 1;
    if (request.method == 'GET') {
      await request.response.addStream(file.openRead(start, end + 1));
    }
  }

  /// Retire failed streams without waiting for a stuck provider to finish.
  /// Its cancellation and eventual temporary-file cleanup remain attached to
  /// the old generation, so it cannot poison a fresh retry.
  Future<void> restart() async {
    final cleanup = _retire();
    await cleanup.$1;
    unawaited(cleanup.$2);
    await start();
  }

  (Future<void>, Future<void>) _retire() {
    if (!_closed.isCompleted) _closed.complete();
    final closing =
        _server?.close(force: true).then<void>((_) {}) ?? Future<void>.value();
    _server = null;
    final pending = List.of(_media.values);
    _media = {};
    for (final client in _clients) {
      client.close(force: true);
    }
    _clients = {};
    _tracks.clear();
    _token = MornyeSources.nonce();
    return (
      closing,
      Future.wait(
        pending.map((value) async {
          try {
            await (await value).file?.dispose();
          } on Object {
            /* Best effort on exit, including cancelled provider requests. */
          }
        }),
      ).then<void>((_) {}),
    );
  }

  Future<void> close() async {
    final cleanup = _retire();
    await cleanup.$1;
    await cleanup.$2;
  }
}

class SourceStreamMedia {
  SourceStreamMedia({
    this.uri,
    this.file,
    this.headers = const {},
    this.prepare,
    this.sourceId,
    this.format,
  });
  final Uri? uri;
  final String? sourceId;
  final String? format;
  final PreparedSourceAudio? file;
  final Map<String, dynamic> headers;
  final Future<PreparedSourceAudio> Function()? prepare;
  Future<SourceStreamMedia>? prepared;
  final created = DateTime.now();
}
