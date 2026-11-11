import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:hyperstream_client/app_theme.dart';
import 'package:hyperstream_client/features/library/album_tracks.dart';
import 'package:hyperstream_client/features/library/library_screen.dart';
import 'package:hyperstream_client/features/favorites/favorites_screen.dart';
import 'package:hyperstream_client/features/playlists/playlist_tracks.dart';
import 'package:hyperstream_client/features/playlists/playlists_screen.dart';
import 'package:hyperstream_client/services/navidrome_client.dart';
import 'package:hyperstream_client/services/playback_service.dart';

import 'support/collection_server.dart';
import 'support/fake_player.dart';

Future<void> main() async {
  const previewFont = String.fromEnvironment('PREVIEW_FONT');
  if (previewFont.isNotEmpty) {
    TestWidgetsFlutterBinding.ensureInitialized();
    await (FontLoader('Roboto')
          ..addFont(File(previewFont).readAsBytes().then(ByteData.sublistView)))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  }
  for (final viewport in [
    (
      name: 'phone',
      size: const Size(393, 852),
      scale: 1.0,
      brightness: Brightness.dark,
    ),
    (
      name: 'small-phone',
      size: const Size(320, 640),
      scale: 1.4,
      brightness: Brightness.light,
    ),
    (
      name: 'desktop',
      size: const Size(1280, 800),
      scale: 1.0,
      brightness: Brightness.dark,
    ),
  ]) {
    testWidgets(
      'favorites, playlist editing, and hidden disconnect at ${viewport.name}',
      (tester) async {
        tester.view.physicalSize = viewport.size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        final server = CollectionServer();
        final player = FakePlayer();
        final playback = PlaybackService(player: player);
        final client = NavidromeClient(
          serverUrl: 'https://music.example.com',
          username: 'test',
          password: 'test',
          httpClient: MockClient(server.handle),
        );
        var disconnected = false;
        addTearDown(() async {
          final disposing = playback.dispose();
          await tester.pump();
          await disposing;
          client.close();
        });
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: hyperstreamTheme(viewport.brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(viewport.scale)),
              child: child!,
            ),
            home: LibraryScreen(
              client: client,
              playback: playback,
              onDisconnect: () async {
                await playback.reset();
                disconnected = true;
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byTooltip('Disconnect'), findsNothing);
        expect(find.byIcon(Icons.logout), findsNothing);

        Future<void> tap(Finder finder) async {
          await tester.ensureVisible(finder);
          await tester.pumpAndSettle();
          await tester.tap(finder);
          await tester.pumpAndSettle();
        }

        Future<void> menuIn(Type pane, Finder menu) async {
          await tester.scrollUntilVisible(
            menu.hitTestable(),
            180,
            scrollable: find
                .descendant(
                  of: find.byType(pane),
                  matching: find.byType(Scrollable),
                )
                .last,
          );
          await tap(menu);
        }

        await tap(find.text('Test album').first);
        await tap(find.byTooltip('Add to favorites'));
        expect(server.favoriteAlbums, {'album'});
        await menuIn(
          AlbumTracks,
          find.byTooltip('Song actions for First song'),
        );
        await tap(find.text('Add to favorites'));
        expect(server.favoriteSongs, {'one'});
        await tap(
          find.descendant(
            of: find.byWidgetPredicate(
              (w) => w is NavigationBar || w is NavigationRail,
            ),
            matching: find.text('Library'),
          ),
        );
        await tap(find.text('Favorites'));
        expect(find.text('Test album'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('First song').hitTestable(),
          160,
          scrollable: find
              .descendant(
                of: find.byType(FavoritesScreen),
                matching: find.byType(Scrollable),
              )
              .last,
        );
        expect(find.text('First song'), findsOneWidget);
        if (const bool.fromEnvironment('CAPTURE_PREVIEWS')) {
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(
              '../build/previews/${viewport.name}-favorites.png',
            ),
          );
        }
        await tap(find.text('Play favorite songs'));
        expect(playback.queue.value.map((item) => item.id), ['one']);
        await tap(find.byTooltip('Remove from favorites'));
        expect(server.favoriteAlbums, isEmpty);
        expect(find.text('Test album'), findsNothing);

        await tap(find.byTooltip('Song actions for First song'));
        await tap(find.text('Add to playlist'));
        expect(find.text('Shared set'), findsNothing);
        await tap(find.text('Weekend'));
        expect(server.playlists['owned']!['songs'], [
          'one',
          'two',
          'one',
          'one',
        ]);
        await tap(
          find.descendant(
            of: find.byWidgetPredicate(
              (w) => w is NavigationBar || w is NavigationRail,
            ),
            matching: find.text('Library'),
          ),
        );
        await tap(find.text('Playlists'));
        await tap(find.text('Weekend'));
        await tap(find.text('Play playlist'));
        expect(
          tester
              .widgetList<ListTile>(
                find.descendant(
                  of: find.byType(PlaylistTracks),
                  matching: find.byType(ListTile),
                ),
              )
              .where((tile) => tile.selected)
              .length,
          1,
        );
        expect(playback.queue.value.map((item) => item.id), [
          'one',
          'two',
          'one',
          'one',
        ]);
        if (const bool.fromEnvironment('CAPTURE_PREVIEWS')) {
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(
              '../build/previews/${viewport.name}-playlist.png',
            ),
          );
        }
        await menuIn(
          PlaylistTracks,
          find.descendant(
            of: find.widgetWithText(ListTile, '4'),
            matching: find.byTooltip('Song actions for First song'),
          ),
        );
        await tap(find.text('Remove from playlist'));
        expect(
          server.requests
              .lastWhere(
                (u) => u.queryParameters.containsKey('songIndexToRemove'),
              )
              .queryParameters['songIndexToRemove'],
          '3',
        );
        expect(server.playlists['owned']!['songs'], ['one', 'two', 'one']);
        // Editing the saved playlist does not unexpectedly replace the current queue.
        expect(playback.queue.value.length, 4);
        await tester.scrollUntilVisible(
          find.text('Rename playlist').hitTestable(),
          -180,
          scrollable: find
              .descendant(
                of: find.byType(PlaylistTracks),
                matching: find.byType(Scrollable),
              )
              .last,
        );
        await tap(find.text('Add songs'));
        await tester.enterText(find.byType(TextField), 'Second');
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();
        await tap(find.byTooltip('Add Second song to playlist'));
        expect(server.playlists['owned']!['songs'], [
          'one',
          'two',
          'one',
          'two',
        ]);
        expect(playback.queue.value.length, 4);
        await tap(find.byTooltip('Close add songs'));
        await tap(find.text('Rename playlist'));
        await tester.enterText(find.byType(TextField), 'Evening mix');
        await tap(find.text('Save'));
        expect(server.playlists['owned']!['name'], 'Evening mix');
        await tap(find.byTooltip('Back to playlists'));
        expect(find.text('Evening mix'), findsOneWidget);

        await tap(find.text('New playlist'));
        if (viewport.name == 'small-phone') {
          tester.view.viewInsets = const FakeViewPadding(bottom: 250);
          await tester.pumpAndSettle();
        }
        await tap(find.text('Save'));
        expect(find.text('Enter a playlist name.'), findsOneWidget);
        await tester.enterText(find.byType(TextField), 'Fresh playlist');
        await tap(find.text('Save'));
        tester.view.resetViewInsets();
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Fresh playlist').hitTestable(),
          160,
          scrollable: find
              .descendant(
                of: find.byType(PlaylistsScreen),
                matching: find.byType(Scrollable),
              )
              .last,
        );
        expect(find.text('Fresh playlist'), findsOneWidget);
        await tap(find.text('Shared set'));
        expect(find.text('Rename playlist'), findsNothing);
        await menuIn(
          PlaylistTracks,
          find.byTooltip('Song actions for Second song'),
        );
        expect(find.text('Remove from playlist'), findsNothing);
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();

        await tap(find.byTooltip('Settings'));
        await tester.ensureVisible(find.text('Disconnect from server'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Disconnect from server'));
        // The real app replaces this screen on disconnect. This fixture keeps
        // it mounted, so its progress indicator deliberately keeps animating.
        await tester.pump(const Duration(milliseconds: 400));
        expect(disconnected, isTrue);
        expect(playback.queue.value, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
