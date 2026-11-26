import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperstream_client/features/player/player_controls.dart';
import 'package:hyperstream_client/models/library.dart';
import 'package:hyperstream_client/models/source_reference.dart';
import 'package:hyperstream_client/services/navidrome_client.dart';
import 'package:hyperstream_client/services/playback_service.dart';
import 'package:hyperstream_client/widgets/music_source_icon.dart';

import 'support/fake_player.dart';

void main() {
  testWidgets(
    'compact now playing shows resolved source and playback quality',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const external = Track(
        id: 'external-song',
        title: 'Catalog song',
        artist: 'Artist',
        album: 'Album',
        duration: Duration(minutes: 3),
        source: SourceReference(sourceId: 'mornye:spotify-web', trackId: 'one'),
      );
      const library = Track(
        id: 'library-song',
        title: 'Library song',
        artist: 'Artist',
        album: 'Album',
        duration: Duration(minutes: 3),
        container: 'mp3',
        bitRate: 320,
      );
      final sourceInfo = ValueNotifier<Map<String, SourcePlaybackInfo>>({});
      final playback = PlaybackService(
        player: FakePlayer(),
        configureSession: (_) async {},
        artworkLoader: (_, _) async => null,
        sourceStreamUri: (_) => Uri.parse('http://127.0.0.1/synthetic'),
        sourcePlaybackInfo: sourceInfo,
      );
      final client = NavidromeClient(
        serverUrl: 'https://example.test',
        username: 'test',
        password: 'test',
      );
      addTearDown(() async {
        final disposing = playback.dispose();
        await tester.pump();
        await disposing;
        sourceInfo.dispose();
        client.close();
      });
      await playback.playAlbum(client, const [external, library], 0);
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
      await tester.tap(find.text(external.title));
      await tester.pumpAndSettle();
      final nowPlaying = find.byWidgetPredicate(
        (widget) =>
            widget is Semantics && widget.properties.label == 'Music player',
      );
      Finder badge(String id) => find.descendant(
        of: nowPlaying,
        matching: find.byWidgetPredicate(
          (widget) => widget is MusicSourceIcon && widget.sourceId == id,
        ),
      );
      expect(badge('mornye:spotify-web'), findsOneWidget);
      expect(find.textContaining('kbps'), findsNothing);

      sourceInfo.value = {
        external.source!.identity: const SourcePlaybackInfo(
          sourceId: 'mornye:qobuz-web',
          format: 'm4a',
          codec: 'aac',
          bitRate: 132,
          bitRateEstimated: true,
        ),
      };
      await tester.pumpAndSettle();
      expect(badge('mornye:spotify-web'), findsNothing);
      final qobuz = badge('mornye:qobuz-web');
      expect(qobuz, findsOneWidget);
      final emblem = tester.widget<Text>(
        find.descendant(of: qobuz, matching: find.text('Q')),
      );
      expect(emblem.style?.color, const Color(0xFF2165BA));
      expect(find.text('Qobuz · M4A · AAC · ≈132 kbps'), findsOneWidget);
      expect(
        find.byTooltip(
          'Qobuz · M4A · AAC · ≈132 kbps\n'
          'Approximate file bitrate, including container overhead.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      await playback.skipToQueueItem(1);
      await tester.pumpAndSettle();
      expect(qobuz, findsNothing);
      final navidrome = badge('navidrome');
      expect(navidrome, findsOneWidget);
      expect(
        find.descendant(
          of: navidrome,
          matching: find.byIcon(Icons.library_music_rounded),
        ),
        findsOneWidget,
      );
      expect(find.text('Navidrome · MP3 · 320 kbps'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await playback.pause();
    },
  );
}
