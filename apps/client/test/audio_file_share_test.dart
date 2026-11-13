import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:hyperstream_client/models/library.dart';
import 'package:hyperstream_client/services/audio_file_share.dart';
import 'package:hyperstream_client/services/navidrome_client.dart';

const track = Track(
  id: 'song',
  title: 'A song',
  artist: 'An artist',
  album: 'Album',
  duration: Duration(minutes: 4),
  container: 'mp3',
);

class StreamingClient extends http.BaseClient {
  StreamingClient(this.handler);
  final Future<http.StreamedResponse> Function(http.BaseRequest) handler;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handler(request);
}

class RealHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late NavidromeClient client;
  late AudioFileShare export;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('hyperstream-share-test-');
  });
  tearDown(() async {
    export.cancel();
    client.close();
    await export.finishPreparing();
    export.dispose();
    expect(
      root.absolute.path.startsWith(Directory.systemTemp.absolute.path),
      isTrue,
    );
    await root.delete(recursive: true);
  });
  void setup(
    Future<http.StreamedResponse> Function(http.BaseRequest) handler, {
    Track song = track,
  }) {
    client = NavidromeClient(
      serverUrl: 'https://music.example.com/navidrome/',
      username: 'listener',
      password: 'private-password',
      httpClient: StreamingClient(handler),
    );
    export = AudioFileShare(
      client: client,
      track: song,
      temporaryDirectory: () async => root,
    );
  }

  Future<void> expectNoFiles() async {
    expect(
      await root.list(recursive: true).where((entry) => entry is File).toList(),
      isEmpty,
    );
  }

  test('original streamed MP3 stays intact and alive until native sharing finishes', () async {
    final bytes = [73, 68, 51, ...List.generate(6000, (i) => i % 256)];
    setup((request) async {
      expect(request.url.path, '/navidrome/rest/download.view');
      expect(request.url.queryParameters['id'], 'song');
      expect(request.url.queryParameters['t'], hasLength(32));
      expect(request.url.queryParameters.containsKey('format'), isFalse);
      expect(request.followRedirects, isFalse);
      expect(request, isA<http.AbortableRequest>());
      return http.StreamedResponse(
        Stream.fromIterable([bytes.sublist(0, 3000), bytes.sublist(3000)]),
        200,
        contentLength: bytes.length,
        headers: {'content-type': 'audio/mpeg'},
      );
    });
    final updates = <int>[];
    export.addListener(() => updates.add(export.received));
    final file = await export.prepare();
    expect(file.uri.pathSegments.last, 'An artist - A song.mp3');
    expect(await file.readAsBytes(), bytes);
    expect(updates, containsAllInOrder([0, 3000, bytes.length]));
    expect(export.progress, 1);
    final completed = Completer<bool>();
    const channel = MethodChannel('dev.hyperstream/share');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'shareFile');
      expect(call.arguments, file.path);
      expect(call.arguments, isNot(contains('http')));
      expect(call.arguments, isNot(contains('private-password')));
      return completed.future;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    var finished = false;
    final sharing = export.share().then((_) => finished = true);
    await Future<void>.delayed(Duration.zero);
    expect(finished, isFalse);
    expect(await file.exists(), isTrue);
    completed.complete(true);
    await sharing;
    await export.cleanup();
    expect(await file.exists(), isFalse);
  });

  test('names cannot escape the export directory and Unicode stays within filesystem limits', () async {
    setup(
      (_) async => http.StreamedResponse(
        Stream.value([73, 68, 51, 0]),
        200,
        headers: {'content-type': 'audio/mpeg'},
      ),
      song: Track(
        id: 'odd',
        title: '../${'✨🎵' * 100}',
        artist: '..\\artist:\nname',
        album: '',
        duration: Duration.zero,
        container: '../../other',
      ),
    );
    final file = await export.prepare();
    expect(
      file.uri.toString(),
      startsWith(root.uri.resolve('hyperstream-share/').toString()),
    );
    expect(file.path, endsWith('.mp3'));
    expect(utf8.encode(file.uri.pathSegments.last).length, lessThan(200));
    expect(file.uri.pathSegments.last, isNot(contains('\\')));
    await export.cleanup();
    await expectNoFiles();
  });

  for (final status in [302, 403, 404]) {
    test('HTTP $status cannot become a shared audio file', () async {
      setup(
        (_) async => http.StreamedResponse(
          Stream.value(utf8.encode('secret server error')),
          status,
          headers: {'location': 'https://other.example.com/?token=secret'},
        ),
      );
      await expectLater(
        export.prepare(),
        throwsA(
          isA<NavidromeException>().having(
            (e) => e.message,
            'sanitized',
            isNot(contains('secret')),
          ),
        ),
      );
      await expectNoFiles();
    });
  }
  for (final mime in [
    'application/json',
    'text/html',
    'application/octet-stream',
  ]) {
    test('HTTP 200 error body ($mime) cannot become an attachment', () async {
      setup(
        (_) async => http.StreamedResponse(
          Stream.value(
            utf8.encode(
              '{"subsonic-response":{"status":"failed","error":{"code":50}}}',
            ),
          ),
          200,
          headers: {'content-type': mime},
        ),
      );
      await expectLater(export.prepare(), throwsA(isA<NavidromeException>()));
      await expectNoFiles();
    });
  }
  for (final bytes in [
    <int>[],
    [73, 68, 51],
  ]) {
    test(
      'empty or truncated downloads are discarded (${bytes.length} bytes)',
      () async {
        setup(
          (_) async => http.StreamedResponse(
            Stream.value(bytes),
            200,
            contentLength: 20,
            headers: {'content-type': 'audio/mpeg'},
          ),
        );
        await expectLater(export.prepare(), throwsA(isA<NavidromeException>()));
        await expectNoFiles();
      },
    );
  }

  for (final closeAccount in [false, true]) {
    test(
      '${closeAccount ? 'account closure' : 'Cancel'} aborts a live HTTP body and removes the partial file',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        server.listen((request) async {
          request.response.headers.contentType = ContentType('audio', 'mpeg');
          request.response.bufferOutput = false;
          request.response.add([73, 68, 51, ...List.filled(8192, 0)]);
          await request.response.flush();
          // Leave the body open: cancellation must actively stop the request.
        });
        client = NavidromeClient(
          serverUrl: 'http://127.0.0.1:${server.port}',
          username: 'test',
          password: 'secret',
          httpClient: IOClient(RealHttpOverrides().createHttpClient(null)),
        );
        export = AudioFileShare(
          client: client,
          track: track,
          temporaryDirectory: () async => root,
        );
        export.addListener(() {
          if (export.received > 0) {
            if (closeAccount) {
              client.close();
            } else {
              export.cancel();
            }
          }
        });
        await expectLater(
          export.prepare().timeout(const Duration(seconds: 3)),
          throwsA(isA<AudioShareCancelled>()),
        );
        await expectNoFiles();
      },
    );
  }

  test('a prepared file cannot be shared after disconnecting', () async {
    setup((_) async => http.StreamedResponse(Stream.value([73, 68, 51]), 200));
    await export.prepare();
    client.close();
    await expectLater(export.share(), throwsA(isA<AudioShareCancelled>()));
    await export.cleanup();
    await expectNoFiles();
  });

  test('FLAC remains FLAC with no lossy conversion', () async {
    final bytes = utf8.encode('fLaC synthetic original');
    setup(
      (_) async => http.StreamedResponse(
        Stream.value(bytes),
        200,
        headers: {'content-type': 'audio/flac'},
      ),
      song: const Track(
        id: 'lossless',
        title: 'Lossless',
        artist: 'Artist',
        album: '',
        duration: Duration.zero,
        container: 'flac',
      ),
    );
    final file = await export.prepare();
    expect(file.path, endsWith('.flac'));
    expect(await file.readAsBytes(), bytes);
    await export.cleanup();
  });

  test('Cancel aborts a live request before response headers arrive', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) {
      export.cancel();
    });
    client = NavidromeClient(
      serverUrl: 'http://127.0.0.1:${server.port}',
      username: 'test',
      password: 'secret',
      httpClient: IOClient(RealHttpOverrides().createHttpClient(null)),
    );
    export = AudioFileShare(
      client: client,
      track: track,
      temporaryDirectory: () async => root,
    );
    await expectLater(
      export.prepare().timeout(const Duration(seconds: 3)),
      throwsA(isA<AudioShareCancelled>()),
    );
    await expectNoFiles();
  });

  test('a stalled body times out without leaving an attachment', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.headers.contentType = ContentType('audio', 'mpeg');
      request.response.bufferOutput = false;
      request.response.add([73, 68, 51, ...List.filled(8192, 0)]);
      await request.response.flush();
    });
    client = NavidromeClient(
      serverUrl: 'http://127.0.0.1:${server.port}',
      username: 'test',
      password: 'secret',
      httpClient: IOClient(RealHttpOverrides().createHttpClient(null)),
    );
    export = AudioFileShare(
      client: client,
      track: track,
      temporaryDirectory: () async => root,
      idleTimeout: const Duration(milliseconds: 100),
    );
    await expectLater(
      export.prepare().timeout(const Duration(seconds: 3)),
      throwsA(isA<NavidromeException>()),
    );
    await expectNoFiles();
  });
}
