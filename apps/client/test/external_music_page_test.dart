import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hyperstream_client/app_theme.dart';
import 'package:hyperstream_client/features/search/external_music_page.dart';
import 'package:hyperstream_client/services/music_sources.dart';
import 'package:hyperstream_client/services/navidrome_client.dart';
import 'package:hyperstream_client/services/playback_service.dart';

import 'support/fake_player.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'external search, album and shared playback at large text in $brightness',
      (tester) async {
        tester.view.physicalSize = const Size(393, 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final calls = <String>[];
        final song = {
          'id': 'song',
          'title': 'Outside song',
          'artistNames': ['Outside artist'],
          'duration': 180000,
          'releaseId': 'album',
          'trackNumber': 1,
        };
        final album = {
          'id': 'album',
          'title': 'Outside album',
          'artistNames': ['Outside artist'],
          'trackCount': 1,
          'tracks': [song],
        };
        final sources = MusicSources(
          httpClient: () => MockClient((request) async {
            calls.add(request.url.path);
            return http.Response(
              jsonEncode(
                request.url.path.endsWith('search')
                    ? {
                        'tracks': [song],
                        'releases': [album],
                      }
                    : album,
              ),
              200,
            );
          }),
        )..enabled = true;
        final client = NavidromeClient(
          serverUrl: 'https://library.example',
          username: 'user',
          password: 'synthetic',
        );
        final player = FakePlayer();
        final playback = PlaybackService(
          player: player,
          configureSession: (_) async {},
          sourceStreamUri: sources.streamUri,
        );
        addTearDown(() async {
          final disposing = playback.dispose();
          await tester.pump();
          await disposing;
          client.close();
          sources.dispose();
        });
        await tester.pumpWidget(
          MaterialApp(
            theme: hyperstreamTheme(brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.6)),
              child: child!,
            ),
            home: ExternalMusicPage(
              client: client,
              playback: playback,
              sources: sources,
            ),
          ),
        );
        await tester.enterText(find.byType(TextField), 'Outside');
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();
        expect(find.text('Outside song'), findsOneWidget);
        expect(
          find.byTooltip('Download song to remote folder'),
          findsOneWidget,
        );
        await tester.tap(find.text('Outside album'));
        await tester.pumpAndSettle();
        expect(calls, ['/search', '/releases/album']);
        expect(
          find.byTooltip('Download album to remote folder'),
          findsNothing,
        ); // One-track album uses the song label.
        await tester.tap(find.widgetWithText(FilledButton, 'Play'));
        await tester.pumpAndSettle();
        expect(playback.queue.value.single.id, contains('external:'));
        expect(player.playing, true);
        expect(tester.takeException(), isNull);
        await playback.pause();
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
