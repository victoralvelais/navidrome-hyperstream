import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperstream_client/services/navidrome_client.dart';
import 'package:hyperstream_client/services/playback_service.dart';
import 'package:just_audio/just_audio.dart';

import 'playback_continuity_test.dart' show MemoryPlaybackStore, savedQueue;

// Keep the real just_audio player, including its idle/native activation path.
// Only the native codec/transport is replaced; FakePlayer cannot catch a lost
// initial seek inside just_audio itself.
class _NativeAudio {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final firstLoad = Completer<Map<dynamic, dynamic>>();
  final firstPlay = Completer<void>();
  final channels = <MethodChannel>[];
  final streams = <EventChannel>[];

  void install() {
    _handle(
      const MethodChannel('com.ryanheise.audio_session'),
      (_) async => null,
    );
    _handle(const MethodChannel('com.ryanheise.just_audio.methods'), (
      call,
    ) async {
      if (call.method == 'init') {
        final id = (call.arguments as Map)['id'];
        final events = Completer<MockStreamHandlerEventSink>();
        final eventChannel = EventChannel(
          'com.ryanheise.just_audio.events.$id',
        );
        streams.add(eventChannel);
        messenger.setMockStreamHandler(
          eventChannel,
          MockStreamHandler.inline(
            onListen: (_, sink) => events.complete(sink),
          ),
        );
        final dataChannel = EventChannel('com.ryanheise.just_audio.data.$id');
        streams.add(dataChannel);
        messenger.setMockStreamHandler(
          dataChannel,
          MockStreamHandler.inline(onListen: (_, _) {}),
        );
        _handle(MethodChannel('com.ryanheise.just_audio.methods.$id'), (
          call,
        ) async {
          if (call.method == 'load') {
            final request = call.arguments as Map<dynamic, dynamic>;
            (await events.future).success({
              'processingState': ProcessingState.ready.index,
              'updateTime': DateTime.now().millisecondsSinceEpoch,
              'updatePosition': request['initialPosition'] ?? 0,
              'bufferedPosition': 0,
              'duration': const Duration(minutes: 3).inMicroseconds,
              'currentIndex': request['initialIndex'] ?? 0,
            });
            if (!firstLoad.isCompleted) firstLoad.complete(request);
            return {'duration': const Duration(minutes: 3).inMicroseconds};
          }
          if (call.method == 'play' && !firstPlay.isCompleted) {
            firstPlay.complete();
          }
          return <String, Object?>{};
        });
      }
      return <String, Object?>{};
    });
  }

  void _handle(
    MethodChannel channel,
    Future<Object?> Function(MethodCall) handler,
  ) {
    channels.add(channel);
    messenger.setMockMethodCallHandler(channel, handler);
  }

  void uninstall() {
    for (final channel in channels) {
      messenger.setMockMethodCallHandler(channel, null);
    }
    for (final stream in streams) {
      messenger.setMockStreamHandler(stream, null);
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final editWhilePaused in [false, true]) {
    test(
      'native activation keeps restored selection and position (edited: $editWhilePaused)',
      () async {
        final native = _NativeAudio()..install();
        final player = AudioPlayer(
          handleAudioSessionActivation: false,
          androidApplyAudioAttributes: false,
        );
        final store = MemoryPlaybackStore()
          ..value = savedQueue(index: 2, order: [1, 2, 0]);
        final client = NavidromeClient(
          serverUrl: 'https://example.test',
          username: 'user',
          password: 'secret',
        );
        final playback = PlaybackService(
          player: player,
          playbackStore: (_) => store,
          artworkLoader: (_, _) async => null,
        );
        addTearDown(() async {
          await playback.dispose();
          client.close();
          native.uninstall();
        });
        await playback.attachAccount(client, remember: true);
        expect(player.currentIndex, 2);
        expect(player.position, const Duration(seconds: 47));
        expect(
          native.firstLoad.isCompleted,
          isFalse,
          reason: 'Restoring alone must not fetch audio.',
        );
        if (editWhilePaused) {
          await playback.skipToQueueItem(1);
          await playback.seek(const Duration(seconds: 62));
        }
        playback.setSleepTimer(endOfTrack: true);
        final index = editWhilePaused ? 1 : 2;
        final position = Duration(seconds: editWhilePaused ? 62 : 47);
        await playback.play();
        final request = await native.firstLoad.future.timeout(
          const Duration(seconds: 5),
        );
        await player.processingStateStream
            .firstWhere((state) => state == ProcessingState.ready)
            .timeout(const Duration(seconds: 5));
        await native.firstPlay.future.timeout(const Duration(seconds: 5));
        expect(request['initialIndex'], index);
        expect(request['initialPosition'], position.inMicroseconds);
        expect(player.currentIndex, index);
        expect(
          player.position.inMilliseconds,
          closeTo(position.inMilliseconds, 1000),
        );
        expect(player.shuffleIndices, [1, 2, 0]);
        expect(player.shuffleModeEnabled, isTrue);
        expect(player.loopMode, LoopMode.all);
        expect(player.speed, 1.25);
        expect(playback.sleepTimer.value?.endOfTrack, isTrue);
        expect(playback.error.value, isNull);
      },
    );
  }
}
