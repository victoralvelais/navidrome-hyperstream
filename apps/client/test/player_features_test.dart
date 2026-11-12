import 'dart:async';

import 'package:audio_service/audio_service.dart';
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
  late Map<String, Completer<Uri?>> art;
  late DateTime now;
  final tracks = List.generate(
    4,
    (i) => Track(
      id: 'song-$i',
      title: 'Song $i',
      artist: 'Artist',
      album: 'Album',
      duration: const Duration(minutes: 3),
      coverArt: 'cover-$i',
      container: 'mp3',
      bitRate: 320,
      albumId: 'album',
      artistId: 'artist',
      userRating: 3,
    ),
  );
  setUp(() {
    player = FakePlayer();
    art = {};
    now = DateTime.utc(2026, 11, 12, 12);
    service = PlaybackService(
      player: player,
      timerClock: () => now,
      artworkLoader: (_, id) => (art[id] ??= Completer<Uri?>()).future,
    );
    client = NavidromeClient(
      serverUrl: 'https://music.example.com',
      username: 'test',
      password: 'secret',
    );
  });
  tearDown(() async {
    await service.dispose();
    client.close();
  });

  test('local system artwork follows the current item and rejects stale replacements', () async {
    await service.playAlbum(client, tracks, 0);
    expect(service.mediaItem.value!.extras!['audioDetails'], 'MP3 · 320 kbps');
    await service.skipToNext();
    art['cover-0']!.complete(Uri.parse('file:///hyperstream-test/first.png'));
    await Future<void>.delayed(Duration.zero);
    expect(service.mediaItem.value!.id, 'song-1');
    expect(service.mediaItem.value!.artUri, isNull);
    art['cover-1']!.complete(Uri.parse('file:///hyperstream-test/second.png'));
    await Future<void>.delayed(Duration.zero);
    expect(service.mediaItem.value!.artUri!.scheme, 'file');
    await service.skipToNext();
    await service.playAlbum(client, [tracks.last], 0);
    art['cover-2']!.complete(Uri.parse('file:///hyperstream-test/stale.png'));
    await Future<void>.delayed(Duration.zero);
    expect(service.mediaItem.value!.id, 'song-3');
    expect(service.mediaItem.value!.artUri, isNull);
    art['cover-3']!.complete(
      Uri.parse('https://music.example.com/cover?token=secret'),
    );
    await Future<void>.delayed(Duration.zero);
    expect(service.mediaItem.value!.artUri, isNull);
  });

  test('shuffle, repeat, and playback rate reflect native state', () async {
    await service.playAlbum(client, tracks, 0);
    await service.setShuffleMode(AudioServiceShuffleMode.all);
    player.shuffleIndices = [0, 3, 1, 2];
    expect(service.upcomingIndices, [3, 1, 2]);
    expect(
      service.playbackState.value.shuffleMode,
      AudioServiceShuffleMode.all,
    );
    await service.setRepeatMode(AudioServiceRepeatMode.one);
    expect(player.loopMode, LoopMode.one);
    expect(service.playbackState.value.repeatMode, AudioServiceRepeatMode.one);
    await service.setSpeed(1.25);
    expect(service.playbackState.value.speed, 1.25);
    await service.setSpeed(double.nan);
    expect(player.speed, 1.25);
  });

  test('deadline sleeps after a suspended interval and cancellation leaves audio playing', () async {
    await service.playAlbum(client, tracks, 0);
    service.setSleepTimer(duration: const Duration(minutes: 15));
    now = now.add(const Duration(minutes: 16));
    player.emit();
    await Future<void>.delayed(Duration.zero);
    expect(player.playing, isFalse);
    expect(service.sleepTimer.value, isNull);
    await service.play();
    service.setSleepTimer(duration: const Duration(minutes: 15));
    service.cancelSleepTimer();
    now = now.add(const Duration(hours: 1));
    player.emit();
    expect(player.playing, isTrue);
  });

  test(
    'end-of-track sleep handles native transitions, repeat-one, and reset',
    () async {
      await service.playAlbum(client, tracks, 0);
      service.setSleepTimer(endOfTrack: true);
      player.currentIndex = 1;
      player.emit();
      await Future<void>.delayed(Duration.zero);
      expect(player.playing, isFalse);
      expect(service.sleepTimer.value, isNull);
      await service.play();
      player.position = const Duration(minutes: 2);
      service.setSleepTimer(endOfTrack: true);
      player.position = Duration.zero;
      player.emit();
      await Future<void>.delayed(Duration.zero);
      expect(player.playing, isFalse);
      service.setSleepTimer(endOfTrack: true);
      await service.reset();
      expect(service.sleepTimer.value, isNull);
    },
  );

  test(
    'reorder and remove preserve the current song, position, and metadata',
    () async {
      await service.playAlbum(client, tracks, 0);
      player.position = const Duration(seconds: 55);
      await service.moveUpcoming(3, 1);
      expect(service.queue.value.map((item) => item.id), [
        'song-0',
        'song-3',
        'song-1',
        'song-2',
      ]);
      expect(service.mediaItem.value!.id, 'song-0');
      expect(player.position, const Duration(seconds: 55));
      expect(service.trackAt(1)!.id, 'song-3');
      await service.removeUpcoming(2);
      expect(service.queue.value.map((item) => item.id), [
        'song-0',
        'song-3',
        'song-2',
      ]);
      await service.removeUpcoming(0);
      expect(service.queue.value.length, 3);
      expect(player.playing, isTrue);
    },
  );

  test(
    'a new selection wins an in-flight queue edit and native failure is safe',
    () async {
      await service.playAlbum(client, tracks, 0);
      player.editGate = Completer<void>();
      final edit = service.moveUpcoming(3, 1);
      await Future<void>.delayed(Duration.zero);
      final replace = service.playAlbum(client, [tracks[2]], 0);
      player.editGate!.complete();
      await Future.wait([edit, replace]);
      expect(service.queue.value.single.id, 'song-2');
      await service.playAlbum(client, tracks, 0);
      player.failEdit = true;
      await service.removeUpcoming(2);
      expect(service.queue.value, isEmpty);
      expect(player.playing, isFalse);
      expect(service.error.value, isNotNull);
    },
  );

  test('activity overlays preserve navigation, rating and file metadata', () {
    final track = tracks.first
        .withLastPlayedAt(now)
        .withActivity(favorite: true);
    expect(track.albumId, 'album');
    expect(track.artistId, 'artist');
    expect(track.audioDetails, 'MP3 · 320 kbps');
    expect(track.userRating, 3);
  });
}
