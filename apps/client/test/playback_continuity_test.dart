import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperstream_client/models/library.dart';
import 'package:hyperstream_client/services/navidrome_client.dart';
import 'package:hyperstream_client/services/playback_service.dart';
import 'package:hyperstream_client/services/playback_store.dart';
import 'package:just_audio/just_audio.dart';

import 'support/fake_player.dart';

class MemoryPlaybackStore implements PlaybackStore {
  PlaybackSnapshot? value;
  Completer<PlaybackSnapshot?>? reading;
  bool failRead = false;
  bool failWrite = false;
  int reads = 0;
  int writes = 0;
  @override
  Future<PlaybackSnapshot?> read() async {
    reads++;
    if (failRead) throw const FormatException('private data');
    return reading == null ? value : reading!.future;
  }

  @override
  Future<void> write(PlaybackSnapshot snapshot) async {
    writes++;
    if (failWrite) throw StateError('private filesystem details');
    value = snapshot;
  }

  @override
  Future<void> clear() async => value = null;
}

const continuityTracks = [
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
  Track(
    id: 'one',
    title: 'First again',
    artist: 'Artist',
    album: 'Album',
    duration: Duration(minutes: 3),
  ),
];

PlaybackSnapshot savedQueue({int index = 1, List<int> order = const []}) =>
    PlaybackSnapshot(
      tracks: continuityTracks,
      coverArtIds: const ['cover', 'cover', 'cover'],
      index: index,
      position: const Duration(seconds: 47),
      shuffleOrder: order,
      repeat: 'all',
      speed: 1.25,
    );

