import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperstream_client/models/library.dart';
import 'package:hyperstream_client/services/navidrome_client.dart';
import 'package:hyperstream_client/services/playback_service.dart';
import 'package:just_audio/just_audio.dart';

import 'support/fake_player.dart';

void main() {
  late FakePlayer player;
  late PlaybackService service;
  late NavidromeClient client;
  late List<AudioSessionConfiguration> configurations;
  bool failConfiguration = false;
  const tracks = [
    Track(
      id: 'one',
      title: 'First',
      artist: 'Artist',
      album: 'Album',
      duration: Duration(minutes: 3),
    ),
    Track(
      id: 'two',
      title: 'Second',
      artist: 'Artist',
      album: 'Album',
      duration: Duration(minutes: 3),
    ),
  ];

  setUp(() {
    player = FakePlayer();
    configurations = [];
    failConfiguration = false;
    service = PlaybackService(
      player: player,
      configureSession: (configuration) async {
        if (failConfiguration) throw StateError('native details');
        configurations.add(configuration);
      },
    );
    client = NavidromeClient(
      serverUrl: 'https://music.example.com',
      username: 'test',
      password: 'test',
    );
  });
  tearDown(() async {
    await service.dispose();
    client.close();
  });

  test('loads the whole album natively at the selected track', () async {
    await service.playAlbum(client, tracks, 1);
    expect(player.loaded.single.length, 2);
    expect(player.currentIndex, 1);
    expect(service.mediaItem.value?.title, 'Second');
    expect(service.queue.value.map((item) => item.id), ['one', 'two']);
    expect(player.playCalls, 1);
  });

  test(
    'mixed album queues keep each song artwork and album fallback',
    () async {
      await service.playAlbum(
        client,
        [
          const Track(
            id: 'search-song',
            title: 'Search song',
            artist: 'Another artist',
            album: 'Another album',
            duration: Duration(minutes: 2),
            coverArt: 'song-cover',
          ),
          tracks.first,
        ],
        0,
        coverArtId: 'album-cover',
      );
      expect(service.queue.value.map((item) => item.extras?['coverArtId']), [
        'song-cover',
        'album-cover',
      ]);
    },
  );

  test(
    'app volume clamps input, restores mute level, and survives a queue reset',
    () async {
      await service.setAppVolume(2);
      expect(player.volume, 1);
      await service.setAppVolume(.32);
      await service.toggleMute();
      expect(player.volume, 0);
      await service.reset();
      await service.toggleMute();
      expect(player.volume, .32);
      await service.playAlbum(client, tracks, 0);
      expect(player.volume, .32);
      await service.setAppVolume(-1);
      expect(player.volume, 0);
      await service.setAppVolume(double.nan);
      expect(player.volume, 0);
    },
  );

  test('rapid volume and mute commands finish in user order', () async {
    await Future.wait([
      service.setAppVolume(.2),
      service.toggleMute(),
      service.toggleMute(),
      service.setAppVolume(.4),
    ]);
    expect(player.volumeCalls, [.2, 0, .2, .4]);
    expect(service.preferences.volume, .4);
  });

  test(
    'failed volume change does not break a playing queue or save a false level',
    () async {
      await service.playAlbum(client, tracks, 0);
      player.failVolume = true;
      await service.setAppVolume(.2);
      expect(service.preferences.volume, 1);
      expect(service.settingsError.value, isNotNull);
      expect(service.error.value, isNull);
      expect(service.playbackState.value.playing, isTrue);
      player.failVolume = false;
      await service.setAppVolume(.3);
      expect(service.settingsError.value, isNull);
    },
  );

  test(
    'mixing can be enabled and explicitly cleared without changing the queue',
    () async {
      await service.playAlbum(client, tracks, 0);
      await service.setMixWithOthers(true);
      await service.setMixWithOthers(false);
      expect(
        configurations.first.avAudioSessionCategory,
        AVAudioSessionCategory.playback,
      );
      expect(
        configurations.first.avAudioSessionCategoryOptions,
        AVAudioSessionCategoryOptions.mixWithOthers,
      );
      expect(
        configurations.last.avAudioSessionCategoryOptions,
        AVAudioSessionCategoryOptions.none,
      );
      expect(service.preferences.mixWithOthers, isFalse);
      expect(service.playbackState.value.playing, isTrue);
      expect(player.playCalls, 1);
    },
  );

  test(
    'failed session reconfiguration preserves the previous choice',
    () async {
      failConfiguration = true;
      await service.setMixWithOthers(true);
      expect(service.preferences.mixWithOthers, isFalse);
      expect(service.settingsError.value, isNotNull);
      expect(service.error.value, isNull);
    },
  );

  test(
    'a newer selection supersedes an in-flight album without stale autoplay',
    () async {
      player.loadGate = Completer<void>();
      final first = service.playAlbum(client, tracks, 0);
      await Future<void>.delayed(Duration.zero);
      final second = service.playAlbum(client, tracks, 1);
      player.loadGate!.complete();
      await Future.wait([first, second]);
      expect(player.currentIndex, 1);
      expect(player.playCalls, 1);
      expect(service.mediaItem.value?.id, 'two');
    },
  );

  test('pause during loading cancels autoplay', () async {
    player.loadGate = Completer<void>();
    final loading = service.playAlbum(client, tracks, 0);
    await Future<void>.delayed(Duration.zero);
    await service.pause();
    player.loadGate!.complete();
    await loading;
    expect(player.playCalls, 0);
    expect(service.playbackState.value.playing, isFalse);
  });

  test(
    'disconnect during loading clears queue and prevents autoplay',
    () async {
      player.loadGate = Completer<void>();
      final loading = service.playAlbum(client, tracks, 0);
      await Future<void>.delayed(Duration.zero);
      final reset = service.reset();
      player.loadGate!.complete();
      await Future.wait([loading, reset]);
      expect(player.playCalls, 0);
      expect(service.queue.value, isEmpty);
      expect(service.mediaItem.value, isNull);
    },
  );

  test('native failures are sanitized and a new selection recovers', () async {
    player.failNextLoad = true;
    await service.playAlbum(client, tracks, 0);
    expect(
      service.playbackState.value.processingState,
      AudioProcessingState.error,
    );
    expect(service.error.value, isNot(contains('secret-auth-url')));
    expect(player.playCalls, 0);
    await service.playAlbum(client, tracks, 1);
    expect(service.error.value, isNull);
    expect(
      service.playbackState.value.processingState,
      AudioProcessingState.ready,
    );
    expect(player.playCalls, 1);
  });

  test('play after album completion restarts at the beginning', () async {
    await service.playAlbum(client, tracks, 1);
    player.processingState = ProcessingState.completed;
    player.emit();
    expect(service.playbackState.value.playing, isFalse);
    await service.play();
    expect(player.currentIndex, 0);
    expect(player.position, Duration.zero);
  });
}
