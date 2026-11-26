import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperstream_client/features/library/cover_art.dart';
import 'package:hyperstream_client/features/library/listening_history_screen.dart';
import 'package:hyperstream_client/services/library_catalog.dart';
import 'package:hyperstream_client/services/playback_service.dart';
import 'package:just_audio/just_audio.dart';

import 'external_playback_test.dart' show externalSong;
import 'recent_radio_service_test.dart' show api, envelope, song;
import 'support/fake_player.dart';

void main() {
  testWidgets('History mixes server and external listens in playback order', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 11, 12);
    final client = api(
      (request) => envelope({
        'searchResult3': {
          'song': request.url.queryParameters['songOffset'] == '0'
              ? [
                  {...song('library'), 'title': 'Library song'},
                  {'id': 'unplayed', 'title': 'Unplayed song'},
                ]
              : [],
        },
      }),
    );
    final player = FakePlayer();
    final playback = PlaybackService(
      player: player,
      configureSession: (_) async {},
      sourceStreamUri: (_) => Uri.parse('https://source.example/track'),
    );
    final catalog = LibraryCatalog(client, now: () => now);
    addTearDown(client.close);
    addTearDown(() async {
      final disposing = playback.dispose();
      await tester.pump();
      await disposing;
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListeningHistoryScreen(catalog: catalog, playback: playback),
        ),
      ),
    );
    await tester.pumpAndSettle();
    client.recordLocalListen(externalSong, now);
    await tester.pumpAndSettle();

    final external = find.byKey(ValueKey('history-${externalSong.id}'));
    final library = find.byKey(const ValueKey('history-library'));
    expect(
      tester.getTopLeft(external).dy,
      lessThan(tester.getTopLeft(library).dy),
    );
    expect(find.text('Unplayed song'), findsNothing);
    final coverArt = tester.widget<CoverArt>(
      find.descendant(of: external, matching: find.byType(CoverArt)),
    );
    expect(coverArt.sourceId, externalSong.source!.sourceId);
    await tester.tap(find.text(externalSong.title));
    await tester.pumpAndSettle();
    expect(playback.mediaItem.value!.id, externalSong.id);
    expect(playback.queue.value.map((item) => item.id), [
      externalSong.id,
      'library',
    ]);
    expect(
      (player.loaded.single.first as UriAudioSource).uri.host,
      'source.example',
    );
    await playback.pause();
    catalog.dispose();
  });
}
