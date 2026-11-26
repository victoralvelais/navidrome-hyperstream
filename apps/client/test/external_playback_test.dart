import 'dart:io';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:just_audio/just_audio.dart';
import 'package:hyperstream_client/models/library.dart';
import 'package:hyperstream_client/models/source_reference.dart';
import 'package:hyperstream_client/services/mornye_sources.dart';
import 'package:hyperstream_client/services/navidrome_client.dart';
import 'package:hyperstream_client/services/playback_service.dart';
import 'package:hyperstream_client/services/playback_store.dart';
import 'package:hyperstream_client/services/recent_radio_service.dart';
import 'package:hyperstream_client/services/music_sources.dart';
import 'package:hyperstream_client/services/music_provider.dart';

import 'support/fake_player.dart';

const externalSong = Track(
  id: 'external:mornye:tidal-web:one',
  title: 'Song',
  artist: 'Artist',
  album: 'Album',
  duration: Duration(minutes: 3),
  source: SourceReference(sourceId: 'mornye:tidal-web', trackId: 'one'),
);

const librarySong = Track(
  id: 'library-song',
  title: 'Library',
  artist: 'Artist',
  album: 'Album',
  duration: Duration(minutes: 3),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  PlaybackService stalledPlayback(
    WidgetTester tester,
    NavidromeClient client,
    AudioPlayer player, {
    Duration sourceLoadTimeout = const Duration(seconds: 90),
  }) {
    final playback = PlaybackService(
      player: player,
      configureSession: (_) async {},
      sourceStreamUri: (_) => Uri.parse('http://127.0.0.1/synthetic'),
      timerClock: tester.binding.clock.now,
      sourceLoadTimeout: sourceLoadTimeout,
    );
    addTearDown(() async {
      client.close();
      final disposing = playback.dispose();
      await tester.pump();
      await disposing;
    });
    return playback;
  }

  for (final replaceSong in [false, true]) {
    testWidgets(
      replaceSong
          ? 'selecting a new song supersedes a stuck external load'
          : 'external load timeout re-enables manual Play',
      (tester) async {
        final client = NavidromeClient(
          serverUrl: 'https://library.example',
          username: 'test',
          password: 'test',
        );
        final nativeLoad = Completer<Duration?>();
        final player = _DelayedLoadsPlayer([nativeLoad.future]);
        final playback = stalledPlayback(
          tester,
          client,
          player,
          sourceLoadTimeout: const Duration(seconds: 1),
        );
        final original = playback.playAlbum(client, [externalSong], 0);
        await tester.pump();
        expect(player.delayedLoads, 1);
        if (replaceSong) {
          final replacement = playback.playAlbum(client, [librarySong], 0);
          await tester.pump();
          expect(player.playCalls, 1);
          await replacement;
        } else {
          await tester.pump(const Duration(seconds: 1));
          expect(
            playback.error.value,
            allOf(contains('Tidal'), contains('Play')),
          );
          await playback.play();
        }
        await original;
        expect(player.playCalls, 1);
        nativeLoad.complete(null);
        await tester.pump();
        expect(player.playCalls, 1);
        expect(
          playback.mediaItem.value?.id,
          replaceSong ? librarySong.id : externalSong.id,
        );
        expect(playback.error.value, isNull);
        await playback.pause();
      },
    );
  }

  testWidgets('slow external load failures exhaust automatic retries', (
    tester,
  ) async {
    final client = NavidromeClient(
      serverUrl: 'https://library.example',
      username: 'test',
      password: 'test',
    );
    final failures = List.generate(3, (_) => Completer<Duration?>());
    final player = _DelayedLoadsPlayer([
      for (final failure in failures) failure.future,
    ]);
    final playback = stalledPlayback(tester, client, player);
    final original = playback.playAlbum(client, [externalSong], 0);
    await tester.pump();
    for (final (index, failure) in failures.indexed) {
      expect(player.delayedLoads, index + 1);
      await tester.pump(const Duration(seconds: 61));
      failure.completeError(PlayerException(1, 'synthetic failure', 0));
      await tester.pump();
      await tester.pump(Duration(seconds: [2, 5, 10][index]));
    }
    await original;
    expect(player.loaded, isEmpty);
    expect(player.playCalls, 0);
    expect(playback.reconnecting, isFalse);
    expect(playback.error.value, contains('Play'));
    await playback.play();
    expect(player.playCalls, 1);
    await playback.pause();
  });

  for (final failureBelongsToSelection in [true, false]) {
    testWidgets(
      failureBelongsToSelection
          ? 'exhausted providers stop automatic retries but allow manual Play'
          : 'a preloaded recording failure does not suppress active recovery',
      (tester) async {
        const preloaded = Track(
          id: 'external:mornye:tidal-web:two',
          title: 'Other recording',
          artist: 'Artist',
          album: 'Album',
          duration: Duration(minutes: 3),
          source: SourceReference(sourceId: 'mornye:tidal-web', trackId: 'two'),
        );
        final client = NavidromeClient(
          serverUrl: 'https://library.example',
          username: 'test',
          password: 'test',
        );
        final player = FakePlayer()..failNextLoad = true;
        SourceException? blockingFailure = const SourceException(
          'Audio providers could not supply this recording.',
          retryable: false,
        );
        final failureTrack = failureBelongsToSelection
            ? externalSong
            : preloaded;
        final playback = PlaybackService(
          player: player,
          configureSession: (_) async {},
          sourceStreamUri: (source) =>
              Uri.parse('http://127.0.0.1/${source.trackId}'),
          sourceFailure: (source) =>
              source.identity == failureTrack.source!.identity
              ? blockingFailure
              : null,
          timerClock: tester.binding.clock.now,
        );
        addTearDown(() async {
          client.close();
          final disposing = playback.dispose();
          await tester.pump();
          await disposing;
        });

        await playback.playAlbum(client, const [externalSong, preloaded], 0);
        expect(player.loaded, hasLength(1));
        expect(playback.reconnecting, !failureBelongsToSelection);
        if (failureBelongsToSelection) {
          expect(playback.canRetryPlayback, isTrue);
          await tester.pump(const Duration(minutes: 1));
          expect(player.loaded, hasLength(1));
          expect(player.playing, isFalse);
          blockingFailure = null;
          await playback.play();
        } else {
          await tester.pump(const Duration(seconds: 2));
          await tester.pumpAndSettle();
        }
        expect(player.loaded, hasLength(2));
        expect(player.playing, isTrue);
        expect(playback.mediaItem.value?.id, externalSong.id);
        expect(playback.error.value, isNull);
        await playback.pause();
      },
    );
  }

  testWidgets(
    'current track label follows provider updates during and after load',
    (tester) async {
      const song = Track(
        id: 'external:spotify',
        title: 'Song',
        artist: 'Artist',
        album: 'Album',
        duration: Duration(minutes: 2),
        source: SourceReference(sourceId: 'mornye:spotify-web', trackId: 'one'),
      );
      final info = ValueNotifier<Map<String, SourcePlaybackInfo>>({});
      final client = NavidromeClient(
        serverUrl: 'https://library.example',
        username: 'test',
        password: 'test',
      );
      final loadGate = Completer<void>();
      final player = FakePlayer()..loadGate = loadGate;
      final playback = PlaybackService(
        player: player,
        sourceStreamUri: (_) => Uri.parse('http://127.0.0.1/synthetic'),
        sourcePlaybackInfo: info,
      );
      addTearDown(() async {
        final disposing = playback.dispose();
        await tester.pump();
        await disposing;
        info.dispose();
        client.close();
      });
      final loading = playback.playAlbum(client, const [song], 0);
      await tester.pump();
      expect(player.loaded, hasLength(1));
      info.value = {
        song.source!.identity: const SourcePlaybackInfo(
          sourceId: 'mornye:qobuz-web',
          format: 'flac',
        ),
      };
      loadGate.complete();
      await loading;
      expect(
        playback.queue.value.single.extras?['audioDetails'],
        'Qobuz · FLAC',
      );
      expect(
        playback.queue.value.single.extras?['sourceId'],
        song.source!.sourceId,
      );
      expect(
        playback.queue.value.single.extras?['playbackSourceId'],
        'mornye:qobuz-web',
      );
      expect(
        playback.mediaItem.value?.extras?['playbackSourceId'],
        'mornye:qobuz-web',
      );
      expect(playback.mediaItem.value?.extras?['audioDetails'], 'Qobuz · FLAC');

      info.value = {
        song.source!.identity: const SourcePlaybackInfo(
          sourceId: 'mornye:tidal-web',
          format: 'aac',
          bitRate: 132,
          bitRateEstimated: true,
        ),
      };
      expect(
        playback.queue.value.single.extras?['audioDetails'],
        'Tidal · AAC · ≈132 kbps',
      );
      expect(
        playback.mediaItem.value?.extras?['playbackSourceId'],
        'mornye:tidal-web',
      );
      await playback.pause();
      expect(
        playback.mediaItem.value?.extras?['audioDetails'],
        'Tidal · AAC · ≈132 kbps',
      );
    },
  );
  testWidgets('a pending Qobuz challenge does not block SoundCloud recovery', (
    tester,
  ) async {
    final sources = MusicSources.instance.extensions!;
    final client = NavidromeClient(
      serverUrl: 'https://library.example',
      username: 'test',
      password: 'test',
    );
    final player = FakePlayer()..failNextLoad = true;
    var prompts = 0;
    final playback = PlaybackService(
      player: player,
      sourceStreamUri: (_) => Uri.parse('http://127.0.0.1/synthetic'),
      verifySource: (_) async {
        prompts++;
        return false;
      },
    );
    addTearDown(() async {
      sources.issue.value = null;
      sources.verification.value = null;
      final disposing = playback.dispose();
      await tester.pump();
      await disposing;
      client.close();
    });
    sources.verification.value = 'qobuz-web';
    sources.issue.value = 'This source could not connect.';
    await playback.playAlbum(client, const [
      Track(
        id: 'external:soundcloud:one',
        title: 'Upload',
        artist: 'Creator',
        album: '',
        duration: Duration(minutes: 3),
        source: SourceReference(sourceId: 'mornye:soundcloud', trackId: 'one'),
      ),
    ], 0);
    expect(prompts, 0);
    expect(playback.reconnecting, true);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(player.playing, true);
    expect(playback.error.value, isNull);
    expect(prompts, 0);
    expect(sources.verification.value, 'qobuz-web');
    await playback.pause();
  });
  testWidgets(
    'initial stream failure starts verification and resumes playback automatically',
    (tester) async {
      final sources = MusicSources.instance.extensions!;
      final client = NavidromeClient(
        serverUrl: 'https://library.example',
        username: 'user',
        password: 'private',
      );
      final player = FakePlayer()..failNextLoad = true;
      final verification = Completer<bool>();
      var prompts = 0;
      final playback = PlaybackService(
        player: player,
        sourceStreamUri: (_) => Uri.parse('http://127.0.0.1/synthetic'),
        sourceFailure: (_) => sources.verification.value == 'tidal-web'
            ? ProviderVerificationRequired('tidal-web', name: 'Tidal')
            : null,
        verifySource: (_) {
          prompts++;
          return verification.future;
        },
      );
      addTearDown(() async {
        sources.issue.value = null;
        sources.verification.value = null;
        client.close();
        final disposing = playback.dispose();
        await tester.pump();
        await disposing;
      });
      sources.issue.value =
          'Tidal needs verification. Open Music sources and choose Verify.';
      sources.verification.value = 'tidal-web';
      await playback.playAlbum(client, [externalSong], 0);
      expect(player.currentIndex, isNull);
      expect(playback.trackAt(0), isNull);
      expect(playback.error.value, contains('Tidal needs verification'));
      expect(playback.reconnecting, false);
      expect(prompts, 1);
      player.errors.add(PlayerException(1, 'private', 0));
      await tester.pump(const Duration(minutes: 1));
      expect(player.loaded, hasLength(1));
      sources.issue.value = null;
      sources.verification.value = null;
      verification.complete(true);
      await tester.pumpAndSettle();
      expect(prompts, 1);
      expect(player.playing, true);
      expect(playback.error.value, isNull);
      await playback.pause();
    },
  );

  for (final action in ['pause', 'new queue', 'cancel', 'challenge again']) {
    testWidgets('$action prevents unwanted verification playback retries', (
      tester,
    ) async {
      final sources = MusicSources.instance.extensions!;
      final client = NavidromeClient(
        serverUrl: 'https://library.example',
        username: 'user',
        password: 'private',
      );
      final player = _VerificationPlayer(() {
        sources.issue.value = 'Tidal needs verification to continue.';
        sources.verification.value = 'tidal-web';
      })..failNextLoad = true;
      final verification = Completer<bool>();
      var prompts = 0;
      final playback = PlaybackService(
        player: player,
        sourceStreamUri: (_) => Uri.parse('http://127.0.0.1/synthetic'),
        sourceFailure: (_) => sources.verification.value == 'tidal-web'
            ? ProviderVerificationRequired('tidal-web', name: 'Tidal')
            : null,
        verifySource: (_) {
          prompts++;
          return verification.future;
        },
      );
      addTearDown(() async {
        sources.issue.value = null;
        sources.verification.value = null;
        client.close();
        final disposing = playback.dispose();
        await tester.pump();
        await disposing;
      });
      sources.issue.value = 'Tidal needs verification to continue.';
      sources.verification.value = 'tidal-web';
      await playback.playAlbum(client, [externalSong], 0);
      if (action == 'pause') await playback.pause();
      if (action == 'new queue') {
        await playback.playAlbum(client, const [
          Track(
            id: 'library',
            title: 'Library',
            artist: 'Artist',
            album: 'Album',
            duration: Duration(minutes: 3),
          ),
        ], 0);
      }
      if (action == 'challenge again') player.failNextLoad = true;
      verification.complete(action != 'cancel');
      await tester.pumpAndSettle();
      await tester.pump(const Duration(minutes: 1));
      expect(prompts, 1);
      expect(player.playing, action == 'new queue');
      expect(
        player.loaded,
        hasLength(action == 'new queue' || action == 'challenge again' ? 2 : 1),
      );
      if (action == 'new queue') {
        expect(playback.mediaItem.value!.id, 'library');
      }
      await playback.pause();
    });
  }
  testWidgets(
    'qualified external playback enters local history without a Navidrome scrobble',
    (tester) async {
      final calls = <String>[];
      final client = NavidromeClient(
        serverUrl: 'https://library.example',
        username: 'user',
        password: 'private',
        httpClient: MockClient((request) async {
          calls.add(request.url.path);
          return http.Response('{}', 200);
        }),
      );
      final player = FakePlayer();
      var elapsed = Duration.zero;
      final start = DateTime.utc(2026, 11, 12);
      final radio = RecentRadioService(client, now: () => start.add(elapsed));
      addTearDown(radio.dispose);
      final playback = PlaybackService(
        player: player,
        configureSession: (_) async {},
        listeningClock: () => elapsed,
        listeningTime: () => start.add(elapsed),
        sourceStreamUri: (source) =>
            Uri.parse('https://source.example/track/${source.trackId}'),
      );
      addTearDown(() async {
        client.close();
        final disposing = playback.dispose();
        await tester.pump();
        await disposing;
      });
      await playback.playAlbum(client, [externalSong], 0);
      await tester.pump();
      expect(
        (player.loaded.single.single as UriAudioSource).uri.host,
        'source.example',
      );
      expect(playback.trackAt(0)!.source!.sourceId, 'mornye:tidal-web');
      Future<void> listen(int seconds) async {
        for (var i = 0; i < seconds; i++) {
          elapsed += const Duration(seconds: 1);
          player.emit();
        }
        await tester.pump();
      }

      await listen(89);
      expect(radio.tracks, isEmpty);
      await listen(1);
      expect(
        radio.tracks.single.source!.identity,
        externalSong.source!.identity,
      );
      expect(radio.tracks.single.lastPlayedAt, start);
      expect(radio.tracks.single.playCount, 1);
      expect(radio.preview!.matches.single.track.id, externalSong.id);
      await listen(90);
      expect(radio.tracks.single.playCount, 1);
      await playback.preferences.setReportListens(false);
      await playback.playAlbum(client, [externalSong], 0);
      await listen(100);
      expect(radio.tracks.single.playCount, 1);
      expect(calls, isEmpty);
      await playback.setSpeed(.75);
      await playback.pause();
      expect(player.speed, .75);
      expect(player.playing, isFalse);
      await playback.playAlbum(client, const [librarySong], 0);
      expect(
        (player.loaded.last.single as UriAudioSource).uri.host,
        'library.example',
      );
      await playback.pause();
    },
  );

  test(
    'external queue roundtrip keeps stable IDs without resolved audio URLs',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'hyperstream-source-queue-',
      );
      final client = NavidromeClient(
        serverUrl: 'https://library.example',
        username: 'user',
        password: 'private',
      );
      try {
        final store = FilePlaybackStore(client, directory: () async => root);
        await store.write(
          const PlaybackSnapshot(
            tracks: [externalSong],
            coverArtIds: [null],
            index: 0,
            position: Duration(seconds: 30),
            speed: .75,
          ),
        );
        final restored = await FilePlaybackStore(
          client,
          directory: () async => root,
        ).read();
        expect(restored!.tracks.single.source!.trackId, 'one');
        expect(restored.position, const Duration(seconds: 30));
        final text = await File(
          '${root.path}/playback-v1/${store.accountKey}/queue.json',
        ).readAsString();
        expect(text, isNot(contains('https://')));
        expect(text, isNot(contains('private')));
      } finally {
        client.close();
        await root.delete(recursive: true);
      }
    },
  );
}

class _DelayedLoadsPlayer extends FakePlayer {
  _DelayedLoadsPlayer(this.results);
  final List<Future<Duration?>> results;
  int delayedLoads = 0;

  @override
  Future<Duration?> setAudioSources(
    List<AudioSource> audioSources, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
    ShuffleOrder? shuffleOrder,
  }) {
    if (delayedLoads < results.length) return results[delayedLoads++];
    return super.setAudioSources(
      audioSources,
      preload: preload,
      initialIndex: initialIndex,
      initialPosition: initialPosition,
      shuffleOrder: shuffleOrder,
    );
  }
}

class _VerificationPlayer extends FakePlayer {
  _VerificationPlayer(this.onFailure);
  final void Function() onFailure;
  @override
  Future<Duration?> setAudioSources(
    List<AudioSource> audioSources, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
    ShuffleOrder? shuffleOrder,
  }) {
    if (failNextLoad) onFailure();
    return super.setAudioSources(
      audioSources,
      preload: preload,
      initialIndex: initialIndex,
      initialPosition: initialPosition,
      shuffleOrder: shuffleOrder,
    );
  }
}
