import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperstream_client/services/navidrome_client.dart';
import 'package:hyperstream_client/services/playback_service.dart';
import 'package:hyperstream_client/services/playback_store.dart';
import 'package:hyperstream_client/models/library.dart';
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

  testWidgets('saved queue restores and checkpoints without an audio device', (
    tester,
  ) async {
    final directory = await Directory.systemTemp.createTemp(
      'hyperstream-restoration-',
    );
    var streamRequests = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      if (request.uri.path.endsWith('/stream.view')) streamRequests++;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'subsonic-response': {'status': 'ok'},
        }),
      );
      await request.response.close();
    });
    final client = NavidromeClient(
      serverUrl: 'http://127.0.0.1:${server.port}',
      username: 'synthetic',
      password: 'synthetic',
    );
    FilePlaybackStore store(NavidromeClient account) =>
        FilePlaybackStore(account, directory: () async => directory);
    const tracks = [
      Track(
        id: 'one',
        title: 'One',
        artist: 'Test',
        album: 'Test',
        duration: Duration(minutes: 3),
      ),
      Track(
        id: 'two',
        title: 'Two',
        artist: 'Test',
        album: 'Test',
        duration: Duration(minutes: 3),
      ),
      Track(
        id: 'one',
        title: 'One again',
        artist: 'Test',
        album: 'Test',
        duration: Duration(minutes: 3),
      ),
    ];
    await store(client).write(
      const PlaybackSnapshot(
        tracks: tracks,
        coverArtIds: [null, null, null],
        index: 2,
        position: Duration(seconds: 47),
        shuffleOrder: [1, 2, 0],
        repeat: 'all',
        speed: 1.25,
      ),
    );
    final playback = await PlaybackService.initialize(playbackStore: store);
    addTearDown(() async {
      await playback.dispose();
      client.close();
      await server.close(force: true);
      await directory.delete(recursive: true);
    });
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('Checking saved playback'))),
    );
    await client.ping();
    await playback.attachAccount(client, remember: true);
    expect(playback.continuityNotice.value, isNull);
    expect(playback.error.value, isNull);
    expect(playback.queue.value.map((item) => item.id), ['one', 'two', 'one']);
    expect(playback.playbackState.value.queueIndex, 2);
    expect(playback.position, const Duration(seconds: 47));
    expect(playback.playbackState.value.playing, isFalse);
    expect(
      playback.playbackState.value.shuffleMode,
      AudioServiceShuffleMode.all,
    );
    expect(playback.playbackState.value.repeatMode, AudioServiceRepeatMode.all);
    expect(playback.playbackState.value.speed, 1.25);
    expect(playback.upcomingIndices, [0]);
    await playback.seek(const Duration(seconds: 62));
    await playback.savePlayback();
    final saved = await store(client).read();
    expect(saved!.position, const Duration(seconds: 62));
    expect(saved.shuffleOrder, [1, 2, 0]);
    expect(streamRequests, 0);
    await playback.reset();
    expect(await store(client).read(), isNull);
  });

  testWidgets('native HTTP playback, pause, seek, album transition, and reset', (
    tester,
  ) async {
    if (Platform.isWindows) {
      const outputs = MethodChannel('dev.hyperstream/audio_outputs');
      final devices = await outputs.invokeListMethod<Object?>('getOutputs');
      final realDevices = devices!
          .where((device) => (device as Map)['id'] != '')
          .length;
      debugPrint('Native audio output count: $realDevices');
      if (realDevices == 0) {
        markTestSkipped(
          'No Windows audio output. Queue restoration is checked separately; real playback requires a device.',
        );
        return;
      }
    }
    final audio = silentWav();
    final streamedIds = <String>{};
    var streamRequests = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final response = request.response;
      if (request.uri.path.endsWith('/stream.view')) {
        streamRequests++;
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
                    {'id': 'three', 'title': 'Third', 'duration': 12},
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
    final savedDirectory = await Directory.systemTemp.createTemp(
      'hyperstream-native-continuity-',
    );
    FilePlaybackStore store(NavidromeClient account) =>
        FilePlaybackStore(account, directory: () async => savedDirectory);
    var playback = await PlaybackService.initialize(playbackStore: store);
    addTearDown(() async {
      await playback.dispose();
      client.close();
      await server.close(force: true);
      await savedDirectory.delete(recursive: true);
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
    await playback.attachAccount(client, remember: true);
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
    await playback.setAppVolume(.3);
    expect(playback.preferences.volume, .3);
    await playback.toggleMute();
    expect(playback.preferences.volume, 0);
    expect(playback.playbackState.value.playing, isTrue);
    await playback.toggleMute();
    expect(playback.preferences.volume, .3);
    expect(playback.settingsError.value, isNull);
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

    await playback.playAlbum(client, tracks, 0);
    await eventually(
      tester,
      () => playback.position > const Duration(milliseconds: 200),
    );
    await playback.setSpeed(1.25);
    expect(playback.playbackState.value.speed, 1.25);
    await playback.setSpeed(1);
    await playback.setShuffleMode(AudioServiceShuffleMode.all);
    expect(
      playback.playbackState.value.shuffleMode,
      AudioServiceShuffleMode.all,
    );
    await playback.setShuffleMode(AudioServiceShuffleMode.none);
    await playback.setRepeatMode(AudioServiceRepeatMode.one);
    expect(playback.playbackState.value.repeatMode, AudioServiceRepeatMode.one);
    await playback.setRepeatMode(AudioServiceRepeatMode.none);
    await playback.moveUpcoming(2, 1);
    expect(playback.queue.value.map((item) => item.id), [
      'one',
      'three',
      'two',
    ]);
    await playback.removeUpcoming(2);
    expect(playback.queue.value.map((item) => item.id), ['one', 'three']);
    await playback.seek(const Duration(seconds: 10));
    playback.setSleepTimer(endOfTrack: true);
    await eventually(
      tester,
      () =>
          playback.sleepTimer.value == null &&
          !playback.playbackState.value.playing,
    );
    expect(playback.error.value, isNull);
    expect(playback.settingsError.value, isNull);
    expect(playback.mediaItem.value?.id, 'three');
    await playback.play();
    playback.setSleepTimer(duration: const Duration(seconds: 1));
    await eventually(
      tester,
      () =>
          playback.sleepTimer.value == null &&
          !playback.playbackState.value.playing,
    );
    // Recreate the real native player using the same on-disk account state.
    await playback.seek(const Duration(seconds: 4));
    await playback.setShuffleMode(AudioServiceShuffleMode.all);
    await playback.setRepeatMode(AudioServiceRepeatMode.all);
    await playback.setSpeed(1.25);
    final upcoming = playback.upcomingIndices;
    final current = playback.playbackState.value.queueIndex;
    final beforeRestoreRequests = streamRequests;
    await playback.dispose();
    playback = await PlaybackService.initialize(playbackStore: store);
    await playback.attachAccount(client, remember: true);
    expect(playback.error.value, isNull);
    expect(playback.continuityNotice.value, isNull);
    expect(playback.queue.value.map((item) => item.id), ['one', 'three']);
    expect(playback.playbackState.value.queueIndex, current);
    expect(playback.playbackState.value.playing, isFalse);
    expect(playback.playbackState.value.repeatMode, AudioServiceRepeatMode.all);
    expect(
      playback.playbackState.value.shuffleMode,
      AudioServiceShuffleMode.all,
    );
    expect(playback.playbackState.value.speed, 1.25);
    expect(playback.upcomingIndices, upcoming);
    expect(playback.position.inMilliseconds, closeTo(4000, 500));
    expect(
      streamRequests,
      beforeRestoreRequests,
      reason: 'Restoration must not fetch audio before Play',
    );
    await playback.play();
    await eventually(
      tester,
      () => playback.position > const Duration(seconds: 5),
    );
    expect(playback.error.value, isNull);
    expect(playback.upcomingIndices, upcoming);
    await playback.reset();
    expect(await store(client).read(), isNull);
    expect(playback.queue.value, isEmpty);
    expect(playback.mediaItem.value, isNull);
    expect(
      playback.playbackState.value.processingState,
      AudioProcessingState.idle,
    );
  });
}
