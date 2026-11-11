import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hyperstream_client/app_theme.dart';
import 'package:hyperstream_client/features/library/library_screen.dart';
import 'package:hyperstream_client/models/library.dart';
import 'package:hyperstream_client/services/navidrome_client.dart';
import 'package:hyperstream_client/services/playback_service.dart';

import 'support/fake_player.dart';

Future<void> main() async {
  // Optional local font for readable preview images; CI needs no external files.
  const previewFont = String.fromEnvironment('PREVIEW_FONT');
  if (previewFont.isNotEmpty) {
    TestWidgetsFlutterBinding.ensureInitialized();
    final font = FontLoader('Roboto')
      ..addFont(File(previewFont).readAsBytes().then(ByteData.sublistView));
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  }
  for (final viewport in [
    (
      name: 'phone-dark',
      size: const Size(393, 852),
      theme: ThemeMode.dark,
      scale: 1.0,
    ),
    (
      name: 'small-phone-light',
      size: const Size(320, 640),
      theme: ThemeMode.light,
      scale: 1.4,
    ),
    (
      name: 'desktop-dark',
      size: const Size(1280, 800),
      theme: ThemeMode.dark,
      scale: 1.0,
    ),
  ]) {
    testWidgets('library, player, and settings work at ${viewport.name}', (
      tester,
    ) async {
      tester.view.physicalSize = viewport.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final player = FakePlayer();
      final playback = PlaybackService(player: player);
      final client = NavidromeClient(
        serverUrl: 'https://music.example.com',
        username: 'test',
        password: 'test',
        httpClient: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'subsonic-response': {
                'status': 'ok',
                if (request.url.path.endsWith('getAlbumList2.view'))
                  'albumList2': {
                    'album': [
                      {
                        'id': 'one',
                        'name': 'After Hours',
                        'artist': 'The Night Ensemble',
                      },
                      {
                        'id': 'two',
                        'name': 'Soft Focus',
                        'artist': 'Still Life',
                      },
                      {
                        'id': 'three',
                        'name': 'Blue Room',
                        'artist': 'Sunday Sessions',
                      },
                      {
                        'id': 'four',
                        'name': 'Out of the City',
                        'artist': 'New Horizons',
                      },
                    ],
                  },
                if (request.url.path.endsWith('getAlbum.view'))
                  'album': {
                    'song': [
                      {
                        'id': 'track',
                        'title': 'A quiet place to start again',
                        'artist': 'The Night Ensemble',
                        'duration': 180,
                      },
                    ],
                  },
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
      addTearDown(() async {
        final disposing = playback.dispose();
        // Futures created inside testWidgets need its simulated loop drained.
        await tester.pump();
        await disposing;
        client.close();
      });
      await playback.preferences.setThemeMode(viewport.theme);
      await playback.playAlbum(client, const [
        Track(
          id: 'track',
          title: 'A quiet place to start again',
          artist: 'The Night Ensemble',
          album: 'After Hours',
          duration: Duration(minutes: 3),
        ),
      ], 0);
      await tester.pumpWidget(
        ListenableBuilder(
          listenable: playback.preferences,
          builder: (context, _) => MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: hyperstreamTheme(Brightness.light),
            darkTheme: hyperstreamTheme(Brightness.dark),
            themeMode: playback.preferences.themeMode,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(viewport.scale)),
              child: child!,
            ),
            home: LibraryScreen(
              client: client,
              playback: playback,
              onDisconnect: () async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Library'), findsOneWidget);
      expect(tester.takeException(), isNull);
      // Optional visual review artifacts, excluded from normal CI/golden checks.
      if (const bool.fromEnvironment('CAPTURE_PREVIEWS')) {
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('../build/previews/${viewport.name}.png'),
        );
      }

      await tester.tap(find.byTooltip('Show music volume'));
      await tester.pumpAndSettle();
      final volumeSlider = tester.widget<Slider>(find.byType(Slider));
      volumeSlider.onChanged!(.27);
      await tester.pumpAndSettle();
      expect(player.volume, .27);
      await tester.tap(find.byTooltip('Mute music'));
      await tester.pumpAndSettle();
      expect(player.volume, 0);
      await tester.tap(find.byTooltip('Unmute music'));
      await tester.pumpAndSettle();
      expect(player.volume, .27);

      await tester.tap(find.byTooltip('Hide music volume'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('A quiet place to start again'));
      await tester.pumpAndSettle();
      expect(find.text('Now playing'), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('CAPTURE_PREVIEWS')) {
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('../build/previews/${viewport.name}-player.png'),
        );
      }
      // A drag previews position; only releasing it asks the native player to seek.
      final seekSlider = tester.widget<Slider>(find.byType(Slider).first);
      seekSlider.onChanged!(45000);
      await tester.pump();
      expect(player.seekCalls, 0);
      seekSlider.onChangeEnd!(45000);
      await tester.pumpAndSettle();
      expect(player.seekCalls, 1);
      expect(player.position, const Duration(seconds: 45));
      await tester.tap(find.byTooltip('Close player'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('After Hours'));
      await tester.pumpAndSettle();
      expect(find.text('Play album'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Appearance'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byType(DropdownButtonFormField<ThemeMode>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Follow system').last);
      await tester.pumpAndSettle();
      expect(playback.preferences.themeMode, ThemeMode.system);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
