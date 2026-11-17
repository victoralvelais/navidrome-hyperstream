import 'dart:async';
import 'dart:io';

import '../models/source_reference.dart';
import 'mornye_provider.dart';
import 'mornye_sources.dart';
import 'music_provider.dart';

/// Lazy, range-preserving URLs for the native queue. Only the loopback listener
/// knows these per-launch tokens; resolved provider URLs never enter queue JSON.
class SourceStreamProxy {
  SourceStreamProxy(this.sources, {this.resolve});
  final Future<SourceStreamMedia> Function(SourceReference)? resolve;
  final MornyeSources sources;
  HttpServer? _server;
  final _token = MornyeSources.nonce();
  final _tracks = <String, SourceReference>{};
  final _media = <String, Future<SourceStreamMedia>>{};
  Future<void> start() async {
    if (_server != null) return;
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
    SourceReference track, {
    bool refresh = false,
  }) async {
    if (refresh) {
      final old = _media.remove(id);
      if (old != null) {
        try {
          await (await old).file?.dispose();
        } on Object {
          /* In use by an older request. */
        }
      }
    }
    return _media.putIfAbsent(id, () async {
      try {
        if (resolve != null) return await resolve!(track);
        final acquisition = MornyeAcquisition(sources);
        final abort = Completer<void>();
        final result = await acquisition.resolve(track, abort.future);
        if (result['prepare'] == true) {
          return SourceStreamMedia(
            file: await acquisition.download(track, abort.future),
          );
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
        return SourceStreamMedia(uri: uri);
      } on Object {
        _media.remove(id);
        rethrow;
      }
    });
  }

  Future<void> _serve(HttpRequest request) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30);
    try {
      final parts = request.uri.pathSegments;
      final track = parts.length == 2 && parts[0] == _token
          ? _tracks[parts[1]]
          : null;
      if (track == null || !['GET', 'HEAD'].contains(request.method)) {
        request.response.statusCode = HttpStatus.notFound;
        return;
      }
      final id = '${parts[1]}@${sources.revision}';
      if (!sources.has(track.sourceId.replaceFirst('mornye:', ''))) {
        throw const SourceException('Enable this provider in Music sources.');
      }
      var media = await _resolve(id, track);
      if (DateTime.now().difference(media.created) >
          const Duration(minutes: 5)) {
        media = await _resolve(id, track, refresh: true);
      }
      if (media.file case final prepared?) {
        await _serveFile(request, prepared.file);
      } else {
        HttpClientResponse? upstream;
        for (var attempt = 0; attempt < 2; attempt++) {
          final outgoing = await client.openUrl(request.method, media.uri!);
          // CDN redirects are handled only over HTTPS, with no app credentials.
          outgoing.followRedirects = false;
          final range = request.headers.value(HttpHeaders.rangeHeader);
          if (range != null) {
            outgoing.headers.set(HttpHeaders.rangeHeader, range);
          }
          outgoing.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
          upstream = await outgoing.close().timeout(
            const Duration(seconds: 30),
          );
          if (![401, 403].contains(upstream.statusCode) || attempt == 1) break;
          await upstream.drain<void>();
          media = await _resolve(id, track, refresh: true);
          if (media.file != null) {
            await _serveFile(request, media.file!.file);
            return;
          }
        }
        if (upstream == null ||
            ![200, 206, 416].contains(upstream.statusCode)) {
          throw const SourceException(
            'The audio source is unavailable. Try another source.',
          );
        }
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
      sources.issue.value = null;
    } on Object catch (error) {
      sources.issue.value = error is SourceException
          ? error.message
          : 'Playback could not reach this music source. Try again.';
      try {
        request.response.statusCode = HttpStatus.badGateway;
      } on Object {
        /* Headers already sent. */
      }
    } finally {
      client.close(force: true);
      try {
        await request.response.close();
      } on Object {
        /* Player disconnected. */
      }
      // Bound prepared media retained for seeks; unused temporary files are
      // removed as the listener moves through the queue.
      if (_media.length > 4) {
        final key = _media.keys.first;
        final old = _media.remove(key)!;
        try {
          await (await old).file?.dispose();
        } on Object {
          /* Still open. */
        }
      }
    }
  }

  static Future<void> _serveFile(HttpRequest request, File file) async {
    final size = await file.length();
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
    request.response.headers.set('Content-Type', audioMime(file.path));
    request.response.headers.set('Accept-Ranges', 'bytes');
    request.response.contentLength = end - start + 1;
    if (request.method == 'GET') {
      await request.response.addStream(file.openRead(start, end + 1));
    }
  }

  Future<void> close() async {
    await _server?.close(force: true);
    _server = null;
    for (final value in _media.values) {
      try {
        await (await value).file?.dispose();
      } on Object {
        /* Best effort on exit. */
      }
    }
    _media.clear();
    _tracks.clear();
  }
}

class SourceStreamMedia {
  SourceStreamMedia({this.uri, this.file});
  final Uri? uri;
  final PreparedSourceAudio? file;
  final created = DateTime.now();
}
