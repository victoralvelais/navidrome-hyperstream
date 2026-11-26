import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperstream_client/app_theme.dart';
import 'package:hyperstream_client/features/player/playback_settings_group.dart';
import 'package:hyperstream_client/features/player/player_controls.dart';
import 'package:hyperstream_client/features/player/tempo_button.dart';
import 'package:hyperstream_client/models/library.dart';
import 'package:hyperstream_client/services/navidrome_client.dart';
import 'package:hyperstream_client/services/playback_service.dart';
import 'package:hyperstream_client/services/song_playback_store.dart';
import 'package:hyperstream_client/widgets/glass_overlays.dart';

import 'support/fake_player.dart';

class _SpeedPlayer extends FakePlayer {
  bool failSpeed = false;
  @override
  Future<void> setSpeed(double value) async {
    if (failSpeed) throw StateError('private native error');
    await super.setSpeed(value);
  }
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'tempo presets and fine controls share the output group in $brightness',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform_views,
          (_) async => null,
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform_views,
            null,
          ),
        );
        final player = _SpeedPlayer()..supportsPitchControl = true;
        final saves = <String>[];
        final playback = PlaybackService(
          player: player,
          songPlaybackStore: SongPlaybackStore(
            save: (json) async => saves.add(json),
          ),
          configureSession: (_) async {},
        );
        final client = NavidromeClient(
          serverUrl: 'https://music.example.com',
          username: 'test',
          password: 'test',
        );
        addTearDown(() async {
          client.close();
          final disposing = playback.dispose();
          await tester.pump();
          await disposing;
        });
        await playback.playAlbum(client, const [
          Track(
            id: 'one',
            title: 'Coastline',
            artist: 'Northline',
            album: 'Album',
            duration: Duration(minutes: 3),
          ),
        ], 0);
        await playback.pause();
        player.position = const Duration(seconds: 45);
        final calls = player.playCalls;
        await tester.pumpWidget(
          MaterialApp(
            theme: hyperstreamTheme(brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.4)),
              child: child!,
            ),
            home: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: PlayerControls(playback: playback, client: client),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Coastline'));
        await tester.pumpAndSettle();
        final group = find.byType(PlaybackSettingsGroup);
        await tester.ensureVisible(group);
        await tester.pumpAndSettle();
        expect(
          find.descendant(of: group, matching: find.byTooltip('Music volume')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: group, matching: find.byType(UiKitView)),
          findsOneWidget,
        );
        await tester.tap(find.byTooltip('Playback tempo'));
        await tester.pumpAndSettle();
        expect(find.byType(UiKitView), findsNothing);
        expect(find.byType(ChoiceChip), findsNWidgets(6));
        expect(find.text('Saved for this song'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.widgetWithText(ChoiceChip, '0.75×'));
        await tester.pumpAndSettle();
        expect(player.speed, .75);
        await tester.tap(find.byTooltip('Increase tempo by 0.01'));
        await tester.tap(find.byTooltip('Increase tempo by 0.01'));
        await tester.pumpAndSettle();
        expect(player.speed, .77);
        expect(player.position, const Duration(seconds: 45));
        expect(player.playCalls, calls);
        expect(player.playing, isFalse);
        final errorMessage = find.descendant(
          of: find.byType(GlassMenuContent<void>),
          matching: find.text(
            "Could not change this song's audio settings. Try again.",
          ),
        );
        final pitch = find.byKey(const ValueKey('keep-pitch-toggle'));
        expect(find.text('Original pitch at every speed'), findsOneWidget);
        await tester.tap(pitch);
        await tester.pumpAndSettle();
        expect(find.text('Pitch changes with speed'), findsOneWidget);
        expect(player.preservesPitch, isFalse);
        expect(playback.songPlaybackSettings.value.keepPitch, isFalse);
        final savesBeforeFailure = saves.length;
        expect(savesBeforeFailure, greaterThan(0));
        player.failPitch = true;
        await tester.tap(pitch);
        await tester.pumpAndSettle();
        expect(find.text('Pitch changes with speed'), findsOneWidget);
        expect(player.preservesPitch, isFalse);
        expect(playback.songPlaybackSettings.value.keepPitch, isFalse);
        expect(saves, hasLength(savesBeforeFailure));
        expect(find.textContaining('private native pitch error'), findsNothing);
        await tester.ensureVisible(errorMessage);
        await tester.pumpAndSettle();
        expect(errorMessage.hitTestable(), findsOneWidget);
        player.failPitch = false;
        await tester.ensureVisible(pitch);
        await tester.tap(pitch);
        await tester.pumpAndSettle();
        expect(find.text('Original pitch at every speed'), findsOneWidget);
        expect(playback.songPlaybackSettings.value.keepPitch, isTrue);
        expect(player.preservesPitch, isTrue);
        expect(player.speed, .77);
        expect(player.position, const Duration(seconds: 45));
        expect(player.playCalls, calls);
        expect(player.playing, isFalse);
        player.failSpeed = true;
        final faster = find.widgetWithText(ChoiceChip, '1.50×');
        await tester.ensureVisible(faster);
        await tester.tap(faster);
        await tester.pumpAndSettle();
        expect(player.speed, .77);
        await tester.ensureVisible(errorMessage);
        await tester.pumpAndSettle();
        expect(errorMessage.hitTestable(), findsOneWidget);
        expect(find.textContaining('private native error'), findsNothing);
        player.failSpeed = false;
        final reset = find.text('Reset 1×');
        await tester.ensureVisible(reset);
        await tester.tap(reset);
        await tester.pumpAndSettle();
        expect(player.speed, 1);
        await tester.tapAt(const Offset(2, 2));
        await tester.pumpAndSettle();
        expect(find.byType(ChoiceChip), findsNothing);
        expect(
          find.descendant(of: group, matching: find.byType(UiKitView)),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
      variant: TargetPlatformVariant({TargetPlatform.iOS}),
    );
  }

  testWidgets('Windows explains why the pitch switch is disabled', (
    tester,
  ) async {
    final player = FakePlayer();
    final playback = PlaybackService(
      player: player,
      configureSession: (_) async {},
    );
    final client = NavidromeClient(
      serverUrl: 'https://music.example.com',
      username: 'test',
      password: 'test',
    );
    addTearDown(client.close);
    await playback.playAlbum(client, const [
      Track(
        id: 'one',
        title: 'Coastline',
        artist: 'Northline',
        album: 'Album',
        duration: Duration(minutes: 3),
      ),
    ], 0);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TempoButton(playback: playback)),
      ),
    );
    await tester.tap(find.byTooltip('Playback tempo'));
    await tester.pumpAndSettle();
    expect(
      find.text('Pitch control is not available on Windows yet'),
      findsOneWidget,
    );
    final pitchSwitch = tester.widget<SwitchListTile>(
      find.byKey(const ValueKey('keep-pitch-toggle')),
    );
    expect(pitchSwitch.onChanged, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    var closed = false;
    final closing = playback.dispose().whenComplete(() => closed = true);
    for (var i = 0; i < 20 && !closed; i++) {
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }
    expect(closed, isTrue);
    await closing;
  }, variant: TargetPlatformVariant({TargetPlatform.windows}));
}
