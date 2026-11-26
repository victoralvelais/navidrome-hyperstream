import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperstream_client/features/player/player_controls.dart';
import 'package:hyperstream_client/services/navidrome_client.dart';
import 'package:hyperstream_client/services/playback_diagnostics.dart';
import 'package:hyperstream_client/services/playback_service.dart';
import 'package:hyperstream_client/services/song_playback_store.dart';
import 'package:just_audio/just_audio.dart';

import 'playback_continuity_test.dart'
    show MemoryPlaybackStore, savedQueue, continuityTracks;
import 'support/account_fakes.dart';
import 'support/fake_player.dart';

class _Recovery {
  _Recovery({
    FakePlayer? player,
    this.resetSourcePlayback,
    this.songPlaybackStore,
  }) : player = player ?? FakePlayer();
  final FakePlayer player;
  final SongPlaybackStore? songPlaybackStore;
  final Future<void> Function()? resetSourcePlayback;
  final diagnostics = PlaybackDiagnostics();
  final client = AccountClient(
    serverUrl: 'https://example.test',
    username: 'user',
    password: 'secret',
  );
  final store = MemoryPlaybackStore()
    ..value = savedQueue(index: 2, order: [1, 2, 0]);
  late final playback = PlaybackService(
    player: player,
    songPlaybackStore: songPlaybackStore,
    playbackStore: (_) => store,
    artworkLoader: (_, _) async => null,
    resetSourcePlayback: resetSourcePlayback,
    diagnostics: diagnostics,
  );

  Future<void> failPlay() async {
    await playback.attachAccount(client, remember: true);
    player.failNextLoad = true;
    await playback.play();
    expect(
      playback.playbackState.value.processingState,
      AudioProcessingState.error,
    );
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    var closed = false;
    final closing = playback.dispose().whenComplete(() => closed = true);
    // Constant empty player streams complete cancellation in the real root
    // zone; drain it as well as the widget test's fake clock during teardown.
    for (var i = 0; i < 20 && !closed; i++) {
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }
    expect(closed, isTrue);
    await closing;
    client.close();
  }
}

