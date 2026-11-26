import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:hyperstream_client/models/source_reference.dart';
import 'package:hyperstream_client/services/mornye_provider.dart';
import 'package:hyperstream_client/services/mornye_sources.dart';
import 'package:hyperstream_client/services/music_provider.dart';
import 'package:hyperstream_client/services/source_stream_proxy.dart';

void main() {
  late MornyeSources sources;
  const track = SourceReference(
    sourceId: 'mornye:tidal-web',
    trackId: 'tidal:123',
  );
  setUp(() {
    sources = MornyeSources();
    sources.extensions = [
      MornyeExtension({
        'id': 'tidal-web',
        'display_name': 'Tidal',
        'version': '1.0.0',
        'download_url': 'https://example.test/package',
        'sha256': 'test',
        'audio': true,
        'installed': true,
        'enabled': true,
      }),
    ];
  });
  tearDown(() => sources.dispose());
  test(
    'a late failed range cannot replace the same recording’s ready state',
    () async {
      final firstStarted = Completer<void>();
      final allowFirstFailure = Completer<void>();
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      upstream.listen((request) async {
        if (request.headers.value('Range') == 'bytes=1-') {
          firstStarted.complete();
          await allowFirstFailure.future;
          request.response.statusCode = 503;
        } else {
          request.response.add([1, 2, 3]);
        }
        await request.response.close();
      });
      var resolves = 0;
      final proxy = SourceStreamProxy(
        sources,
        resolve: (_) async {
          resolves++;
          return SourceStreamMedia(
            uri: Uri.parse('http://127.0.0.1:${upstream.port}/audio'),
          );
        },
      );
      addTearDown(() async {
        if (!allowFirstFailure.isCompleted) allowFirstFailure.complete();
        await proxy.close();
        await upstream.close(force: true);
      });
      await proxy.start();
      final url = proxy.uri(track);
      final stale = http.get(url, headers: {'Range': 'bytes=1-'});
      await firstStarted.future.timeout(const Duration(seconds: 2));
      expect((await http.get(url)).bodyBytes, [1, 2, 3]);
      allowFirstFailure.complete();
      expect((await stale).statusCode, 502);
      expect(proxy.failureFor(track), isNull);
      expect((await http.get(url)).bodyBytes, [1, 2, 3]);
      expect(resolves, 1);
    },
  );
  test(
    'failures are isolated by recording and expire with the proxy session',
    () async {
      const otherTrack = SourceReference(
        sourceId: 'mornye:tidal-web',
        trackId: 'tidal:456',
      );
      const exhausted = SourceException(
        'Providers exhausted',
        retryable: false,
      );
      const transient = SourceException('Try again');
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      upstream.listen((request) async {
        request.response.add([1, 2, 3]);
        await request.response.close();
      });
      var firstTrackAttempts = 0;
      final proxy = SourceStreamProxy(
        sources,
        resolve: (reference) async {
          if (reference.identity == otherTrack.identity) throw transient;
          if (++firstTrackAttempts == 1) throw exhausted;
          return SourceStreamMedia(
            uri: Uri.parse('http://127.0.0.1:${upstream.port}/fresh'),
          );
        },
      );
      addTearDown(() async {
        await proxy.close();
        await upstream.close(force: true);
      });
      await proxy.start();
      final firstUrl = proxy.uri(track);
      expect((await http.get(firstUrl)).statusCode, 502);
      expect(proxy.failureFor(track)?.retryable, isFalse);
      expect(proxy.failureFor(otherTrack), isNull);
      expect((await http.get(proxy.uri(otherTrack))).statusCode, 502);
      expect(proxy.failureFor(otherTrack)?.retryable, isTrue);
      expect(proxy.failureFor(track)?.retryable, isFalse);
      expect((await http.get(firstUrl)).bodyBytes, [1, 2, 3]);
      expect(proxy.failureFor(track), isNull);
      expect(proxy.failureFor(otherTrack)?.retryable, isTrue);
      await proxy.restart();
      expect(proxy.failureFor(otherTrack), isNull);
    },
  );

  test(
    'an abandoned range read keeps prepared audio for the next seek',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'hyperstream-seek-',
      );
      final file = await File('${directory.path}/source.m4a')
          .writeAsBytes(Uint8List(4 * 1024 * 1024));
      var resolves = 0;
      final proxy = SourceStreamProxy(
        sources,
        resolve: (_) async {
          resolves++;
          return SourceStreamMedia(file: PreparedSourceAudio(file, directory));
        },
      );
      await proxy.start();
      addTearDown(proxy.close);
      final url = proxy.uri(track);
      final client = HttpClient();
      final request = await client.getUrl(url);
      request.headers.set('Range', 'bytes=0-');
      final response = await request.close();
      await response.first;
      client.close(force: true);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect((await http.head(url)).statusCode, 200);
      expect(resolves, 1);
      expect(await file.exists(), true);
      expect(sources.issue.value, isNull);
    },
  );
  test('a failed transport is resolved afresh on the next Play request', () async {
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    upstream.listen((r) async {
      r.response.statusCode = r.uri.path == '/stale' ? 404 : 200;
      if (r.response.statusCode == 200) r.response.add([1, 2, 3]);
      await r.response.close();
    });
    var resolves = 0;
    final published = <SourcePlaybackInfo>[];
    final proxy = SourceStreamProxy(
      sources,
      onMedia: (_, info) => published.add(info),
      resolve: (_) async {
        resolves++;
        return SourceStreamMedia(
          uri: Uri.parse(
            'http://127.0.0.1:${upstream.port}/${resolves == 1 ? 'stale' : 'fresh'}',
          ),
          sourceId: 'mornye:qobuz-web',
          format: 'flac',
          bitRate: 941,
        );
      },
    );
    await proxy.start();
    addTearDown(() async {
      await proxy.close();
      await upstream.close(force: true);
    });
    final url = proxy.uri(track);
    expect((await http.get(url)).statusCode, 502);
    expect(published, isEmpty);
    final retry = await http.get(url);
    expect(retry.statusCode, 200);
    expect(retry.bodyBytes, [1, 2, 3]);
    expect(resolves, 2);
    expect(published.single.bitRate, 941);
    expect(published.single.label, 'Qobuz · FLAC · 941 kbps');
    expect(sources.issue.value, isNull);
  });
  test(
    'restart bypasses stuck resolution and ignores its late failure',
    () async {
      final started = Completer<void>();
      final stale = Completer<SourceStreamMedia>();
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      upstream.listen((r) async {
        r.response.add([1, 2, 3]);
        await r.response.close();
      });
      var resolves = 0;
      final proxy = SourceStreamProxy(
        sources,
        resolve: (_) {
          if (++resolves == 1) {
            started.complete();
            return stale.future;
          }
          return Future.value(
            SourceStreamMedia(
              uri: Uri.parse('http://127.0.0.1:${upstream.port}/fresh'),
            ),
          );
        },
      );
      await proxy.start();
      addTearDown(() async {
        if (!stale.isCompleted) {
          stale.completeError(const SourceException('Cancelled'));
        }
        await proxy.close();
        await upstream.close(force: true);
      });
      final oldUrl = proxy.uri(track);
      final oldRequest = http
          .get(oldUrl)
          .then<void>((_) {}, onError: (Object _) {});
      await started.future;
      await proxy.restart().timeout(const Duration(seconds: 2));
      final url = proxy.uri(track);
      expect(url, isNot(oldUrl));
      expect((await http.get(url)).bodyBytes, [1, 2, 3]);
      stale.completeError(const SourceException('Old private failure'));
      await oldRequest;
      await Future<void>.delayed(Duration.zero);
      expect(sources.issue.value, isNull);
      expect(proxy.failureFor(track), isNull);
      expect((await http.get(url)).statusCode, 200);
      expect(
        resolves,
        2,
        reason: 'A stale failure cannot evict the healthy retry.',
      );
    },
  );
  test(
    'restart cleans late prepared files without blocking the new listener',
    () async {
      final started = Completer<void>();
      final stale = Completer<SourceStreamMedia>();
      final directory = await Directory.systemTemp.createTemp(
        'hyperstream-retired-',
      );
      final file = await File('${directory.path}/late.m4a')
          .writeAsBytes([1, 2, 3]);
      final proxy = SourceStreamProxy(
        sources,
        resolve: (_) {
          started.complete();
          return stale.future;
        },
      );
      await proxy.start();
      final oldRequest = http
          .get(proxy.uri(track))
          .then<void>((_) {}, onError: (Object _) {});
      await started.future;
      await proxy.restart().timeout(const Duration(seconds: 2));
      expect(proxy.started, true);
      stale.complete(
        SourceStreamMedia(file: PreparedSourceAudio(file, directory)),
      );
      await oldRequest;
      for (var i = 0; i < 50 && await directory.exists(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(await directory.exists(), false);
      await proxy.close();
    },
  );
  test(
    'a synchronous resolver failure does not poison the cached future',
    () async {
      var resolves = 0;
      final directory = await Directory.systemTemp.createTemp(
        'hyperstream-retry-',
      );
      final file = await File('${directory.path}/source.mp3')
          .writeAsBytes([1, 2, 3]);
      final proxy = SourceStreamProxy(
        sources,
        resolve: (_) {
          if (++resolves == 1) throw const SourceException('Temporary failure');
          return Future.value(
            SourceStreamMedia(file: PreparedSourceAudio(file, directory)),
          );
        },
      );
      await proxy.start();
      addTearDown(proxy.close);
      final url = proxy.uri(track);
      expect((await http.get(url)).statusCode, 502);
      expect((await http.get(url)).bodyBytes, [1, 2, 3]);
      expect(resolves, 2);
    },
  );
  test('closing with a failing resolution retires the cache safely', () async {
    final started = Completer<void>();
    final pending = Completer<SourceStreamMedia>();
    final proxy = SourceStreamProxy(
      sources,
      resolve: (_) {
        started.complete();
        return pending.future;
      },
    );
    await proxy.start();
    final request = http
        .get(proxy.uri(track))
        .then<void>((_) {}, onError: (Object _) {});
    await started.future;
    final closing = proxy.close();
    // Let close begin waiting on the resolution before it removes its own entry.
    await Future<void>.delayed(Duration.zero);
    pending.completeError(const SourceException('Playback cancelled.'));
    await closing;
    await request;
  });
  test('YouTube request context is forwarded and blocked streams prepare a seekable fallback', () async {
    final directory = await Directory.systemTemp.createTemp(
      'hyperstream-youtube-fallback-',
    );
    final file = await File('${directory.path}/playback.m4a')
        .writeAsBytes([0, 1, 2, 3, 4, 5]);
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var requests = 0;
    var preparations = 0;
    upstream.listen((r) async {
      requests++;
      expect(r.headers.value('User-Agent'), 'Synthetic client');
      expect(r.headers.value('Origin'), 'https://www.youtube.com');
      expect(r.headers.value('Authorization'), isNull);
      expect(r.headers.value('Cookie'), isNull);
      r.response.statusCode = 403;
      await r.response.close();
    });
    final proxy = SourceStreamProxy(
      sources,
      resolve: (_) async => SourceStreamMedia(
        uri: Uri.parse('http://127.0.0.1:${upstream.port}/blocked'),
        headers: {
          'User-Agent': 'Synthetic client',
          'Origin': 'https://www.youtube.com',
          'Authorization': 'synthetic-must-not-forward',
          'Cookie': 'synthetic-must-not-forward',
        },
        prepare: () async {
          preparations++;
          return PreparedSourceAudio(file, directory);
        },
      ),
    );
    await proxy.start();
    addTearDown(() async {
      await proxy.close();
      await upstream.close(force: true);
    });
    final url = proxy.uri(track);
    final audio = await http.get(url, headers: {'Range': 'bytes=2-4'});
    expect(audio.statusCode, 206);
    expect(audio.headers['content-type'], 'audio/mp4');
    expect(audio.bodyBytes, [2, 3, 4]);
    final head = await http.head(url);
    expect(head.headers['content-length'], '6');
    expect(preparations, 1);
    expect(requests, 2);
    expect(sources.issue.value, isNull);
  });
  test('HTTPS CDN redirects preserve ranges and reject a downgrade', () async {
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final seen = <String>[];
    upstream.listen((r) async {
      seen.add(r.uri.path);
      expect(r.headers.value('Range'), 'bytes=2-4');
      if (r.uri.path == '/redirect' || r.uri.path == '/downgrade') {
        r.response.statusCode = 302;
        r.response.headers.set(
          'Location',
          r.uri.path == '/redirect'
              ? 'https://cdn.example.test/audio'
              : 'http://cdn.example.test/audio',
        );
      } else {
        r.response.statusCode = 206;
        r.response.headers.set('Content-Range', 'bytes 2-4/6');
        r.response.add([2, 3, 4]);
      }
      await r.response.close();
    });
    final proxy = SourceStreamProxy(
      sources,
      client: () => _MappedClient(upstream.port),
      resolve: (track) async => SourceStreamMedia(
        uri: Uri.parse('https://media.example.test/${track.trackId}'),
      ),
    );
    await proxy.start();
    addTearDown(() async {
      await proxy.close();
      await upstream.close(force: true);
    });
    final response = await http.get(
      proxy.uri(
        const SourceReference(
          sourceId: 'mornye:tidal-web',
          trackId: 'redirect',
        ),
      ),
      headers: {'Range': 'bytes=2-4'},
    );
    expect(response.statusCode, 206);
    expect(response.bodyBytes, [2, 3, 4]);
    final rejected = await http.get(
      proxy.uri(
        const SourceReference(
          sourceId: 'mornye:tidal-web',
          trackId: 'downgrade',
        ),
      ),
      headers: {'Range': 'bytes=2-4'},
    );
    expect(rejected.statusCode, 502);
    expect(seen, ['/redirect', '/audio', '/downgrade']);
  });
  test('native queue URLs resolve lazily, preserve ranges, refresh expired links', () async {
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = <String?>[];
    upstream.listen((r) async {
      requests.add(r.headers.value('Range'));
      if (r.uri.path == '/expired') {
        r.response.statusCode = 403;
        await r.response.close();
        return;
      }
      r.response.statusCode = 206;
      r.response.headers.set('Content-Type', 'audio/flac');
      r.response.headers.set('Content-Range', 'bytes 2-4/6');
      r.response.contentLength = 3;
      r.response.add([2, 3, 4]);
      await r.response.close();
    });
    var resolves = 0;
    final proxy = SourceStreamProxy(
      sources,
      resolve: (_) async {
        resolves++;
        return SourceStreamMedia(
          uri: Uri.parse(
            'http://127.0.0.1:${upstream.port}/${resolves == 1 ? 'expired' : 'fresh'}',
          ),
        );
      },
    );
    await proxy.start();
    addTearDown(() async {
      await proxy.close();
      await upstream.close(force: true);
    });
    final url = proxy.uri(track);
    expect(resolves, 0);
    final response = await http.get(url, headers: {'Range': 'bytes=2-4'});
    expect(resolves, 2);
    expect(requests, ['bytes=2-4', 'bytes=2-4']);
    expect(response.statusCode, 206);
    expect(response.headers['content-range'], 'bytes 2-4/6');
    expect(response.bodyBytes, [2, 3, 4]);
    final forbidden = await http.get(url.replace(path: '/wrong-token/track'));
    expect(forbidden.statusCode, 404);
    expect(resolves, 2);
  });
  test('prepared files support seek ranges, HEAD and cleanup', () async {
    final directory = await Directory.systemTemp.createTemp(
      'hyperstream-proxy-',
    );
    final file = File('${directory.path}/source.flac');
    await file.writeAsBytes([0, 1, 2, 3, 4, 5]);
    final proxy = SourceStreamProxy(
      sources,
      resolve: (_) async =>
          SourceStreamMedia(file: PreparedSourceAudio(file, directory)),
    );
    await proxy.start();
    addTearDown(proxy.close);
    final url = proxy.uri(track);
    final response = await http.get(url, headers: {'Range': 'bytes=2-4'});
    expect(response.statusCode, 206);
    expect(response.bodyBytes, [2, 3, 4]);
    final head = await http.head(url);
    expect(head.headers['content-length'], '6');
    expect(head.bodyBytes, isEmpty);
    final invalid = await http.get(url, headers: {'Range': 'bytes=99-'});
    expect(invalid.statusCode, 416);
    expect(invalid.headers['content-range'], 'bytes */6');
    await proxy.close();
    expect(await directory.exists(), false);
  });

  for (final probeFails in [false, true]) {
    test(
      'prepared audio remains seekable ${probeFails ? 'after probe failure' : 'while bitrate is pending'}',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'hyperstream-probe-',
        );
        final file = await File('${directory.path}/source.m4a')
            .writeAsBytes([0, 1, 2, 3, 4, 5]);
        const resolvedSource = 'mornye:qobuz-web';
        const quality = SourcePlaybackInfo(
          sourceId: resolvedSource,
          format: 'm4a',
          codec: 'aac',
          bitRate: 129,
          bitRateEstimated: true,
        );
        final probe = Completer<SourcePlaybackInfo?>();
        final updated = Completer<void>();
        final published = <SourcePlaybackInfo>[];
        var probes = 0;
        var resolves = 0;
        final proxy = SourceStreamProxy(
          sources,
          resolve: (_) async {
            resolves++;
            return SourceStreamMedia(
              sourceId: resolvedSource,
              file: PreparedSourceAudio(file, directory),
            );
          },
          onMedia: (reference, info) {
            expect(reference, track);
            published.add(info);
            if (info.bitRate != null && !updated.isCompleted) {
              updated.complete();
            }
          },
          probeAudio: (prepared, sourceId) {
            probes++;
            expect(prepared.path, file.path);
            expect(sourceId, resolvedSource);
            return probe.future;
          },
        );
        await proxy.start();
        addTearDown(() async {
          if (!probe.isCompleted) probe.complete(null);
          await proxy.close();
        });
        final url = proxy.uri(track);
        expect((await http.get(url)).bodyBytes, [0, 1, 2, 3, 4, 5]);
        expect(published.last.sourceId, resolvedSource);
        expect(published.last.bitRate, isNull);
        final pendingSeek = await http.get(
          url,
          headers: {'Range': 'bytes=2-4'},
        );
        expect(pendingSeek.statusCode, 206);
        expect(pendingSeek.bodyBytes, [2, 3, 4]);

        if (probeFails) {
          probe.completeError(
            const FormatException('Malformed probe response'),
          );
        } else {
          probe.complete(quality);
          await updated.future.timeout(const Duration(seconds: 2));
        }
        final cachedSeek = await http.get(url, headers: {'Range': 'bytes=4-5'});
        expect(cachedSeek.statusCode, 206);
        expect(cachedSeek.bodyBytes, [4, 5]);
        expect(published.last.bitRate, probeFails ? null : 129);
        expect(published.last.bitRateEstimated, !probeFails);
        expect(resolves, 1);
        expect(probes, 1);
        expect(sources.issue.value, isNull);
      },
    );
  }
}

class _MappedClient extends Fake implements HttpClient {
  _MappedClient(this.port);
  final int port;
  final delegate = HttpClient();
  @override
  Duration? connectionTimeout;
  @override
  Future<HttpClientRequest> openUrl(String method, Uri uri) {
    expect(uri.scheme, 'https');
    return delegate.openUrl(
      method,
      uri.replace(scheme: 'http', host: '127.0.0.1', port: port),
    );
  }

  @override
  void close({bool force = false}) => delegate.close(force: force);
}
