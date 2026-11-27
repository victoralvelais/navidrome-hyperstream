import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperstream_client/features/player/e3/aurora_background.dart';
import 'package:hyperstream_client/features/player/e3/controls.dart';
import 'package:hyperstream_client/features/player/player_controls.dart';
import 'package:hyperstream_client/models/library.dart';
import 'package:hyperstream_client/services/app_preferences.dart';
import 'package:hyperstream_client/services/navidrome_client.dart';
import 'package:hyperstream_client/services/playback_service.dart';
import 'package:just_audio/just_audio.dart';

import 'support/fake_player.dart';

const _tracks = [
  Track(
    id: 'first-song',
    title: 'A long track title for a compact display',
    artist: 'The Test Quartet',
    album: 'Songs in the queue',
    duration: Duration(minutes: 3),
  ),
  Track(
    id: 'second-song',
    title: 'The next song',
    artist: 'The Test Quartet',
    album: 'Songs in the queue',
    duration: Duration(minutes: 3),
  ),
];

final _playerRoute = find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.label == 'Music player',
);

Finder _inside(Finder matching) =>
    find.descendant(of: _playerRoute, matching: matching);

Future<void> _transition(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

Future<FakePlayer> _openPlayer(
  WidgetTester tester, {
  required Size size,
  double scale = 1,
  ValueNotifier<bool>? reducedMotion,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final player = FakePlayer()..supportsPitchControl = true;
  final motion = reducedMotion ?? ValueNotifier(true);
  final playback = PlaybackService(
    player: player,
    preferences: AppPreferences()..reportListens = false,
    configureSession: (_) async {},
    artworkLoader: (_, _) async => null,
  );
  final client = NavidromeClient(
    serverUrl: 'https://example.test',
    username: 'test',
    password: 'test',
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    motion.dispose();
    final disposing = playback.dispose();
    await tester.pump();
    await disposing;
    client.close();
  });
  await playback.playAlbum(client, _tracks, 0);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => ValueListenableBuilder(
        valueListenable: motion,
        builder: (context, reduceMotion, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: reduceMotion,
            padding: const EdgeInsets.only(bottom: 24),
            viewPadding: const EdgeInsets.only(bottom: 24),
          ),
          child: child!,
        ),
        child: child,
      ),
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: PlayerControls(playback: playback, client: client),
        ),
      ),
    ),
  );
  await tester.tap(find.text(_tracks.first.title));
  await _transition(tester);
  expect(_playerRoute, findsOneWidget);
  return player;
}

void main() {
  for (final (size, scale) in [
    (const Size(320, 568), 1.0),
    (const Size(390, 844), 1.0),
    (const Size(1024, 700), 1.0),
    (const Size(320, 568), 2.0),
  ]) {
    testWidgets('now playing fits ${size.width} × ${size.height} at $scale×', (
      tester,
    ) async {
      await _openPlayer(tester, size: size, scale: scale);
      expect(_inside(find.text(_tracks.first.title)), findsOneWidget);
      final pause = _inside(find.byTooltip('Pause'));
      await tester.ensureVisible(pause);
      await _transition(tester);
      expect(pause.hitTestable(), findsOneWidget);
      expect(
        tester.widget<AuroraBackground>(find.byType(AuroraBackground)).running,
        isFalse,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('playback controls reach the player and pause album motion', (
    tester,
  ) async {
    final motion = ValueNotifier(false);
    final player = await _openPlayer(
      tester,
      size: const Size(390, 844),
      reducedMotion: motion,
    );

    Future<void> press(String tooltip) async {
      final button = _inside(find.byTooltip(tooltip));
      await tester.ensureVisible(button);
      await _transition(tester);
      await tester.tap(button);
      await _transition(tester);
    }

    PulsePlayButton playButton() => tester.widget(find.byType(PulsePlayButton));
    expect(playButton().running, isTrue);
    motion.value = true;
    await tester.pump();
    expect(playButton().running, isFalse);
    expect(player.playing, isTrue);
    motion.value = false;
    await tester.pump();
    expect(playButton().running, isTrue);
    await press('Pause');
    expect(player.playing, isFalse);
    expect(playButton().running, isFalse);
    await press('Play');
    expect(player.playing, isTrue);
    await press('Next track');
    expect(player.currentIndex, 1);
    expect(_inside(find.text(_tracks.last.title)), findsOneWidget);
    await press('Previous track');
    expect(player.currentIndex, 0);
    await press('Mute music');
    expect(player.volume, 0);
    await press('Unmute music');
    expect(player.volume, 1);
    await press('Shuffle queue');
    expect(player.shuffleModeEnabled, isTrue);
    await press('Turn shuffle off');
    expect(player.shuffleModeEnabled, isFalse);
    await press('Repeat off');
    expect(player.loopMode, LoopMode.all);
    await press('Repeat all');
    expect(player.loopMode, LoopMode.one);
    await press('Repeat one');
    expect(player.loopMode, LoopMode.off);
    expect(tester.takeException(), isNull);
  });

  testWidgets('More edits settings for only the current song', (tester) async {
    final player = await _openPlayer(tester, size: const Size(390, 844));
    expect(_inside(find.byTooltip('Choose audio output')), findsOneWidget);
    final more = _inside(find.byTooltip('More playback options'));
    await tester.ensureVisible(more);
    await tester.tap(more);
    await _transition(tester);

    final pitch = find.byKey(const ValueKey('keep-pitch-toggle'));
    final tempo = find.widgetWithText(ChoiceChip, '1.25×');
    await tester.ensureVisible(tempo);
    await tester.tap(tempo);
    await _transition(tester);
    expect(player.speed, 1.25);
    await tester.ensureVisible(pitch);
    await tester.tap(pitch);
    await _transition(tester);
    expect(player.preservesPitch, isFalse);
    for (final label in [
      'Sleep timer',
      'Save to remote folder',
      'Share snapshot',
      'Playback details',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    final sleep = find.text('Sleep timer');
    await tester.ensureVisible(sleep);
    await tester.tap(sleep);
    await _transition(tester);
    await tester.tap(find.text('End of current track'));
    await _transition(tester);
    expect(find.text('Sleep at the end of this track'), findsOneWidget);

    final close = find.byTooltip('Close more');
    await tester.ensureVisible(close);
    await tester.tap(close);
    await _transition(tester);
    await tester.tap(_inside(find.byTooltip('Next track')));
    await _transition(tester);
    expect(player.speed, 1);
    expect(player.preservesPitch, isTrue);
    await tester.tap(_inside(find.byTooltip('Previous track')));
    await _transition(tester);
    expect(player.speed, 1.25);
    expect(player.preservesPitch, isFalse);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant({TargetPlatform.windows}));
}