void main() {
  testWidgets('playback diagnostics can be copied before and after recovery', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final f = _Recovery();
    final clipboard = <String>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard.add(call.arguments['text'] as String);
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await f.failPlay();
    f.diagnostics.record(
      stage: PlaybackStage.transport,
      outcome: PlaybackOutcome.failed,
      sourceId: 'mornye:qobuz-web',
      privateError: 'HTTP 429 at https://private.example/secret?token=secret',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.iOS),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: PlayerControls(playback: f.playback, client: f.client),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> copyDetails() async {
      await tester.tap(find.text('Playback details'));
      await tester.pumpAndSettle();
      expect(find.text('Playback diagnostics'), findsOneWidget);
      await tester.tap(find.text('Copy diagnostics'));
      await tester.pumpAndSettle();
      expect(clipboard.last, contains('rate-limited'));
      expect(clipboard.last, contains('429'));
      expect(clipboard.last, contains('Qobuz'));
      expect(clipboard.last, isNot(contains('private.example')));
      expect(clipboard.last, isNot(contains('secret')));
      await tester.tap(find.text('Done').last);
      await tester.pumpAndSettle();
      tester
          .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
          .removeCurrentSnackBar();
      await tester.pumpAndSettle();
    }

    await copyDetails();
    await tester.tap(find.byTooltip('Play'));
    await tester.pumpAndSettle();
    expect(f.playback.error.value, isNull);
    expect(find.text('Playback details'), findsNothing);
    await tester.tap(find.text(f.playback.mediaItem.value!.title));
    await tester.pumpAndSettle();
    final queue = find.byTooltip('Show queue');
    await Scrollable.ensureVisible(tester.element(queue), alignment: .35);
    await tester.pumpAndSettle();
    await tester.tap(queue);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Queue options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Player info'));
    await tester.pumpAndSettle();
    await copyDetails();
    expect(clipboard, hasLength(2));
    await f.close(tester);
  });

  testWidgets(
    'Play recovers from a failed load while song edits are disabled',
    (tester) async {
      final player = _SpeedGatedPlayer()..supportsPitchControl = true;
      final f = _Recovery(player: player);
      final stuck = Completer<void>();
      f.player.loadGate = stuck;
      var finished = false;
      final loading = f.playback
          .playAlbum(f.client, continuityTracks, 1)
          .whenComplete(() => finished = true);
      await tester.pump();
      expect(finished, false);
      expect(f.playback.canEditSongSettings, isFalse);
      final speedChange = f.playback.setSpeed(.75);
      await tester.pump();
      expect(player.speedChangeStarted, isFalse);
      await speedChange;
      f.player.errors.add(PlayerException(1, 'private native failure', 1));
      await tester.pumpAndSettle();
      expect(
        finished,
        true,
        reason: 'Recovery must not queue behind an abandoned native load.',
      );
      await loading;
      expect(f.playback.canRetryPlayback, true);
      f.player.loadGate = null;
      var recovered = false;
      final retry = f.playback.play().whenComplete(() => recovered = true);
      await tester.pumpAndSettle();
      expect(recovered, isTrue);
      await retry;
      expect(f.player.playing, true);
      expect(f.player.currentIndex, 1);
      expect(f.playback.error.value, isNull);
      stuck.completeError(PlayerException(1, 'late old failure', 1));
      await tester.pumpAndSettle();
      expect(f.playback.error.value, isNull);
      expect(f.player.playing, true);
      await f.close(tester);
    },
  );
  testWidgets('Play recovers while a prior song edit is pending', (
    tester,
  ) async {
    final player = _SpeedGatedPlayer()..supportsPitchControl = true;
    final f = _Recovery(player: player);
    await f.playback.playAlbum(f.client, continuityTracks, 1);
    final speedChange = f.playback.setSpeed(.75);
    await tester.pump();
    expect(player.speedChangeStarted, isTrue);
    player.errors.add(PlayerException(1, 'private native failure', 1));
    await tester.pumpAndSettle();
    expect(f.playback.canRetryPlayback, isTrue);
    var recovered = false;
    final retry = f.playback.play().whenComplete(() => recovered = true);
    await tester.pumpAndSettle();
    expect(recovered, isTrue);
    await retry;
    expect(player.playing, isTrue);
    expect(player.currentIndex, 1);
    expect(player.speed, 1);
    player.speedChangeGate.complete();
    await speedChange;
    await tester.pumpAndSettle();
    expect(player.speed, 1);
    expect(f.playback.error.value, isNull);
    await f.close(tester);
  });

  for (final action in ['Play', 'automatic retry', 'another song']) {
    testWidgets('$action rebuilds a failed native player and source session', (
      tester,
    ) async {
      final player = _StickyPlayer()..supportsPitchControl = true;
      var sourceResets = 0;
      final brokenAtSourceReset = <bool>[];
      final f = _Recovery(
        player: player,
        songPlaybackStore: SongPlaybackStore(),
        resetSourcePlayback: () async {
          brokenAtSourceReset.add(player.broken);
          sourceResets++;
        },
      );
      await f.songPlaybackStore!.set(
        SongPlaybackStore.keyFor(f.client, continuityTracks[2]),
        const SongPlaybackSettings(speed: .75, keepPitch: false),
      );
      await f.playback.attachAccount(f.client, remember: true);
      await f.playback.play();
      expect(player.pitchAtLoad, isNotEmpty);
      expect(player.pitchAtLoad, everyElement(false));
      player.position = const Duration(seconds: 62);
      await player.setVolume(.4);
      await player.setLoopMode(LoopMode.all);
      player.broken = true;
      player.errors.add(PlayerException(1, 'private failure', 2));
      switch (action) {
        case 'Play':
          await f.playback.play();
        case 'automatic retry':
          await tester.pump(const Duration(seconds: 2));
        case 'another song':
          await f.playback.playAlbum(f.client, continuityTracks, 1);
      }
      await tester.pumpAndSettle();
      expect(player.stops, 1);
      expect(sourceResets, 1);
      expect(brokenAtSourceReset, [
        false,
      ], reason: 'Stop the native player before replacing its stream session.');
      expect(player.playing, true);
      expect(f.playback.error.value, isNull);
      expect(player.volume, .4);
      final anotherSong = action == 'another song';
      expect(player.speed, anotherSong ? 1 : .75);
      expect(player.pitchAtLoad.last, anotherSong);
      expect(player.preservesPitch, anotherSong);
      if (action != 'another song') {
        expect(player.currentIndex, 2);
        expect(player.position, const Duration(seconds: 62));
        expect(player.loopMode, LoopMode.all);
        expect(player.shuffleIndices, [1, 2, 0]);
      }
      await f.close(tester);
    });
  }
  testWidgets('Pause during a playback reset prevents unwanted autoplay', (
    tester,
  ) async {
    final resetting = Completer<void>();
    final f = _Recovery(resetSourcePlayback: () => resetting.future);
    await f.failPlay();
    final retry = f.playback.play();
    await tester.pump();
    await f.playback.pause();
    resetting.complete();
    await retry;
    await tester.pump();
    expect(f.player.playing, false);
    expect(f.player.currentIndex, 2);
    expect(f.player.position, const Duration(seconds: 47));
    await f.close(tester);
  });
  testWidgets(
    'Play can recover a load that failed before publishing a media item',
    (tester) async {
      final f = _Recovery();
      f.player.failNextPause = true;
      await f.playback.playAlbum(f.client, continuityTracks, 1);
      expect(f.playback.mediaItem.value, isNull);
      expect(f.playback.canRetryPlayback, isTrue);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlayerControls(playback: f.playback, client: f.client),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Play'));
      await tester.pumpAndSettle();
      expect(f.player.playing, isTrue);
      expect(f.player.currentIndex, 1);
      expect(f.playback.error.value, isNull);
      await f.close(tester);
    },
  );

  testWidgets('the visible Play button retries an errored restored queue', (
    tester,
  ) async {
    final f = _Recovery();
    await f.failPlay();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlayerControls(playback: f.playback, client: f.client),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Press Play to retry'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (w) => w is IconButton && w.tooltip == 'Play',
            ),
          )
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.byTooltip('Play'));
    await tester.pumpAndSettle();
    expect(f.playback.error.value, isNull);
    expect(f.player.playing, isTrue);
    expect(f.player.currentIndex, 2);
    expect(f.player.position, const Duration(seconds: 47));
    expect(f.player.shuffleIndices, [1, 2, 0]);
    // Stop retrying is available without clearing the queue.
    f.player.errors.add(PlayerException(1, 'private-url', 2));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stop retrying'));
    await tester.pumpAndSettle();
    expect(f.playback.reconnecting, isFalse);
    expect(f.player.playing, isFalse);
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (w) => w is IconButton && w.tooltip == 'Play',
            ),
          )
          .onPressed,
      isNotNull,
    );
    await f.close(tester);
  });

  testWidgets(
    'connection probes back off and resume the same song when reachable',
    (tester) async {
      final f = _Recovery();
      f.client.pingError = const NavidromeException('Unavailable');
      await f.failPlay();
      await tester.pump(const Duration(seconds: 2));
      expect(f.client.pings, 1);
      expect(
        f.player.loaded,
        hasLength(2),
        reason: 'An offline server must not trigger another whole-queue load.',
      );
      await tester.pump(const Duration(seconds: 4));
      expect(f.client.pings, 1);
      f.client.pingError = null;
      await tester.pump(const Duration(seconds: 1));
      expect(f.client.pings, 2);
      expect(f.player.playCalls, 1);
      expect(f.player.currentIndex, 2);
      expect(f.player.position, const Duration(seconds: 47));
      expect(f.player.shuffleIndices, [1, 2, 0]);
      expect(f.playback.error.value, isNull);
      expect(f.playback.reconnecting, isFalse);
      await f.close(tester);
    },
  );

  for (final action in [
    'pause',
    'clear',
    'new queue',
    'switch account',
    'retry now',
  ]) {
    testWidgets('$action wins over an in-flight recovery probe', (
      tester,
    ) async {
      final f = _Recovery();
      final gate = Completer<void>();
      f.client.pingGate = gate;
      await f.failPlay();
      await tester.pump(const Duration(seconds: 2));
      expect(f.client.pings, 1);
      switch (action) {
        case 'pause':
          await f.playback.pause();
        case 'clear':
          await f.playback.reset();
        case 'switch account':
          await f.playback.suspendForAccountSwitch();
        case 'new queue':
          await f.playback.playAlbum(f.client, [continuityTracks[1]], 0);
        case 'retry now':
          await f.playback.play();
      }
      final loads = f.player.loaded.length;
      gate.complete();
      await tester.pump(const Duration(seconds: 40));
      expect(f.player.loaded, hasLength(loads));
      expect(f.playback.reconnecting, isFalse);
      expect(f.player.playing, action == 'new queue' || action == 'retry now');
      if (action == 'new queue') {
        expect(f.playback.queue.value.single.id, 'two');
      }
      await f.close(tester);
    });
  }

  testWidgets('disposal ignores a late successful recovery probe', (
    tester,
  ) async {
    final f = _Recovery();
    final gate = Completer<void>();
    f.client.pingGate = gate;
    await f.failPlay();
    await tester.pump(const Duration(seconds: 2));
    await f.close(tester);
    gate.complete();
    await tester.pump();
    expect(f.player.playCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'healthy server with a broken stream stops automatic reloads but allows Play',
    (tester) async {
      final f = _Recovery();
      await f.failPlay();
      for (final seconds in [2, 5]) {
        f.player.failNextLoad = true;
        await tester.pump(Duration(seconds: seconds));
      }
      await tester.pump(const Duration(seconds: 10));
      expect(f.player.loaded, hasLength(4));
      expect(f.playback.error.value, contains('server is reachable'));
      expect(f.playback.reconnecting, isFalse);
      await tester.pump(const Duration(minutes: 2));
      expect(f.client.pings, 3);
      await f.playback.play();
      expect(f.player.currentIndex, 2);
      expect(f.player.position, const Duration(seconds: 47));
      expect(f.player.playing, isTrue);
      await f.close(tester);
    },
  );

  testWidgets(
    'authentication rejection stops retries without discarding the queue',
    (tester) async {
      final f = _Recovery();
      f.client.pingError = const NavidromeException(
        'private response',
        authenticationRejected: true,
      );
      await f.failPlay();
      await tester.pump(const Duration(seconds: 2));
      expect(f.playback.error.value, contains('sign-in was rejected'));
      expect(f.playback.error.value, isNot(contains('private response')));
      expect(f.playback.queue.value, hasLength(3));
      await tester.pump(const Duration(minutes: 2));
      expect(f.client.pings, 1);
      await f.close(tester);
    },
  );

  testWidgets('foreground recovery retains a runtime interruption position', (
    tester,
  ) async {
    final f = _Recovery();
    await f.playback.attachAccount(f.client, remember: true);
    await f.playback.play();
    f.player.position = const Duration(seconds: 62);
    f.player.errors.add(PlayerException(1, 'private-url', 2));
    f.playback.retryConnectionNow();
    await tester.pump();
    expect(f.client.pings, 1);
    expect(f.player.playCalls, 2);
    expect(f.player.currentIndex, 2);
    expect(f.player.position, const Duration(seconds: 62));
    await f.close(tester);
  });
}

class _SpeedGatedPlayer extends FakePlayer {
  final speedChangeGate = Completer<void>();
  bool speedChangeStarted = false;

  @override
  Future<void> setSpeed(double value) async {
    if (!speedChangeStarted && value == .75) {
      speedChangeStarted = true;
      await speedChangeGate.future;
    }
    await super.setSpeed(value);
  }
}

class _StickyPlayer extends FakePlayer {
  bool broken = false;
  int stops = 0;
  @override
  Future<Duration?> setAudioSources(
    List<AudioSource> audioSources, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
    ShuffleOrder? shuffleOrder,
  }) {
    if (broken) {
      throw PlayerException(1, 'Native player needs recreation', initialIndex);
    }
    return super.setAudioSources(
      audioSources,
      preload: preload,
      initialIndex: initialIndex,
      initialPosition: initialPosition,
      shuffleOrder: shuffleOrder,
    );
  }

  @override
  Future<void> stop() async {
    stops++;
    broken = false;
    await super.stop();
  }
}
