import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperstream_client/app_theme.dart';
import 'package:hyperstream_client/features/playlists/smart_playlist_results.dart';
import 'package:hyperstream_client/features/playlists/smart_playlists_screen.dart';
import 'package:hyperstream_client/models/smart_playlist.dart';
import 'package:hyperstream_client/services/library_catalog.dart';
import 'package:hyperstream_client/services/playback_service.dart';
import 'package:hyperstream_client/services/playlist_icon_store.dart';
import 'package:hyperstream_client/services/smart_playlist_store.dart';

import 'recent_radio_service_test.dart' show api, envelope;
import 'smart_playlist_screen_test.dart' show tapVisible;
import 'support/fake_player.dart';

void main() {
  for (final width in [320.0, 1280.0]) {
    testWidgets(
      'edit, play and persist variety and reshuffle in both types at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var scans = 0;
        final now = DateTime.utc(2026, 11, 13);
        final client = api((request) {
          final first = request.url.queryParameters['songOffset'] == '0';
          if (first) scans++;
          return envelope({
            'searchResult3': {
              'song': first
                  ? [
                      for (var i = 0; i < 12; i++)
                        {
                          'id': 'song-$i',
                          'title': 'Song $i',
                          'artist': 'Artist ${i % 4}',
                          'duration': 180,
                          'created': '2026-11-12T00:00:00Z',
                        },
                    ]
                  : [],
            },
          });
        });
        final catalog = LibraryCatalog(client, now: () => now);
        var catalogDisposed = false;
        final player = FakePlayer();
        final playback = PlaybackService(
          player: player,
          artworkLoader: (_, _) async => null,
        );
        final icons = PlaylistIconStore(
          client,
          read: (_) async => null,
          write: (_, _) async {},
        );
        var failSave = false;
        String? disk;
        final store = SmartPlaylistStore(
          client,
          read: (_) async => disk,
          write: (_, value) async {
            if (failSave) throw StateError('disk');
            disk = value;
          },
        );
        addTearDown(() async {
          final closing = playback.dispose();
          await tester.pump();
          await closing;
          store.dispose();
          icons.dispose();
          if (!catalogDisposed) catalog.dispose();
          client.close();
        });
        await store.save(
          SmartPlaylistDefinition(
            id: 'variety',
            name: 'Personal radio',
            type: SmartPlaylistType.rules,
            include: SmartGroup(),
            exclude: SmartGroup(all: false),
            shuffleSeed: 42,
            pools: [
              SmartPool(name: 'First', rules: SmartGroup(), share: 60),
              SmartPool(name: 'Second', rules: SmartGroup(), share: 40),
            ],
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: hyperstreamTheme(Brightness.dark),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(width == 320 ? 1.4 : 1)),
              child: child!,
            ),
            home: Scaffold(
              body: SmartPlaylistScreen(
                id: 'variety',
                catalog: catalog,
                store: store,
                icons: icons,
                playback: playback,
                onDeleted: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tapVisible(tester, find.text('Edit configuration'));
        await tapVisible(tester, find.byTooltip('Order'));
        await tapVisible(tester, find.text('Stable shuffle'));
        await tapVisible(tester, find.byTooltip('Artist spacing'));
        await tapVisible(tester, find.text('3 other songs between repeats'));
        await tapVisible(tester, find.text('Relax spacing when necessary'));
        await tapVisible(tester, find.text('Preview tracks'));
        List<String> ids() => tester
            .widget<SmartPlaylistResults>(find.byType(SmartPlaylistResults))
            .preview
            .result!
            .matches
            .map((m) => m.track.id)
            .toList();
        final first = ids();
        expect(first, hasLength(12));
        await tapVisible(tester, find.text('Play'));
        final queue = playback.queue.value.map((t) => t.id).toList();
        expect(queue, first);
        await tapVisible(tester, find.text('Reshuffle'));
        final second = ids();
        expect(second, isNot(first));
        expect(playback.queue.value.map((t) => t.id), queue);
        await tapVisible(tester, find.text('Save'));
        expect(store.items.single.shuffleSeed, 43);
        expect(store.items.single.artistGap, 3);
        expect(store.items.single.relaxArtistGap, isFalse);
        await tapVisible(tester, find.text('Reshuffle'));
        expect(store.items.single.shuffleSeed, 44);
        final savedOrder = ids();
        failSave = true;
        await tapVisible(tester, find.text('Reshuffle'));
        expect(store.items.single.shuffleSeed, 44);
        expect(ids(), savedOrder);
        expect(
          find.text('Could not save the new shuffle. Try again.'),
          findsOneWidget,
        );
        failSave = false;
        await tapVisible(tester, find.text('Reshuffle'));
        expect(store.items.single.shuffleSeed, 45);
        expect(playback.queue.value.map((t) => t.id), queue);
        final reopened = SmartPlaylistStore(
          client,
          read: (_) async => disk,
          write: (_, _) async {},
        );
        await reopened.load();
        expect(reopened.items.single.toJson(), store.items.single.toJson());
        reopened.dispose();
        await tapVisible(tester, find.text('Edit configuration'));
        await tapVisible(tester, find.text('Mix'));
        await tapVisible(tester, find.text('First · 60%'));
        await tapVisible(tester, find.byTooltip('Order'));
        await tapVisible(tester, find.text('Stable shuffle'));
        await tapVisible(tester, find.text('Done'));
        await tapVisible(tester, find.text('Preview tracks'));
        expect(ids(), hasLength(12));
        await tapVisible(tester, find.text('Save'));
        expect(store.items.single.type, SmartPlaylistType.mix);
        expect(store.items.single.pools.first.order, SmartOrder.stableShuffle);
        expect(store.items.single.order, SmartOrder.stableShuffle);
        expect(store.items.single.artistGap, 3);
        await tapVisible(tester, find.text('Reshuffle'));
        expect(store.items.single.shuffleSeed, 46);
        client.recordLocalListen(catalog.tracks.first, now);
        await tester.pumpAndSettle();
        expect(store.items.single.shuffleSeed, 46);
        expect(scans, 1);
        expect(playback.queue.value.map((t) => t.id), queue);
        await tapVisible(tester, find.text('Edit configuration'));
        await tapVisible(tester, find.text('Rules'));
        await tapVisible(tester, find.byTooltip('Order'));
        await tapVisible(tester, find.text('Custom ranking'));
        await tapVisible(tester, find.byKey(const ValueKey('addedDays')));
        await tester.enterText(find.byKey(const ValueKey('addedDays')), '');
        await tapVisible(tester, find.text('Preview tracks'));
        expect(
          find.text('Ranking windows must be from 1 to 3650 days.'),
          findsOneWidget,
        );
        await tapVisible(tester, find.byKey(const ValueKey('addedDays')));
        await tester.enterText(find.byKey(const ValueKey('addedDays')), '14');
        await tapVisible(tester, find.text('Preview tracks'));
        expect(
          tester
              .widget<SmartPlaylistResults>(find.byType(SmartPlaylistResults))
              .preview
              .result!
              .matches
              .first
              .score,
          isNotNull,
        );
        await tapVisible(tester, find.text('Mix'));
        await tapVisible(tester, find.text('First · 60%'));
        await tapVisible(tester, find.byTooltip('Order'));
        await tapVisible(tester, find.text('Custom ranking'));
        await tapVisible(tester, find.byKey(const ValueKey('addedDays')));
        await tester.enterText(find.byKey(const ValueKey('addedDays')), '60');
        await tapVisible(tester, find.text('Done'));
        await tapVisible(tester, find.text('Preview tracks'));
        await tapVisible(tester, find.text('Save'));
        expect(store.items.single.order, SmartOrder.customRanking);
        expect(store.items.single.ranking.addedDays, 14);
        expect(store.items.single.pools.first.ranking.addedDays, 60);
        expect(store.items.single.pools.first.order, SmartOrder.customRanking);
        final rankedReload = SmartPlaylistStore(
          client,
          read: (_) async => disk,
          write: (_, _) async {},
        );
        await rankedReload.load();
        expect(rankedReload.items.single.toJson(), store.items.single.toJson());
        rankedReload.dispose();
        expect(playback.queue.value.map((t) => t.id), queue);
        expect(scans, 1);
        expect(tester.takeException(), isNull);
        await playback.pause();
        await tester.pumpWidget(const SizedBox.shrink());
        catalog.dispose();
        catalogDisposed = true;
        await tester.pumpAndSettle();
      },
    );
  }
}
