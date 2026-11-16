import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperstream_client/app_theme.dart';
import 'package:hyperstream_client/features/player/playback_settings_group.dart';
import 'package:hyperstream_client/features/player/player_controls.dart';
import 'package:hyperstream_client/models/library.dart';
import 'package:hyperstream_client/services/navidrome_client.dart';
import 'package:hyperstream_client/services/playback_service.dart';

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
        final player = _SpeedPlayer();
        final playback = PlaybackService(
          player: player,
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
        player.failSpeed = true;
        await tester.tap(find.widgetWithText(ChoiceChip, '1.50×'));
        await tester.pumpAndSettle();
        expect(player.speed, .77);
        expect(
          find
              .text('Could not change the audio setting. Try again.')
              .hitTestable(),
          findsOneWidget,
        );
        expect(find.textContaining('private native error'), findsNothing);
        player.failSpeed = false;
        await tester.tap(find.text('Reset 1×'));
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
}
