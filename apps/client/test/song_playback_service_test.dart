import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyperstream_client/services/navidrome_client.dart';
import 'package:hyperstream_client/services/playback_service.dart';
import 'package:hyperstream_client/services/song_playback_store.dart';

import 'playback_continuity_test.dart' show continuityTracks;
import 'support/fake_player.dart';

class _TransitionPlayer extends FakePlayer {
  final indexChanges = StreamController<int?>.broadcast(sync: true);
  Completer<void>? speedGate;
  final editStarted = Completer<void>();

  @override
  Stream<int?> get currentIndexStream => indexChanges.stream;

  void advanceNaturally(int index) {
    currentIndex = index;
    indexChanges.add(index);
  }

  @override
  Future<void> setSpeed(double value) async {
    if (value == .77 && speedGate != null && !editStarted.isCompleted) {
      editStarted.complete();
      await speedGate!.future;
    }
    await super.setSpeed(value);
  }

  @override
  Future<void> dispose() async {
    await super.dispose();
    await indexChanges.close();
  }
}

void main() {
  late _TransitionPlayer player;
  late PlaybackService playback;
  late NavidromeClient client;
  late SongPlaybackStore store;
  const defaults = SongPlaybackSettings();

  String key(int index) =>
      SongPlaybackStore.keyFor(client, continuityTracks[index]);

  void expectSettings(SongPlaybackSettings expected) {
    expect(playback.songPlaybackSettings.value, expected);
    expect(player.speed, expected.speed);
    expect(player.preservesPitch, expected.keepPitch);
  }

  setUp(() {
    player = _TransitionPlayer()..supportsPitchControl = true;
    store = SongPlaybackStore();
    client = NavidromeClient(
      serverUrl: 'https://music.example.test',
      username: 'test-user',
      password: 'test-password',
    );
    playback = PlaybackService(
      player: player,
      songPlaybackStore: store,
      configureSession: (_) async {},
    );
  });

  tearDown(() async {
    await playback.dispose();
    client.close();
  });

  test(
    'edits follow song identity across next, previous, and duplicate entries',
    () async {
      expect(playback.canEditSongSettings, isFalse);
      await playback.setSpeed(.75);
      expectSettings(defaults);
      await playback.playAlbum(client, continuityTracks, 0);
      expect(playback.canEditSongSettings, isTrue);
      expectSettings(defaults);
      await playback.setSpeed(.75);
      await playback.setKeepPitch(false);
      await Future.wait([playback.adjustSpeed(.01), playback.adjustSpeed(.01)]);
      const saved = SongPlaybackSettings(speed: .77, keepPitch: false);
      expectSettings(saved);
      expect(store.get(key(0)), saved);
      expect(store.get(key(1)), defaults);
      await playback.skipToNext();
      expectSettings(defaults);
      await playback.setSpeed(1.25);
      await playback.skipToPrevious();
      expectSettings(saved);
      await playback.skipToQueueItem(2);
      expectSettings(saved);
      await playback.skipToPrevious();
      expectSettings(const SongPlaybackSettings(speed: 1.25));
      await playback.reset();
      expect(playback.canEditSongSettings, isFalse);
      expect(playback.songPlaybackSettings.value, defaults);
      await playback.playAlbum(client, continuityTracks, 0);
      expectSettings(saved);
    },
  );

  test(
    'a rejected saved setting does not stop the selected song from playing',
    () async {
      const saved = SongPlaybackSettings(speed: .75, keepPitch: false);
      await store.set(key(0), saved);
      player.failPitch = true;
      await playback.playAlbum(client, continuityTracks, 0);
      expect(player.playing, isTrue);
      expect(playback.error.value, isNull);
      expect(playback.settingsError.value, isNotNull);
      expect(store.get(key(0)), saved);
      player.failPitch = false;
      await playback.setSpeed(.75);
      expectSettings(saved);
      expect(playback.settingsError.value, isNull);
    },
  );

  test('a natural native index change applies persisted settings', () async {
    const saved = SongPlaybackSettings(speed: 1.5, keepPitch: false);
    await store.set(key(1), saved);
    await playback.playAlbum(client, continuityTracks, 0);
    expectSettings(defaults);
    final playCalls = player.playCalls;
    player.advanceNaturally(1);
    await pumpEventQueue();
    expect(playback.mediaItem.value?.id, 'two');
    expectSettings(saved);
    expect(player.playCalls, playCalls);
    expect(player.playing, isTrue);
  });

  test(
    'a delayed edit cannot overwrite a song reached by natural advance',
    () async {
      const nextSong = SongPlaybackSettings(speed: 1.5, keepPitch: false);
      await store.set(key(1), nextSong);
      await playback.playAlbum(client, continuityTracks, 0);
      player.speedGate = Completer<void>();
      final editing = playback.setSpeed(.77);
      await player.editStarted.future;
      player.advanceNaturally(1);
      await pumpEventQueue();
      player.speedGate!.complete();
      await editing;
      await pumpEventQueue();
      expectSettings(nextSong);
      expect(store.get(key(1)), nextSong);
    },
  );
}