void main() {
  late MemoryPlaybackStore store;
  late FakePlayer player;
  late PlaybackService playback;
  late NavidromeClient client;
  setUp(() {
    store = MemoryPlaybackStore();
    player = FakePlayer();
    playback = PlaybackService(
      player: player,
      playbackStore: (_) => store,
      artworkLoader: (_, _) async => null,
    );
    client = NavidromeClient(
      serverUrl: 'https://example.test/music',
      username: 'one',
      password: 'new-password',
    );
  });
  tearDown(() async {
    await playback.dispose();
    client.close();
  });

  test('restores duplicate queue positions, position, settings and exact shuffle paused', () async {
    store.value = savedQueue(index: 2, order: [1, 2, 0]);
    await playback.attachAccount(client, remember: true);
    expect(playback.queue.value.map((e) => e.id), ['one', 'two', 'one']);
    expect(player.currentIndex, 2);
    expect(player.position, const Duration(seconds: 47));
    expect(player.shuffleIndices, [1, 2, 0]);
    expect(playback.earlierIndices, [1]);
    expect(playback.upcomingIndices, [0]);
    expect(player.playCalls, 0);
    expect(player.preloads, [false]);
    expect(playback.playbackState.value.playing, isFalse);
    expect(playback.playbackState.value.repeatMode, AudioServiceRepeatMode.all);
    expect(player.speed, 1.25);
    expect(playback.sleepTimer.value, isNull);
    expect(playback.queue.value.last.extras?['coverArtId'], 'cover');
    final uri = (player.loaded.single.first as UriAudioSource).uri;
    expect(uri.path, '/music/rest/stream.view');
    expect(uri.queryParameters['u'], 'one');
    expect(uri.queryParameters['id'], 'one');
    expect(uri.queryParameters.containsKey('t'), isTrue);
    // Native loading may ask for a shuffle again. It must keep the traversal.
    player.activeShuffleOrder!.shuffle(initialIndex: 2);
    expect(player.activeShuffleOrder!.indices, [1, 2, 0]);
    await playback.play();
    expect(player.playCalls, 1);
    expect(player.preloads, [false, true]);
    expect(player.position, const Duration(seconds: 47));
  });

  test(
    'pausing or clearing during restored activation prevents late playback',
    () async {
      store.value = savedQueue();
      await playback.attachAccount(client, remember: true);
      player.loadGate = Completer<void>();
      final activating = playback.play();
      await Future<void>.delayed(Duration.zero);
      await playback.pause();
      player.loadGate!.complete();
      await activating;
      expect(player.playCalls, 0);
      expect(player.currentIndex, 1);
      expect(player.position, const Duration(seconds: 47));
      await playback.suspendForAccountSwitch();
      await playback.attachAccount(client, remember: true);
      player.loadGate = Completer<void>();
      final restarting = playback.play();
      await Future<void>.delayed(Duration.zero);
      final clearing = playback.reset();
      player.loadGate!.complete();
      await Future.wait([restarting, clearing]);
      expect(playback.queue.value, isEmpty);
      expect(player.playCalls, 0);
      expect(store.value, isNull);
    },
  );

  test(
    'paused seeks and queue edits survive service disposal and recreation',
    () async {
      await playback.attachAccount(client, remember: true);
      await playback.playAlbum(
        client,
        continuityTracks,
        0,
        coverArtId: 'fallback',
      );
      await playback.pause();
      await playback.moveUpcoming(2, 1);
      await playback.removeUpcoming(2);
      await playback.seek(const Duration(seconds: 38));
      await playback.setRepeatMode(AudioServiceRepeatMode.one);
      await playback.savePlayback();
      await playback.dispose();
      player = FakePlayer();
      playback = PlaybackService(
        player: player,
        playbackStore: (_) => store,
        artworkLoader: (_, _) async => null,
      );
      await playback.attachAccount(client, remember: true);
      expect(playback.queue.value.map((e) => e.title), [
        'First',
        'First again',
      ]);
      expect(player.position, const Duration(seconds: 38));
      expect(
        playback.playbackState.value.repeatMode,
        AudioServiceRepeatMode.one,
      );
      expect(player.playCalls, 0);
    },
  );

  test(
    'explicit clear is persistent and disposal does not resurrect it',
    () async {
      store.value = savedQueue();
      await playback.attachAccount(client, remember: true);
      await playback.reset();
      await playback.savePlayback();
      expect(store.value, isNull);
      expect(playback.queue.value, isEmpty);
    },
  );

  test('failed retries keep the restored position and Play recovers', () async {
    store.value = savedQueue(index: 2, order: [1, 2, 0]);
    await playback.attachAccount(client, remember: true);
    player.errors.add(PlayerException(1, 'private-url', 2));
    player.failNextLoad = true;
    await playback.play();
    expect(playback.error.value, isNotNull);
    await playback.play();
    expect(playback.error.value, isNull);
    expect(player.playing, isTrue);
    expect(player.currentIndex, 2);
    expect(player.position, const Duration(seconds: 47));
    expect(player.shuffleIndices, [1, 2, 0]);
  });

  test(
    'an unavailable current track can be bypassed without losing the queue',
    () async {
      store.value = savedQueue();
      await playback.attachAccount(client, remember: true);
      player.errors.add(PlayerException(1, 'missing-track', 1));
      await playback.skipToQueueItem(2);
      expect(playback.error.value, isNull);
      expect(player.currentIndex, 2);
      expect(player.position, Duration.zero);
      expect(player.playing, isTrue);
      expect(playback.queue.value, hasLength(3));
    },
  );

  test('new selection wins a slow restoration read', () async {
    store.reading = Completer();
    final restoring = playback.attachAccount(client, remember: true);
    await playback.playAlbum(client, [continuityTracks.first], 0);
    store.reading!.complete(savedQueue());
    await restoring;
    expect(playback.queue.value, hasLength(1));
    expect(player.playCalls, 1);
    expect(store.value!.tracks, hasLength(1));
  });

  test('disposing during a native load prevents late autoplay', () async {
    player.loadGate = Completer<void>();
    final loading = playback.playAlbum(client, continuityTracks, 0);
    await Future<void>.delayed(Duration.zero);
    final closing = playback.dispose();
    player.loadGate!.complete();
    await Future.wait([loading, closing]);
    expect(player.playCalls, 0);
    // The standard teardown owns this replacement; the original is disposed.
    playback = PlaybackService(player: FakePlayer());
  });

  test('clear during a slow read suppresses the stored queue', () async {
    store.reading = Completer();
    final restoring = playback.attachAccount(client, remember: true);
    await playback.reset();
    store.reading!.complete(savedQueue());
    await restoring;
    expect(store.value, isNull);
    expect(player.loaded, isEmpty);
  });

  test('temporary sessions neither restore nor write saved playback', () async {
    store.value = savedQueue();
    await playback.attachAccount(client, remember: false);
    await playback.playAlbum(client, continuityTracks, 0);
    await playback.savePlayback();
    expect(store.reads, 0);
    expect(store.writes, 0);
    expect(store.value!.index, 1);
  });

  test(
    'unreadable data is preserved and writes failing do not stop playback',
    () async {
      store.failRead = true;
      store.value = savedQueue();
      await playback.attachAccount(client, remember: true);
      await playback.playAlbum(client, continuityTracks, 0);
      await playback.savePlayback();
      expect(store.writes, 0);
      expect(
        playback.continuityNotice.value,
        contains('could not be restored'),
      );
      expect(playback.error.value, isNull);
      expect(player.playing, isTrue);
    },
  );

  test('save failure gives a sanitized notice and can recover', () async {
    await playback.attachAccount(client, remember: true);
    store.failWrite = true;
    await playback.playAlbum(client, continuityTracks, 0);
    await playback.savePlayback();
    expect(playback.continuityNotice.value, contains('could not be saved'));
    expect(player.playing, isTrue);
    expect(playback.error.value, isNull);
    store.failWrite = false;
    await playback.savePlayback();
    expect(playback.continuityNotice.value, isNull);
  });

  test(
    'switching accounts saves old queue and ignores its late restoration',
    () async {
      final otherStore = MemoryPlaybackStore()..value = savedQueue(index: 0);
      final other = NavidromeClient(
        serverUrl: 'https://example.test/music',
        username: 'two',
        password: 'different',
      );
      addTearDown(other.close);
      await playback.dispose();
      player = FakePlayer();
      playback = PlaybackService(
        player: player,
        playbackStore: (c) => c.username == 'one' ? store : otherStore,
        artworkLoader: (_, _) async => null,
      );
      store.reading = Completer();
      final oldRead = playback.attachAccount(client, remember: true);
      await playback.suspendForAccountSwitch();
      await playback.attachAccount(other, remember: true);
      store.reading!.complete(savedQueue(index: 2));
      await oldRead;
      expect(player.currentIndex, 0);
      await playback.seek(const Duration(seconds: 23));
      await playback.suspendForAccountSwitch();
      expect(otherStore.value!.position, const Duration(seconds: 23));
      expect(store.writes, 0);
      store.reading = null;
      store.value = savedQueue(index: 2);
      await playback.attachAccount(client, remember: true);
      expect(player.currentIndex, 2);
      expect(player.position, const Duration(seconds: 47));
    },
  );
}
