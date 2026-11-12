import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:hyperstream_client/features/library/library_screen.dart';
import 'package:hyperstream_client/features/playlists/recent_radio_screen.dart';
import 'package:hyperstream_client/main.dart';
import 'package:hyperstream_client/services/account_session.dart';
import 'package:hyperstream_client/services/account_store.dart';
import 'package:hyperstream_client/services/catalog_cache.dart';
import 'package:hyperstream_client/services/navidrome_client.dart';
import 'package:hyperstream_client/services/playback_service.dart';

import 'catalog_cache_test.dart' show MemoryCatalogCache;
import 'support/account_fakes.dart';
import 'support/fake_player.dart';

http.Response _response([Map<String, Object?> data = const {}]) =>
    http.Response(
      jsonEncode({
        'subsonic-response': {'status': 'ok', 'type': 'navidrome', ...data},
      }),
      200,
    );

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });
  testWidgets(
    'cold catalog starts on connected Home and navigation shares the in-flight sync',
    (tester) async {
      final page = Completer<http.Response>();
      var pages = 0;
      final client = NavidromeClient(
        serverUrl: 'https://music.example.com',
        username: 'test',
        password: 'synthetic',
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/auth/login')) {
            return http.Response('', 404);
          }
          if (request.url.path.endsWith('search3.view')) {
            pages++;
            return pages == 1 ? page.future : _response({'searchResult3': {}});
          }
          return _response();
        }),
      );
      final cache = MemoryCatalogCache();
      final playback = PlaybackService(player: FakePlayer());
      addTearDown(() async {
        final closing = playback.dispose();
        await tester.pump();
        await closing;
        client.close();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: LibraryScreen(
            client: client,
            playback: playback,
            catalogCache: cache,
            onDisconnect: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Hyperstream'), findsOneWidget);
      expect(
        pages,
        1,
        reason: 'The catalog scan must already be running on Home.',
      );
      expect(cache.saved, isNull);
      // Navigation is responsive while the catalog page is waiting on the server.
      await tester.tap(find.text('Library'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Playlists'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Recent Radio'));
      await tester.pump();
      expect(find.byType(RecentRadioScreen), findsOneWidget);
      expect(pages, 1, reason: 'Opening Radio must reuse the startup request.');
      page.complete(
        _response({
          'searchResult3': {
            'song': [
              {
                'id': 'background-song',
                'title': 'Ready before opening',
                'created': DateTime.now().toUtc().toIso8601String(),
                'played': DateTime.now().toUtc().toIso8601String(),
                'playCount': 1,
              },
            ],
          },
        }),
      );
      await tester.pumpAndSettle();
      expect(pages, 2);
      expect(find.text('Ready before opening'), findsOneWidget);
      expect(cache.saved!.tracks.single.id, 'background-song');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('connected startup reuses a fresh catalog without another scan', (
    tester,
  ) async {
    var pages = 0;
    final client = NavidromeClient(
      serverUrl: 'https://music.example.com',
      username: 'test',
      password: 'synthetic',
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('search3.view')) pages++;
        return _response();
      }),
    );
    final cache = MemoryCatalogCache()
      ..saved = CatalogSnapshot(syncedAt: DateTime.now().toUtc(), tracks: []);
    final playback = PlaybackService(player: FakePlayer());
    addTearDown(() async {
      final closing = playback.dispose();
      await tester.pump();
      await closing;
      client.close();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          client: client,
          playback: playback,
          catalogCache: cache,
          onDisconnect: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Hyperstream'), findsOneWidget);
    expect(pages, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'leaving the connected account cancels a startup scan before the next page',
    (tester) async {
      final page = Completer<http.Response>();
      var pages = 0;
      final client = NavidromeClient(
        serverUrl: 'https://music.example.com',
        username: 'test',
        password: 'synthetic',
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/auth/login')) {
            return http.Response('', 404);
          }
          if (request.url.path.endsWith('search3.view')) {
            pages++;
            return page.future;
          }
          return _response();
        }),
      );
      final cache = MemoryCatalogCache();
      final playback = PlaybackService(player: FakePlayer());
      addTearDown(() async {
        final closing = playback.dispose();
        await tester.pump();
        await closing;
        client.close();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: LibraryScreen(
            client: client,
            playback: playback,
            catalogCache: cache,
            onDisconnect: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(pages, 1);
      await tester.pumpWidget(const SizedBox());
      page.complete(
        _response({
          'searchResult3': {
            'song': [
              {
                'id': 'old-account',
                'created': '2026-11-12T00:00:00Z',
                'played': '2026-11-12T00:00:00Z',
              },
            ],
          },
        }),
      );
      await tester.pump();
      expect(pages, 1);
      expect(cache.writes, 0);
    },
  );

  testWidgets(
    'signed-out and rejected sessions never mount the catalog-loading screen',
    (tester) async {
      var requests = 0;
      final session = AccountSession(
        store: MemoryAccountStore(),
        createClient:
            ({required serverUrl, required username, required password}) =>
                NavidromeClient(
                  serverUrl: serverUrl,
                  username: username,
                  password: password,
                  httpClient: MockClient((request) async {
                    requests++;
                    expect(request.url.path, endsWith('ping.view'));
                    return http.Response(
                      jsonEncode({
                        'subsonic-response': {
                          'status': 'failed',
                          'error': {'code': 40, 'message': 'Wrong credentials'},
                        },
                      }),
                      200,
                    );
                  }),
                ),
      );
      final playback = PlaybackService(player: FakePlayer());
      await tester.pumpWidget(
        HyperstreamApp(
          accountSession: session,
          initialize: (_) async => playback,
        ),
      );
      await tester.pumpAndSettle();
      expect(requests, 0);
      expect(find.byType(LibraryScreen), findsNothing);
      unawaited(
        session.connect(
          SavedAccount(
            serverUrl: 'https://music.example.com',
            username: 'test',
            password: 'wrong',
          ),
          remember: false,
        ),
      );
      await tester.pumpAndSettle();
      expect(requests, 1);
      expect(session.client, isNull);
      expect(find.byType(LibraryScreen), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );
}
