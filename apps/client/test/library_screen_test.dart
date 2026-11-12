import 'package:hyperstream_client/widgets/glass_overlays.dart';
import 'package:hyperstream_client/widgets/hyperstream_mark.dart';
import 'package:hyperstream_client/features/library/artwork_backdrop.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:hyperstream_client/widgets/floating_chrome.dart';

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
import 'package:hyperstream_client/widgets/glass_settings.dart';
import 'package:hyperstream_client/widgets/glass_surface.dart';

import 'support/fake_player.dart';
import 'support/account_fakes.dart';

import 'package:hyperstream_client/services/account_session.dart';
import 'package:hyperstream_client/services/account_store.dart';

import 'support/preview_artwork.dart';

Future<void> main() async {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });
  if (const bool.fromEnvironment('CAPTURE_PREVIEWS')) _PreviewBinding();
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
  final covers = const bool.fromEnvironment('CAPTURE_PREVIEWS')
      ? await Future.wait(List.generate(4, previewArtwork))
      : <List<int>>[];
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
      name: 'phone-light',
      size: const Size(393, 852),
      theme: ThemeMode.light,
      scale: 1.0,
    ),
    (
      name: 'tablet-light',
      size: const Size(1024, 1366),
      theme: ThemeMode.light,
      scale: 1.0,
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
      final homeAccount = SavedAccount(
        serverUrl: 'https://music.example.com',
        username: 'listener',
        password: 'synthetic',
        name: 'Home library',
      );
      final otherAccount = SavedAccount(
        serverUrl: 'https://archive.example.com',
        username: 'listener',
        password: 'synthetic',
        name: 'Archive',
      );
      final accounts = AccountSession(
        store: MemoryAccountStore()
          ..servers = SavedServers(
            accounts: [homeAccount, otherAccount],
            activeId: homeAccount.id,
          ),
        createClient: AccountClient.new,
      );
      await accounts.restore();
      addTearDown(accounts.dispose);
      final client = NavidromeClient(
        serverUrl: 'https://music.example.com',
        username: 'test',
        password: 'test',
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('getCoverArt.view') &&
              covers.isNotEmpty) {
            final index = [
              'one',
              'two',
              'three',
              'four',
            ].indexOf(request.url.queryParameters['id'] ?? 'one');
            return http.Response.bytes(
              covers[index < 0 ? 0 : index],
              200,
              headers: {'content-type': 'image/png'},
            );
          }
          return http.Response(
            jsonEncode({
              'subsonic-response': {
                'status': 'ok',
                'type': 'navidrome',
                'openSubsonic': true,
                if (request.url.path.endsWith('getPlaylists.view'))
                  'playlists': {
                    'playlist': [
                      for (var i = 0; i < 18; i++)
                        {
                          'id': 'playlist-$i',
                          'name':
                              [
                                'Evening rotation',
                                'Focus sessions',
                                'Weekend favorites',
                              ][i % 3] +
                              (i < 3 ? '' : ' ${i + 1}'),
                          'owner': 'test',
                          'songCount': 20 + i,
                          if (covers.isNotEmpty)
                            'coverArt': ['one', 'two', 'three', 'four'][i % 4],
                        },
                    ],
                  },
                if (request.url.path.endsWith('getGenres.view'))
                  'genres': {
                    'genre': [
                      {'value': 'Electronic', 'albumCount': 3},
                      {'value': 'Jazz', 'albumCount': 2},
                      {'value': 'Ambient', 'albumCount': 4},
                      {'value': 'Soul', 'albumCount': 1},
                    ],
                  },
                if (request.url.path.endsWith('getStarred2.view'))
                  'starred2': {},
                if (request.url.path.endsWith('getArtist.view'))
                  'artist': {
                    'album': [
                      {
                        'id': 'artist-album',
                        'name': 'Artist album',
                        'artist': 'Northline',
                        if (covers.isNotEmpty) 'coverArt': 'two',
                      },
                    ],
                  },
                if (request.url.path.endsWith('getAlbumList2.view'))
                  'albumList2': {
                    'album': [
                      {
                        'id': 'one',
                        if (covers.isNotEmpty) 'coverArt': 'one',
                        'name': 'After Hours',
                        'artist': 'The Night Ensemble',
                      },
                      {
                        'id': 'two',
                        if (covers.isNotEmpty) 'coverArt': 'two',
                        'name': 'Soft Focus',
                        'artist': 'Still Life',
                      },
                      {
                        'id': 'three',
                        if (covers.isNotEmpty) 'coverArt': 'three',
                        'name': 'Blue Room',
                        'artist': 'Sunday Sessions',
                      },
                      {
                        'id': 'four',
                        if (covers.isNotEmpty) 'coverArt': 'four',
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
                if (request.url.path.endsWith('search3.view'))
                  'searchResult3': {
                    if (request.url.queryParameters['artistCount'] != '0')
                      'artist': [
                        {
                          'id': 'northline',
                          'name': 'Northline',
                          'albumCount': 1,
                          if (covers.isNotEmpty) 'coverArt': 'two',
                        },
                      ],
                    if (request.url.queryParameters['albumCount'] != '0')
                      'album': [
                        {
                          'id': 'result',
                          'name': 'Search album',
                          'artist': 'Search artist',
                          if (covers.isNotEmpty) 'coverArt': 'three',
                        },
                      ],
                    if (request.url.queryParameters['songCount'] != '0' &&
                        request.url.queryParameters['songOffset'] == '0')
                      'song': [
                        {
                          'id': 'result-song',
                          'title': 'Search song',
                          'artist': 'Search artist',
                          'album': 'Search album',
                          'created': '2026-11-10T00:00:00Z',
                          'played': '2026-11-11T00:00:00Z',
                          'playCount': 1,
                          if (covers.isNotEmpty) 'coverArt': 'four',
                        },
                      ],
                  },
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(() async {
        final disposing = playback.dispose();
        // Futures created inside testWidgets need its simulated loop drained.
        await tester.pump();
        await disposing;
        client.close();
      });
      await playback.preferences.setThemeMode(viewport.theme);
      await playback.playAlbum(
        client,
        [
          const Track(
            id: 'track',
            title: 'A quiet place to start again',
            artist: 'The Night Ensemble',
            album: 'After Hours',
            duration: Duration(minutes: 3),
            container: 'mp3',
            bitRate: 320,
            albumId: 'one',
            artistId: 'northline',
          ),
          for (var i = 0; i < 12; i++)
            Track(
              id: 'queue-$i',
              title: [
                'After the rain',
                'City lights',
                'Into the blue',
                'A little further',
              ][i % 4],
              artist: [
                'Still Life',
                'New Horizons',
                'Sunday Sessions',
                'The Night Ensemble',
              ][i % 4],
              album: 'Sample album',
              duration: const Duration(minutes: 4),
              coverArt: covers.isEmpty
                  ? null
                  : ['one', 'two', 'three', 'four'][i % 4],
              container: 'mp3',
              bitRate: 320,
            ),
        ],
        0,
        coverArtId: covers.isNotEmpty ? 'one' : null,
      );
      await tester.pumpWidget(
        ListenableBuilder(
          listenable: playback.preferences,
          builder: (context, _) => MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: hyperstreamTheme(Brightness.light),
            darkTheme: hyperstreamTheme(Brightness.dark),
            themeMode: playback.preferences.themeMode,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(viewport.scale),
                padding: EdgeInsets.only(
                  bottom: viewport.size.width < 950 ? 34 : 0,
                ),
                viewPadding: EdgeInsets.only(
                  bottom: viewport.size.width < 950 ? 34 : 0,
                ),
              ),
              child: GlassSettings(
                preferences: playback.preferences,
                child: child!,
              ),
            ),
            home: LibraryScreen(
              accountSession: accounts,
              client: client,
              playback: playback,
              onDisconnect: () async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Hyperstream'), findsOneWidget);
      expect(find.byType(HyperstreamMark), findsOneWidget);
      Finder nav(String label) => find.descendant(
        of: find.byWidgetPredicate(
          (w) => w is FloatingNavigation || w is NavigationRail,
        ),
        matching: find.text(label),
      );
      expect(find.text('Appearance'), findsOneWidget);
      expect(find.text('Recently added'), findsNothing);
      if (viewport.size.width < 950) {
        expect(
          FloatingNavigation.destinations.map((destination) => destination.$1),
          ['Home', 'Library', 'Search'],
        );
      } else {
        expect(
          tester
              .widget<NavigationRail>(find.byType(NavigationRail))
              .destinations
              .map((destination) => (destination.label as Text).data),
          ['Home', 'Library', 'Search'],
        );
        expect(
          find.text('Choose an album or artist to explore.'),
          findsNothing,
        );
      }
      await _capturePreview(tester, '${viewport.name}-home');
      await tester.tap(nav('Library'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Playlists'));
      await tester.pumpAndSettle();
      await Scrollable.ensureVisible(
        tester.element(find.text('Recent Radio')),
        alignment: .35,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Recent Radio'));
      await tester.pumpAndSettle();
      expect(find.text('Play'), findsOneWidget);
      expect(find.text('Choose an album or artist to explore.'), findsNothing);
      await _capturePreview(tester, '${viewport.name}-radio');
      await tester.tap(find.byTooltip('Back to playlists'));
      await tester.pumpAndSettle();
      expect(find.text('Smart playlists'), findsNothing);
      expect(
        find.widgetWithText(TextField, 'Search Playlists'),
        findsOneWidget,
      );
      await _capturePreview(tester, '${viewport.name}-playlists');
      await tester.tap(find.byTooltip('New playlist'));
      await tester.pumpAndSettle();
      expect(find.byType(PopupMenuItem<String>), findsNWidgets(2));
      expect(find.text('New smart playlist'), findsOneWidget);
      await tester.tap(find.text('New smart playlist'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Playlist name'),
        'My Recent Radio',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('My Recent Radio'), findsOneWidget);
      await tester.dragFrom(const Offset(12, 180), const Offset(120, 4));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(TextField, 'Search Playlists'),
        findsOneWidget,
      );
      expect(find.text('My Recent Radio'), findsOneWidget);
      await _capturePreview(tester, '${viewport.name}-playlists-saved');
      final playlistsScroll = find
          .descendant(
            of: find.byKey(const PageStorageKey('playlists')),
            matching: find.byType(Scrollable),
          )
          .first;
      tester.state<ScrollableState>(playlistsScroll).position.jumpTo(90);
      await tester.pumpAndSettle();
      expect(
        tester.widget<FloatingTopBar>(find.byType(FloatingTopBar)).title,
        'Playlists',
      );
      await _capturePreview(tester, '${viewport.name}-playlists-scrolled');
      tester.state<ScrollableState>(playlistsScroll).position.jumpTo(0);
      await tester.pumpAndSettle();
      await tester.tap(nav('Library'));
      await tester.pumpAndSettle();
      expect(find.text('Artists'), findsOneWidget);
      expect(find.byTooltip('Previous track'), findsOneWidget);
      expect(tester.takeException(), isNull);
      // Optional visual review artifacts, excluded from normal CI/golden checks.
      await _capturePreview(tester, viewport.name);
      expect(find.byTooltip('Refresh albums'), findsNothing);
      expect(find.byTooltip('Settings'), findsNothing);
      if (viewport.size.width < 950 && viewport.scale <= 1.2) {
        await tester.drag(
          find.byKey(const PageStorageKey('library-hub')),
          const Offset(0, -300),
        );
        await tester.pumpAndSettle();
        expect(find.byTooltip('Expand navigation'), findsOneWidget);
        expect(find.byTooltip('Previous track'), findsOneWidget);
        await _capturePreview(tester, '${viewport.name}-collapsed');
        await tester.tap(find.byTooltip('Expand navigation'));
        await tester.pumpAndSettle();
        await tester.drag(
          find.byKey(const PageStorageKey('library-hub')),
          const Offset(0, 600),
        );
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Artists'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Northline'));
      await tester.pumpAndSettle();
      await Scrollable.ensureVisible(
        tester.element(find.text('Artist album')),
        alignment: .35,
      );
      await tester.tap(find.text('Artist album'));
      await tester.pumpAndSettle();
      expect(find.text('Play'), findsOneWidget);
      await tester.tap(find.byTooltip('Back to artist'));
      await tester.pumpAndSettle();
      expect(find.text('Artist album'), findsOneWidget);
      await tester.tap(nav('Library'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Music volume'));
      await tester.pumpAndSettle();
      final volumeTrack = tester.getRect(
        find.byKey(const ValueKey('vertical-volume-track')),
      );
      await tester.tapAt(
        Offset(
          volumeTrack.center.dx,
          volumeTrack.top + volumeTrack.height * .60,
        ),
      );
      await tester.pumpAndSettle();
      expect(player.volume, closeTo(.4, .01));
      await tester.tap(find.byTooltip('Mute music'));
      await tester.pumpAndSettle();
      expect(player.volume, 0);
      await tester.tap(find.byTooltip('Unmute music'));
      await tester.pumpAndSettle();
      expect(player.volume, closeTo(.4, .01));
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      await tester.tap(find.text('A quiet place to start again'));
      await tester.pumpAndSettle();
      expect(find.text('Now playing'), findsNothing);
      expect(find.byTooltip('Close player'), findsNothing);
      expect(tester.takeException(), isNull);
      await _capturePreview(tester, '${viewport.name}-player');
      await Scrollable.ensureVisible(
        tester.element(find.byTooltip('Music volume').last),
        alignment: .35,
      );
      await tester.tap(find.byTooltip('Music volume').last);
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byTooltip('Next track').last).right,
        lessThanOrEqualTo(
          tester
              .getRect(find.byKey(const ValueKey('vertical-volume-track')))
              .left,
        ),
      );
      await _capturePreview(tester, '${viewport.name}-volume');
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      // A drag previews position; only releasing it asks the native player to seek.
      final seekSlider = tester.widget<Slider>(find.byType(Slider).first);
      seekSlider.onChanged!(45000);
      await tester.pump();
      expect(player.seekCalls, 0);
      seekSlider.onChangeEnd!(45000);
      await tester.pumpAndSettle();
      expect(player.seekCalls, 1);
      expect(player.position, const Duration(seconds: 45));
      await Scrollable.ensureVisible(
        tester.element(find.byTooltip('Show queue')),
        alignment: .35,
      );
      await tester.tap(find.byTooltip('Show queue'));
      await tester.pumpAndSettle();
      expect(find.text('Up next'), findsOneWidget);
      expect(find.byTooltip('Queue options'), findsOneWidget);
      final queueList = find.byKey(const ValueKey('up-next-list'));
      final queuePlayer = find.byKey(const ValueKey('queue-player-overlay'));
      final queueSurface = find
          .ancestor(of: queuePlayer, matching: find.byType(GlassSurface))
          .last;
      expect(
        tester.getRect(queuePlayer).bottom,
        closeTo(tester.getRect(queueSurface).bottom, .1),
        reason: 'The list and player must fill the outer sheet, including the bottom safe area.',
      );
      if (viewport.size.width < 950) {
        expect(
          tester.getRect(find.byTooltip('Next track').last).bottom,
          lessThanOrEqualTo(tester.getRect(queuePlayer).bottom - 34),
          reason: 'Keep only the controls above the home indicator.',
        );
      }
      expect(
        tester.getRect(queueList).bottom,
        closeTo(tester.getRect(queuePlayer).bottom, .1),
        reason: 'The list viewport must continue beneath the player.',
      );
      final queueScroll = tester
          .state<ScrollableState>(
            find
                .descendant(of: queueList, matching: find.byType(Scrollable))
                .first,
          )
          .position;
      queueScroll.jumpTo(queueScroll.maxScrollExtent);
      await tester.pumpAndSettle();
      final lastQueueRow = find.descendant(
        of: queueList,
        matching: find.byKey(const ValueKey(12)),
      );
      expect(
        tester.getRect(lastQueueRow).bottom,
        lessThanOrEqualTo(tester.getRect(queuePlayer).top),
        reason: 'The final track must scroll fully above the player controls.',
      );
      expect(lastQueueRow.hitTestable(), findsOneWidget);
      queueScroll.jumpTo(0);
      await tester.pumpAndSettle();
      final playerBounds = tester.getRect(queuePlayer);
      for (final tile in tester.widgetList<ListTile>(
        find.descendant(of: queueList, matching: find.byType(ListTile)),
      )) {
        final row = find.byWidget(tile);
        final point = const Alignment(.9, 0).withinRect(tester.getRect(row));
        if (playerBounds.contains(point)) {
          expect(
            row.hitTestable(at: const Alignment(.9, 0)),
            findsNothing,
            reason:
                'Covered queue rows must not receive taps through the player.',
          );
        }
      }
      await _capturePreview(tester, '${viewport.name}-queue');
      await tester.tap(find.byTooltip('Queue options'));
      await tester.pumpAndSettle();
      await _capturePreview(tester, '${viewport.name}-queue-menu');
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      if (viewport.name == 'phone-light' || viewport.name == 'phone-dark') {
        final list = find.byKey(const ValueKey('up-next-list'));
        final pull = await tester.startGesture(
          tester.getTopLeft(list) + const Offset(80, 100),
        );
        await pull.moveBy(const Offset(0, 20));
        await pull.moveBy(const Offset(0, 260));
        await tester.pump(const Duration(milliseconds: 400));
        await pull.up();
      } else {
        await tester.tap(find.byTooltip('Close queue'));
      }
      await tester.pumpAndSettle();
      expect(find.text('Up next'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Soft Focus').hitTestable(),
        200,
        scrollable: find
            .descendant(
              of: find.byKey(const PageStorageKey('library-hub')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('Soft Focus'));
      await tester.pumpAndSettle();
      expect(find.text('Play'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(
        tester
            .widget<ArtworkBackdrop>(find.byType(ArtworkBackdrop).first)
            .coverArt,
        covers.isEmpty ? null : 'two',
      );
      if (viewport.size.width >= 950) {
        expect(
          tester.getRect(find.byTooltip('Back to albums')).left,
          greaterThanOrEqualTo(viewport.size.width - 370),
        );
      }
      await _capturePreview(tester, '${viewport.name}-album');
      if (find.byTooltip('Expand navigation').evaluate().isNotEmpty) {
        await tester.tap(find.byTooltip('Expand navigation'));
        await tester.pumpAndSettle();
      }
      await tester.tap(nav('Home'));
      await tester.pumpAndSettle();
      expect(find.text('Appearance'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _capturePreview(tester, '${viewport.name}-settings');
      await Scrollable.ensureVisible(
        tester.element(find.text('Servers')),
        alignment: .35,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Servers'));
      await tester.pumpAndSettle();
      expect(find.text('Home library'), findsOneWidget);
      expect(find.text('Archive'), findsOneWidget);
      await _capturePreview(tester, '${viewport.name}-servers');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Appearance'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(GlassDropdownField<ThemeMode>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Follow system').last);
      await tester.pumpAndSettle();
      expect(playback.preferences.themeMode, ThemeMode.system);
      expect(tester.takeException(), isNull);
      // Return from settings and search using the same persistent player.
      await tester.tap(find.byTooltip('Back to home'));
      await tester.pumpAndSettle();
      await playback.preferences.setThemeMode(viewport.theme);
      await tester.tap(nav('Search'));
      await tester.pumpAndSettle();
      expect(find.text('Browse your library'), findsOneWidget);
      await _capturePreview(tester, '${viewport.name}-discover');
      final discoveryScroll = tester
          .state<ScrollableState>(
            find
                .byWidgetPredicate(
                  (w) =>
                      w is Scrollable && w.axisDirection == AxisDirection.down,
                )
                .first,
          )
          .position;
      discoveryScroll.jumpTo(discoveryScroll.maxScrollExtent.clamp(0, 260));
      await tester.pumpAndSettle();
      await _capturePreview(tester, '${viewport.name}-discover-scrolled');
      discoveryScroll.jumpTo(0);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Search');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await _capturePreview(tester, '${viewport.name}-search');
      await Scrollable.ensureVisible(
        tester.element(find.byKey(const ValueKey('search-filter-songs'))),
        alignment: .35,
      );
      await tester.tap(find.byKey(const ValueKey('search-filter-songs')));
      await tester.pumpAndSettle();
      expect(find.text('Search song'), findsOneWidget);
      tester.view.physicalSize = viewport.size.width < 850
          ? const Size(1280, 800)
          : const Size(393, 852);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Search',
      );
      expect(find.text('Search song'), findsOneWidget);
      tester.view.physicalSize = viewport.size;
      await tester.pumpAndSettle();
      await Scrollable.ensureVisible(
        tester.element(find.byKey(const ValueKey('search-filter-albums'))),
        alignment: .35,
      );
      await tester.tap(find.byKey(const ValueKey('search-filter-albums')));
      await tester.pumpAndSettle();
      await Scrollable.ensureVisible(
        tester.element(find.text('Search album')),
        alignment: .35,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Search album'));
      await tester.pumpAndSettle();
      expect(find.text('Play'), findsOneWidget);
      await tester.tap(find.byTooltip('Back to search'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Search',
      );
      await Scrollable.ensureVisible(
        tester.element(find.byKey(const ValueKey('search-filter-songs'))),
        alignment: .35,
      );
      await tester.tap(find.byKey(const ValueKey('search-filter-songs')));
      await tester.pumpAndSettle();
      await Scrollable.ensureVisible(
        tester.element(find.text('Search song')),
        alignment: .35,
      );
      await tester.tap(find.text('Search song'));
      await tester.pumpAndSettle();
      expect(playback.mediaItem.value?.id, 'result-song');
      expect(find.text('Search song'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      await playback.pause();
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}

class _PreviewBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get disableShadows => false;
}

Future<void> _capturePreview(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('CAPTURE_PREVIEWS')) return;
  final context = tester.element(find.byType(MaterialApp));
  final images = tester.widgetList<Image>(find.byType(Image)).toList();
  // Codec work runs outside the simulated clock; wait for actual decoded covers.
  await tester.runAsync(() async {
    await Future.wait(
      images.map((image) => precacheImage(image.image, context)),
    );
  });
  await tester.pumpAndSettle();
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('../build/previews/$name.png'),
  );
}
