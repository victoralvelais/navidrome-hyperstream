import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:hyperstream_client/app_theme.dart';
import 'package:hyperstream_client/features/playlists/recent_radio_screen.dart';
import 'package:hyperstream_client/services/navidrome_client.dart';
import 'package:hyperstream_client/services/playback_service.dart';
import 'package:hyperstream_client/services/recent_radio_service.dart';

import 'support/fake_player.dart';

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  const fontPath = String.fromEnvironment('PREVIEW_FONT');
  if (fontPath.isNotEmpty) {
    await (FontLoader(
      'Roboto',
    )..addFont(File(fontPath).readAsBytes().then(ByteData.sublistView))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  }
  for (final size in [
    const Size(320, 640),
    const Size(393, 852),
    const Size(1280, 800),
  ]) {
    testWidgets(
      'Recent Radio play, local updates, refresh and stale results at ${size.width}',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var fail = false;
        var reversed = false;
        var now = DateTime.utc(2026, 11, 11, 18);
        var scans = 0;
        final client = NavidromeClient(
          serverUrl: 'https://music.example.com',
          username: 'test',
          password: 'synthetic',
          httpClient: MockClient((request) async {
            if (request.url.queryParameters['songOffset'] == '0') scans++;
            if (fail) return http.Response('private', 500);
            final songs = request.url.queryParameters['songOffset'] == '0'
                ? [
                    {
                      'id': 'played',
                      'title': 'Older favorite',
                      'artist': 'The Night Ensemble',
                      'duration': 180,
                      'created': '2026-08-01T00:00:00Z',
                      'played': '2026-11-11T17:00:00Z',
                      'playCount': 1,
                    },
                    {
                      'id': 'added',
                      'title': 'New discovery',
                      'artist': 'Northline',
                      'duration': 180,
                      'created': reversed
                          ? '2026-11-11T18:00:00Z'
                          : '2026-11-10T12:00:00Z',
                    },
                  ]
                : [];
            return http.Response(
              jsonEncode({
                'subsonic-response': {
                  'status': 'ok',
                  'type': 'navidrome',
                  'openSubsonic': true,
                  'searchResult3': {'song': songs},
                },
              }),
              200,
            );
          }),
        );
        final radio = RecentRadioService(client, now: () => now);
        final playback = PlaybackService(player: FakePlayer());
        addTearDown(() async {
          final disposing = playback.dispose();
          await tester.pump();
          await disposing;
          client.close();
        });
        await tester.pumpWidget(
          MaterialApp(
            theme: hyperstreamTheme(Brightness.dark),
            home: Scaffold(
              body: MediaQuery(
                data: MediaQueryData(
                  size: size,
                  textScaler: TextScaler.linear(size.width == 320 ? 1.4 : 1),
                ),
                child: RecentRadioScreen(radio: radio, playback: playback),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('2 songs · 30 days'), findsOneWidget);
        expect(radio.preview!.matches.first.track.id, 'played');
        expect(scans, 1);
        if (const bool.fromEnvironment('CAPTURE_PREVIEWS')) {
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(
              '../build/previews/recent-radio-${size.width.toInt()}.png',
            ),
          );
        }
        await tester.ensureVisible(find.text('Play'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Play'));
        await tester.pumpAndSettle();
        expect(playback.queue.value.map((t) => t.id), ['played', 'added']);
        reversed = true;
        tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .jumpTo(0);
        await tester.pumpAndSettle();
        await tester.drag(find.byType(CustomScrollView), const Offset(0, 400));
        await tester.pumpAndSettle();
        expect(scans, 2);
        expect(radio.preview!.matches.first.track.id, 'added');
        expect(playback.queue.value.map((t) => t.id), ['played', 'added']);
        expect(find.byType(TextFormField), findsNothing);
        final played = radio.preview!.matches.last.track;
        now = now.add(const Duration(seconds: 1));
        client.recordLocalListen(played, now);
        await tester.pumpAndSettle();
        expect(radio.preview!.matches.map((m) => m.track.id), [
          'played',
          'added',
        ]);
        expect(scans, 2);
        expect(playback.queue.value.map((t) => t.id), ['played', 'added']);
        fail = true;
        final preview = radio.preview;
        final failed = radio.refresh();
        await tester.pumpAndSettle();
        await failed;
        expect(identical(radio.preview, preview), isTrue);
        expect(
          find.text(
            'Showing the last synced library with local listening updates.',
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await playback.pause();
        await tester.pumpWidget(const SizedBox.shrink());
        radio.dispose();
      },
    );
  }
}
