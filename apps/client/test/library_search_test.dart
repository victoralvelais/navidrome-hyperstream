import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hyperstream_client/app_theme.dart';
import 'package:hyperstream_client/features/search/library_search.dart';
import 'package:hyperstream_client/features/search/online_search_toggle.dart';
import 'package:hyperstream_client/services/mornye_sources.dart';
import 'package:hyperstream_client/services/music_provider.dart';
import 'package:hyperstream_client/services/navidrome_client.dart';
import 'package:hyperstream_client/services/music_sources.dart';
import 'package:hyperstream_client/services/playback_service.dart';

import 'support/fake_player.dart';

http.Response results({
  List<Map<String, dynamic>> songs = const [],
  List<Map<String, dynamic>> albums = const [],
}) => http.Response(
  jsonEncode({
    'subsonic-response': {
      'status': 'ok',
      'searchResult3': {'song': songs, 'album': albums},
    },
  }),
  200,
);

void main() {
  Future<void> mount(
    WidgetTester tester,
    Future<http.Response> Function(http.Request) handler, {
    bool discover = false,
    MusicSources? sources,
    Brightness brightness = Brightness.dark,
    double textScale = 1,
  }) async {
    final client = NavidromeClient(
      serverUrl: 'https://music.example.com',
      username: 'test',
      password: 'test',
      httpClient: MockClient(handler),
    );
    final playback = PlaybackService(player: FakePlayer());
    addTearDown(() async {
      final disposing = playback.dispose();
      await tester.pump();
      await disposing;
      client.close();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: hyperstreamTheme(brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: LibrarySearch(
            discover: discover,
            client: client,
            playback: playback,
            onAlbumSelected: (_) {},
            sources: sources,
          ),
        ),
      ),
    );
  }

  Future<void> query(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
  }

  for (final brightness in Brightness.values) {
    testWidgets(
      'online augments library results and keeps one search field in $brightness',
      (tester) async {
        tester.view.physicalSize = const Size(393, 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final onlineQueries = <String?>[];
        final libraryQueries = <String?>[];
        final pending = Completer<http.Response>();
        final sources = MusicSources(
          httpClient: () => MockClient((request) async {
            onlineQueries.add(request.url.queryParameters['q']);
            if (onlineQueries.length == 2) return pending.future;
            return http.Response(
              jsonEncode({
                'releases': [],
                'tracks': [
                  {
                    'id': 'upload',
                    'title': 'Online upload',
                    'artistNames': ['Uploader'],
                    'duration': 90000,
                  },
                ],
              }),
              200,
            );
          }),
        )..enabled = true;
        addTearDown(sources.dispose);
        await mount(
          tester,
          (request) async {
            libraryQueries.add(request.url.queryParameters['query']);
            return results(
              songs: [
                {'id': 'saved', 'title': 'Library song', 'artist': 'Artist'},
              ],
            );
          },
          sources: sources,
          brightness: brightness,
          textScale: 1.6,
        );
        await query(tester, 'remix');
        await tester.pumpAndSettle();
        expect(find.text('Library song'), findsOneWidget);
        expect(onlineQueries, isEmpty);
        final field = find.byType(TextField);
        final editor = tester.state<EditableTextState>(
          find.byType(EditableText),
        );
        await tester.tap(find.byKey(const ValueKey('search-online-toggle')));
        await tester.pumpAndSettle();
        expect(field, findsOneWidget);
        expect(tester.widget<TextField>(field).controller!.text, 'remix');
        expect(
          tester.state<EditableTextState>(find.byType(EditableText)),
          same(editor),
        );
        expect(find.text('Online upload'), findsOneWidget);
        expect(find.text('Library song'), findsOneWidget);
        expect(find.byType(DropdownButtonFormField<String>), findsNothing);
        expect(find.byType(FilterChip), findsNothing);
        expect(
          find.byTooltip('Download song to remote folder'),
          findsOneWidget,
        );
        expect(libraryQueries, ['remix']);
        expect(onlineQueries, ['remix']);
        await query(tester, 'another');
        await tester.tap(find.byKey(const ValueKey('search-online-toggle')));
        pending.complete(
          http.Response(
            jsonEncode({
              'releases': [],
              'tracks': [
                {'id': 'stale', 'title': 'Stale upload'},
              ],
            }),
            200,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Stale upload'), findsNothing);
        expect(find.text('Library song'), findsOneWidget);
        expect(tester.widget<TextField>(field).controller!.text, 'another');
        expect(libraryQueries, ['remix', 'another']);
        expect(onlineQueries, ['remix', 'another']);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'long press selects a source without toggling online or replacing library results',
    (tester) async {
      final catalogs = _SearchCatalogs();
      final sources = MusicSources(extensions: catalogs);
      addTearDown(() {
        sources.dispose();
        catalogs.dispose();
      });
      var libraryCalls = 0;
      await mount(tester, (_) async {
        libraryCalls++;
        return results(
          songs: [
            {'id': 'saved', 'title': 'Library song'},
          ],
        );
      }, sources: sources);
      await query(tester, 'remix');
      await tester.pumpAndSettle();
      final toggle = find.byKey(const ValueKey('search-online-toggle'));
      await tester.longPress(toggle);
      await tester.pumpAndSettle();
      expect(tester.widget<OnlineSearchToggle>(toggle).enabled, false);
      await tester.tap(
        find.byKey(const ValueKey('online-source-ytmusic-spotiflac')),
      );
      await tester.pumpAndSettle();
      expect(catalogs.selected, 'ytmusic-spotiflac');
      expect(catalogs.queries, isEmpty);
      expect(find.text('Library song'), findsOneWidget);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(find.text('YouTube upload'), findsOneWidget);
      expect(find.text('Library song'), findsOneWidget);
      expect(find.text('Browse source'), findsNothing);
      await tester.longPress(toggle);
      await tester.pumpAndSettle();
      expect(tester.widget<OnlineSearchToggle>(toggle).enabled, true);
      await tester.tap(find.byKey(const ValueKey('online-source-tidal-web')));
      await tester.pumpAndSettle();
      expect(find.text('Tidal song'), findsOneWidget);
      expect(find.text('YouTube upload'), findsNothing);
      expect(find.text('Library song'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'remix',
      );
      expect(catalogs.queries, ['ytmusic-spotiflac:remix', 'tidal-web:remix']);
      expect(libraryCalls, 1);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(find.text('Tidal song'), findsNothing);
      expect(find.text('Library song'), findsOneWidget);
      expect(libraryCalls, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'online failure leaves library matches usable and retry only requests online',
    (tester) async {
      var libraryCalls = 0;
      final catalogs = _SearchCatalogs()..fail = true;
      final sources = MusicSources(extensions: catalogs);
      addTearDown(() {
        sources.dispose();
        catalogs.dispose();
      });
      await mount(tester, (_) async {
        libraryCalls++;
        return results(
          songs: [
            {'id': 'saved', 'title': 'Library song'},
          ],
        );
      }, sources: sources);
      await tester.tap(find.byKey(const ValueKey('search-online-toggle')));
      await query(tester, 'remix');
      await tester.pumpAndSettle();
      expect(find.text('Library song'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      await tester.ensureVisible(find.text('Retry'));
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(catalogs.queries, hasLength(2));
      expect(libraryCalls, 1);
      expect(find.text('Library song'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'filters apply to both result groups without repeating their searches',
    (tester) async {
      final catalogs = _SearchCatalogs()..includeAlbum = true;
      final sources = MusicSources(extensions: catalogs);
      addTearDown(() {
        sources.dispose();
        catalogs.dispose();
      });
      var libraryCalls = 0;
      await mount(tester, (_) async {
        libraryCalls++;
        return results(
          songs: [
            {'id': 'saved', 'title': 'Library song'},
          ],
          albums: [
            {'id': 'album', 'name': 'Library album'},
          ],
        );
      }, sources: sources);
      await tester.tap(find.byKey(const ValueKey('search-online-toggle')));
      await query(tester, 'remix');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('search-filter-albums')));
      await tester.pumpAndSettle();
      expect(find.text('Library album'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Online album'),
        150,
        scrollable: find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        ),
      );
      expect(find.text('Online album'), findsOneWidget);
      expect(find.text('Library song'), findsNothing);
      expect(find.text('Tidal song'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('search-filter-songs')));
      await tester.pumpAndSettle();
      expect(find.text('Library song'), findsOneWidget);
      expect(find.text('Tidal song'), findsOneWidget);
      expect(find.text('Library album'), findsNothing);
      expect(find.text('Online album'), findsNothing);
      expect(libraryCalls, 1);
      expect(catalogs.queries, hasLength(1));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'online finishes independently while the library request is pending',
    (tester) async {
      final catalogs = _SearchCatalogs();
      final sources = MusicSources(extensions: catalogs);
      addTearDown(() {
        sources.dispose();
        catalogs.dispose();
      });
      final library = Completer<http.Response>();
      await mount(tester, (_) => library.future, sources: sources);
      await query(tester, 'remix');
      await tester.tap(find.byKey(const ValueKey('search-online-toggle')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Tidal song'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('search-online-toggle')));
      library.complete(
        results(
          songs: [
            {'id': 'saved', 'title': 'Library song'},
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Library song'), findsOneWidget);
      expect(find.text('Tidal song'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'search stays pinned over discovery and results without losing focus',
    (tester) async {
      tester.view.physicalSize = const Size(393, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await mount(tester, (request) async {
        if (request.url.path.endsWith('search3.view')) {
          return results(
            songs: List.generate(
              20,
              (i) => {'id': '$i', 'title': 'Song $i', 'artist': 'Artist'},
            ),
          );
        }
        return http.Response(
          jsonEncode({
            'subsonic-response': {
              'status': 'ok',
              'genres': {
                'genre': [
                  for (var i = 0; i < 8; i++)
                    {'value': 'Genre $i', 'albumCount': 1},
                ],
              },
              'albumList2': {'album': []},
            },
          }),
          200,
        );
      }, discover: true);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('search-online-toggle')));
      await tester.pumpAndSettle();
      expect(find.text('Recently added'), findsOneWidget);
      expect(find.text('Browse source'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('search-online-toggle')));
      await tester.pumpAndSettle();
      final field = find.byType(TextField);
      final fieldBounds = tester.getRect(field);
      ScrollPosition position() => tester
          .state<ScrollableState>(
            find
                .byWidgetPredicate(
                  (w) =>
                      w is Scrollable && w.axisDirection == AxisDirection.down,
                )
                .first,
          )
          .position;
      final tile = find.text('Recently added');
      position().jumpTo(tester.getRect(tile).center.dy - fieldBounds.center.dy);
      await tester.pumpAndSettle();
      expect(tester.getRect(field), fieldBounds);
      expect(tester.getRect(tile).overlaps(fieldBounds), isTrue);
      expect(
        tile.hitTestable(),
        findsNothing,
        reason:
            'The pinned search editor must receive taps over a covered tile.',
      );

      await tester.tap(field);
      await tester.pump();
      final editor = tester.state<EditableTextState>(find.byType(EditableText));
      expect(editor.widget.focusNode.hasFocus, isTrue);
      await query(tester, 'song');
      await tester.pumpAndSettle();
      expect(
        tester.state<EditableTextState>(find.byType(EditableText)),
        same(editor),
      );
      expect(editor.widget.focusNode.hasFocus, isTrue);
      final song = find.text('Song 0');
      position().jumpTo(tester.getRect(song).center.dy - fieldBounds.center.dy);
      await tester.pumpAndSettle();
      expect(tester.getRect(field), fieldBounds);
      expect(tester.getRect(song).overlaps(fieldBounds), isTrue);
      expect(song.hitTestable(), findsNothing);
      position().jumpTo(position().maxScrollExtent);
      await tester.pumpAndSettle();
      expect(find.text('Song 19').hitTestable(), findsOneWidget);
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      expect(
        tester.state<EditableTextState>(find.byType(EditableText)),
        same(editor),
      );
      expect(editor.widget.focusNode.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'debounces typing and ignores stale success or failure after query changes',
    (tester) async {
      final requests = <String>[];
      final first = Completer<http.Response>();
      final second = Completer<http.Response>();
      await mount(tester, (request) {
        final text = request.url.queryParameters['query']!;
        requests.add(text);
        return text == 'first' ? first.future : second.future;
      });
      await tester.enterText(find.byType(TextField), 'fir');
      await tester.pump(const Duration(milliseconds: 200));
      expect(requests, isEmpty);
      await query(tester, 'first');
      await query(tester, 'second');
      expect(requests, ['first', 'second']);
      second.complete(
        results(
          songs: [
            {'id': 'new', 'title': 'New result'},
          ],
        ),
      );
      await tester.pumpAndSettle();
      first.completeError(http.ClientException('private error'));
      await tester.pumpAndSettle();
      expect(find.text('New result'), findsOneWidget);
      expect(find.text('Retry search'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('clearing a pending search prevents results from reappearing', (
    tester,
  ) async {
    final pending = Completer<http.Response>();
    var calls = 0;
    await mount(tester, (_) {
      calls++;
      return pending.future;
    });
    await query(tester, 'pending');
    await tester.tap(find.byTooltip('Clear search'));
    pending.complete(
      results(
        songs: [
          {'id': 'old', 'title': 'Old result'},
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('Old result'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await query(tester, '   ');
    expect(calls, 1);
    // Also dispose with a queued debounce: it must not issue a request later.
    await tester.enterText(find.byType(TextField), 'unmounted');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    expect(calls, 1);
  });

  testWidgets(
    'pagination retries the failed page and preserves earlier results',
    (tester) async {
      var failNextPage = true;
      final failedPage = Completer<http.Response>();
      final pages = <Map<String, String>>[];
      await mount(tester, (request) async {
        final parameters = request.url.queryParameters;
        pages.add(parameters);
        if (parameters['albumOffset'] == '20') {
          if (failNextPage) return failedPage.future;
          return results(
            albums: [
              {'id': 'last', 'name': 'Last album'},
            ],
          );
        }
        return results(
          albums: List.generate(20, (i) => {'id': '$i', 'name': 'Album $i'}),
          songs: [
            {'id': 'song', 'title': 'Matching song'},
          ],
        );
      });
      await query(tester, 'album');
      await tester.pumpAndSettle();
      final scrollable = find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          )
          .first;
      await tester.scrollUntilVisible(
        find.text('More albums'),
        400,
        scrollable: scrollable,
      );
      await tester.tap(find.text('More albums'));
      // A second tap before the next frame must not request the same page twice.
      await tester.tap(find.text('More albums'));
      failedPage.complete(http.Response('unavailable', 503));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Retry search').hitTestable(),
        250,
        scrollable: scrollable,
      );
      expect(find.text('Matching song'), findsOneWidget);
      failNextPage = false;
      await tester.tap(find.text('Retry search'));
      await tester.pumpAndSettle();
      expect(pages.map((p) => p['albumOffset']), ['0', '20', '20']);
      expect(pages.last['songCount'], '0');
      expect(find.text('Last album'), findsOneWidget);
      expect(find.text('Matching song'), findsOneWidget);
      expect(find.text('More albums'), findsNothing);
      expect(find.text('Retry search'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

class _SearchCatalogs extends MornyeSources {
  _SearchCatalogs() {
    extensions = [
      for (final entry in [
        ('tidal-web', 'Tidal'),
        ('ytmusic-spotiflac', 'YouTube Music'),
      ])
        MornyeExtension({
          'id': entry.$1,
          'display_name': entry.$2,
          'version': '1.0.0',
          'download_url': 'https://example.test/extension',
          'sha256': 'synthetic',
          'audio': true,
          'installed': true,
          'enabled': true,
        }),
    ];
    selected = 'tidal-web';
  }
  final queries = <String>[];
  bool fail = false;
  bool includeAlbum = false;
  @override
  Future<void> choose({
    String? catalog,
    String? audio,
    bool legacy = false,
  }) async {
    selected = catalog;
    notifyListeners();
  }

  @override
  Future<dynamic> execute(
    Map<String, dynamic> request, {
    Future<void>? abort,
  }) async {
    queries.add('${request['id']}:${request['args'][0]}');
    if (fail) {
      throw const SourceException('This source is unavailable. Try again.');
    }
    return [
      if (includeAlbum)
        {
          'id': 'album',
          'name': 'Online album',
          'item_type': 'album',
          'artists': 'Artist',
        },
      {
        'id': 'upload',
        'name': request['id'] == 'tidal-web' ? 'Tidal song' : 'YouTube upload',
        'artists': 'Artist',
      },
    ];
  }
}
