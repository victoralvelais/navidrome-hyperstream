import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hyperstream_client/app_theme.dart';
import 'package:hyperstream_client/features/search/library_search.dart';
import 'package:hyperstream_client/services/navidrome_client.dart';
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
        theme: hyperstreamTheme(Brightness.dark),
        home: Scaffold(
          body: LibrarySearch(
            discover: discover,
            client: client,
            playback: playback,
            onAlbumSelected: (_) {},
          ),
        ),
      ),
    );
  }

  Future<void> query(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
  }

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
