import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperstream_client/app_theme.dart';
import 'package:hyperstream_client/features/player/volume_button.dart';
import 'package:hyperstream_client/services/playback_service.dart';

import 'support/fake_player.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'speaker drag, tap, keyboard, mute and dismissal control app volume in $brightness',
      (tester) async {
        final player = FakePlayer();
        final playback = PlaybackService(player: player);
        addTearDown(() async {
          final disposing = playback.dispose();
          await tester.pump();
          await disposing;
        });
        final setting = playback.setAppVolume(.4);
        await tester.pump();
        await setting;
        await tester.pumpWidget(
          MaterialApp(
            theme: hyperstreamTheme(brightness),
            home: Scaffold(
              body: Align(
                alignment: Alignment.bottomRight,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: VolumeButton(playback: playback),
                ),
              ),
            ),
          ),
        );
        final speaker = find.byTooltip('Music volume');
        final gesture = await tester.startGesture(tester.getCenter(speaker));
        await gesture.moveBy(const Offset(0, -24));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('vertical-volume-track')),
          findsOneWidget,
        );
        final initial = player.volume;
        await gesture.moveBy(const Offset(0, -50));
        await tester.pumpAndSettle();
        expect(player.volume, greaterThan(initial));
        expect(player.volume, lessThan(1));
        await gesture.up();
        await tester.pumpAndSettle();
        final afterDrag = player.volume;
        expect(
          Theme.of(
            tester.element(find.byKey(const ValueKey('vertical-volume-track'))),
          ).brightness,
          Brightness.dark,
        );
        final fill = tester.widget<ColoredBox>(
          find.descendant(
            of: find.byKey(const ValueKey('vertical-volume-track')),
            matching: find.byType(ColoredBox),
          ),
        );
        expect(fill.color.computeLuminance(), greaterThan(.8));
        expect(
          tester
              .widget<IconButton>(
                find.byWidgetPredicate(
                  (widget) =>
                      widget is IconButton && widget.tooltip == 'Mute music',
                ),
              )
              .color!
              .computeLuminance(),
          lessThan(.05),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(player.volume, closeTo(afterDrag - .05, .001));
        final beforeMute = player.volume;
        await tester.tap(find.byTooltip('Mute music'));
        await tester.pumpAndSettle();
        expect(player.volume, 0);
        await tester.tap(find.byTooltip('Unmute music'));
        await tester.pumpAndSettle();
        expect(player.volume, beforeMute);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('vertical-volume-track')),
          findsNothing,
        );
        await tester.tap(speaker);
        await tester.pumpAndSettle();
        expect(player.volume, beforeMute);
        await tester.tapAt(const Offset(20, 20));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('vertical-volume-track')),
          findsNothing,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        expect(tester.takeException(), isNull);
      },
    );
  }
}
