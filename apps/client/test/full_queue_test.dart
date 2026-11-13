import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperstream_client/features/player/player_controls.dart';
import 'package:hyperstream_client/models/library.dart';
import 'package:hyperstream_client/services/navidrome_client.dart';
import 'package:hyperstream_client/services/playback_service.dart';

import 'support/fake_player.dart';

void main() {
  testWidgets(
    'queue opens at current, scrolls earlier, then pulls closed at its beginning',
    (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final player = FakePlayer();
      final playback = PlaybackService(
        player: player,
        artworkLoader: (_, _) async => null,
      );
      final client = NavidromeClient(
        serverUrl: 'https://example.test',
        username: 'user',
        password: 'secret',
      );
      addTearDown(() async {
        final disposing = playback.dispose();
        await tester.pump();
        await disposing;
        client.close();
      });
      await playback.playAlbum(
        client,
        List.generate(
          12,
          (i) => Track(
            id: 'song-$i',
            title: 'Song $i',
            artist: 'Artist',
            album: 'Album',
            duration: const Duration(minutes: 3),
          ),
        ),
        6,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.iOS),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: PlayerControls(playback: playback, client: client),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Song 6'));
      await tester.pumpAndSettle();
      await Scrollable.ensureVisible(
        tester.element(find.byTooltip('Show queue')),
        alignment: .35,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Show queue'));
      await tester.pumpAndSettle();
      final list = find.byKey(const ValueKey('up-next-list'));
      final current = find
          .descendant(
            of: find.byKey(const ValueKey('queue-current')),
            matching: find.byType(Padding),
          )
          .first;
      final playerOverlay = find.byKey(const ValueKey('queue-player-overlay'));
      final scroll = tester
          .state<ScrollableState>(
            find.descendant(of: list, matching: find.byType(Scrollable)).first,
          )
          .position;
      expect(scroll.pixels, 0);
      expect(scroll.minScrollExtent, lessThan(-300));
      expect(
        tester.getTopLeft(current).dy,
        closeTo(tester.getTopLeft(list).dy, .1),
      );
      expect(
        tester.getTopLeft(find.text('Up next')).dy,
        greaterThan(tester.getTopLeft(current).dy),
      );
      expect(
        find.byKey(const ValueKey('earlier-queue-5')).hitTestable(),
        findsNothing,
      );
      final panelTop = tester.getTopLeft(playerOverlay).dy;
      final pull = await tester.startGesture(
        tester.getTopLeft(list) + const Offset(100, 90),
      );
      await pull.moveBy(const Offset(0, 20));
      await pull.moveBy(const Offset(0, 120));
      await tester.pump(const Duration(milliseconds: 400));
      expect(scroll.pixels, lessThan(0));
      expect(scroll.pixels, greaterThan(scroll.minScrollExtent));
      expect(
        tester.getTopLeft(playerOverlay).dy,
        closeTo(panelTop, .1),
        reason: 'Browsing earlier entries must not drag the sheet.',
      );
      await pull.up();
      await tester.pumpAndSettle();
      final previous = find.byKey(const ValueKey('earlier-queue-5'));
      expect(previous.hitTestable(), findsOneWidget);
      await tester.tap(previous);
      await tester.pumpAndSettle();
      expect(player.currentIndex, 5);
      expect(playback.earlierIndices, [0, 1, 2, 3, 4]);
      expect(playback.upcomingIndices.first, 6);
      scroll.jumpTo(scroll.minScrollExtent);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('earlier-queue-0')).hitTestable(),
        findsOneWidget,
      );
      final dismiss = await tester.startGesture(
        tester.getTopLeft(list) + const Offset(100, 90),
      );
      await dismiss.moveBy(const Offset(0, 20));
      await dismiss.moveBy(const Offset(0, 260));
      await tester.pump(const Duration(milliseconds: 400));
      await dismiss.up();
      await tester.pumpAndSettle();
      expect(list, findsNothing);
      expect(tester.takeException(), isNull);
      await playback.pause();
    },
  );
}
