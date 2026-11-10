import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperstream_client/services/navidrome_client.dart';
import 'package:hyperstream_client/services/playback_service.dart';
import 'package:integration_test/integration_test.dart';

// Silent PCM audio exercises the real native decoder without a music download.
Uint8List silentWav() {
  const samples = 44100 * 12;
  final bytes = Uint8List(44 + samples * 2);
  final header = ByteData.sublistView(bytes);
  void text(int offset, String value) =>
      bytes.setRange(offset, offset + value.length, ascii.encode(value));
  text(0, 'RIFF');
  header.setUint32(4, bytes.length - 8, Endian.little);
  text(8, 'WAVE');
  text(12, 'fmt ');
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little);
  header.setUint16(22, 1, Endian.little);
  header.setUint32(24, 44100, Endian.little);
  header.setUint32(28, 88200, Endian.little);
  header.setUint16(32, 2, Endian.little);
  header.setUint16(34, 16, Endian.little);
  text(36, 'data');
  header.setUint32(40, samples * 2, Endian.little);
  return bytes;
}

Future<void> eventually(
  WidgetTester tester,
  bool Function() condition, {
  String Function()? details,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(
    condition(),
    isTrue,
    reason:
        'Native playback condition did not become true. ${details?.call() ?? ''}',
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native HTTP playback, pause, seek, album transition, and reset', (
    tester,
  ) async {
    final audio = silentWav();
    final streamedIds = <String>{};
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final response = request.response;
      if (request.uri.path.endsWith('/stream.view')) {
        streamedIds.add(request.uri.queryParameters['id']!);
        response.headers.contentType = ContentType('audio', 'wav');
        response.headers.set('accept-ranges', 'bytes');
        var start = 0;
        var end = audio.length - 1;
        final range = request.headers.value('range');
        if (range != null) {
          final match = RegExp(r'^bytes=(\d+)-(\d*)$').firstMatch(range)!;
          start = int.parse(match.group(1)!);
          if (match.group(2)!.isNotEmpty) end = int.parse(match.group(2)!);
          end = end.clamp(start, audio.length - 1);
          response.statusCode = HttpStatus.partialContent;
          response.headers.set(
            'content-range',
            'bytes $start-$end/${audio.length}',
          );
        }
        response.contentLength = end - start + 1;
        if (request.method != 'HEAD') {
          response.add(audio.sublist(start, end + 1));
        }
      } else {
        response.headers.contentType = ContentType.json;
        response.write(
          jsonEncode({
            'subsonic-response': {
              'status': 'ok',
              if (request.uri.path.endsWith('/getAlbumList2.view'))
                'albumList2': {
                  'album': [
                    {'id': 'album', 'name': 'Test album'},
                  ],
                },
              if (request.uri.path.endsWith('/getAlbum.view'))
                'album': {
                  'song': [
                    {'id': 'one', 'title': 'First', 'duration': 12},
                    {'id': 'two', 'title': 'Second', 'duration': 12},
                  ],
                },
            },
          }),
        );
      }
      await response.close();
    });
    final client = NavidromeClient(
      serverUrl: 'http://127.0.0.1:${server.port}',
      username: 'test',
      password: 'test',
    );
    final playback = await PlaybackService.initialize();
    addTearDown(() async {
      await playback.dispose();
      client.close();
      await server.close(force: true);
    });
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text('Testing native audio with generated silence…'),
          ),
        ),
      ),
    );

    await client.ping();
    final albums = await client.albums();
    final tracks = await client.tracks(albums.single.id);
    await playback.playAlbum(client, tracks, 0);
    expect(playback.error.value, isNull);
    await eventually(
      tester,
      () => playback.position > const Duration(milliseconds: 200),
      details: () =>
          'state=${playback.playbackState.value.processingState}, '
          'playing=${playback.playbackState.value.playing}, '
          'position=${playback.position}, duration=${playback.mediaItem.value?.duration}, '
          'error=${playback.error.value}, streamed=$streamedIds',
    );
    expect(playback.mediaItem.value?.id, 'one');
    await playback.pause();
    expect(playback.playbackState.value.playing, isFalse);
    await playback.seek(const Duration(seconds: 10));
    await eventually(
      tester,
      () => playback.position >= const Duration(seconds: 9),
    );
    await playback.play();
    await eventually(tester, () => playback.mediaItem.value?.id == 'two');
    expect(streamedIds, containsAll(['one', 'two']));
    expect(playback.error.value, isNull);
    await playback.reset();
    expect(playback.queue.value, isEmpty);
    expect(playback.mediaItem.value, isNull);
    expect(
      playback.playbackState.value.processingState,
      AudioProcessingState.idle,
    );
  });
}
