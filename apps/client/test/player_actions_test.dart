import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hyperstream_client/app_theme.dart';
import 'package:hyperstream_client/features/player/player_actions.dart';
import 'package:hyperstream_client/models/library.dart';
import 'package:hyperstream_client/services/library_collections.dart';
import 'package:hyperstream_client/services/navidrome_client.dart';
import 'package:hyperstream_client/services/playback_service.dart';
import 'package:hyperstream_client/widgets/glass_overlays.dart';
import 'package:hyperstream_client/widgets/glass_surface.dart';

import 'support/fake_player.dart';

void main() {
  testWidgets(
    'track actions navigate, rate, favorite, mix, and share without credentials',
    (tester) async {
      const track = Track(
        id: 'seed',
        title: 'First song',
        artist: 'Artist',
        album: 'Album',
        duration: Duration(minutes: 3),
        albumId: 'album',
        artistId: 'artist',
        userRating: 2,
      );
      final requests = <Uri>[];
      final client = NavidromeClient(
        serverUrl: 'https://music.example.com',
        username: 'test',
        password: 'secret',
        httpClient: MockClient((request) async {
          requests.add(request.url);
          return http.Response(
            jsonEncode({
              'subsonic-response': {
                'status': 'ok',
                if (request.url.path.endsWith('getSimilarSongs2.view'))
                  'similarSongs2': {
                    'song': [
                      {'id': 'next', 'title': 'Second song'},
                    ],
                  },
              },
            }),
            200,
          );
        }),
      );
      final store = LibraryCollections(client);
      final playback = PlaybackService(player: FakePlayer());
      addTearDown(() async {
        store.dispose();
        final disposing = playback.dispose();
        await tester.pump();
        await disposing;
        client.close();
      });
      Album? selectedAlbum;
      Artist? selectedArtist;
      String? shared;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            shared = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: hyperstreamTheme(Brightness.dark),
          home: Scaffold(
            body: Center(
              child: NowPlayingTrackActions(
                song: track,
                playback: playback,
                collections: store,
                onAlbum: (album) => selectedAlbum = album,
                onArtist: (artist) => selectedArtist = artist,
              ),
            ),
          ),
        ),
      );
      Future<void> open() async {
        await tester.tap(find.byTooltip('Song actions for First song'));
        await tester.pumpAndSettle();
      }

      await open();
      expect(find.text('Delete cache'), findsNothing);
      await tester.tap(find.text('Show album'));
      await tester.pumpAndSettle();
      expect(selectedAlbum?.id, 'album');
      await open();
      await tester.tap(find.text('Show artist'));
      await tester.pumpAndSettle();
      expect(selectedArtist?.id, 'artist');
      await open();
      await tester.tap(find.text('Rating · 2/5'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('4 stars'));
      await tester.pumpAndSettle();
      expect(store.rating(track), 4);
      expect(requests.last.queryParameters['rating'], '4');
      await open();
      await tester.tap(find.text('Add to favorites'));
      await tester.pumpAndSettle();
      expect(store.isFavorite(track.id, album: false), isTrue);
      await open();
      await tester.tap(find.text('Instant Mix'));
      await tester.pumpAndSettle();
      expect(playback.queue.value.map((item) => item.id), ['seed', 'next']);
      await open();
      await tester.tap(find.text('Share · copy details'));
      await tester.pumpAndSettle();
      expect(shared, 'First song — Artist\nAlbum');
      expect(shared, isNot(contains('secret')));
      expect(shared, isNot(contains('http')));
      expect(tester.takeException(), isNull);
      await playback.pause();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('an open glass sheet responds to Reduce Transparency', (
    tester,
  ) async {
    final enabled = ValueNotifier(true);
    addTearDown(enabled.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => ValueListenableBuilder<bool>(
          valueListenable: enabled,
          builder: (context, value, _) =>
              GlassScope(enabled: value, child: child!),
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showGlassSheet<void>(
                context: context,
                builder: (_) => const Text('Sheet'),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byType(BackdropFilter), findsOneWidget);
    enabled.value = false;
    await tester.pumpAndSettle();
    expect(find.byType(BackdropFilter), findsNothing);
    enabled.value = true;
    await tester.pumpAndSettle();
    expect(find.byType(BackdropFilter), findsOneWidget);
  });
}
