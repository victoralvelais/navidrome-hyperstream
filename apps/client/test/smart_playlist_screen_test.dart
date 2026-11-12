import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperstream_client/app_theme.dart';
import 'package:hyperstream_client/features/playlists/smart_playlist_editor.dart';
import 'package:hyperstream_client/features/playlists/smart_playlists_screen.dart';
import 'package:hyperstream_client/models/smart_playlist.dart';
import 'package:hyperstream_client/services/library_catalog.dart';
import 'package:hyperstream_client/services/playback_service.dart';
import 'package:hyperstream_client/services/smart_playlist_store.dart';

import 'recent_radio_service_test.dart' show api, envelope;
import 'support/fake_player.dart';

Finder field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    final scrollable = find
        .descendant(
          of: find.byType(ListView).first,
          matching: find.byType(Scrollable),
        )
        .first;
    tester.state<ScrollableState>(scrollable).position.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      finder,
      250,
      scrollable: scrollable,
      maxScrolls: 40,
    );
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

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
      'create, preview, save, reopen and play both types at ${size.width}',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var scans = 0;
        var failSave = false;
        String? disk;
        var now = DateTime.utc(2026, 11, 11, 18);
        final client = api((request) {
          final first = request.url.queryParameters['songOffset'] == '0';
          if (first) scans++;
          return envelope({
            'searchResult3': {
              'song': first
                  ? [
                      {
                        'id': 'new',
                        'title': 'New discovery',
                        'artist': 'Northline',
                        'created': '2026-11-10T00:00:00Z',
                        'duration': 180,
                      },
                      {
                        'id': 'old',
                        'title': 'Older favorite',
                        'artist': 'The Night Ensemble',
                        'created': '2026-01-01T00:00:00Z',
                        'played': '2026-11-11T17:00:00Z',
                        'playCount': 1,
                        'duration': 180,
                      },
                    ]
                  : [],
            },
          });
        });
        final catalog = LibraryCatalog(client, now: () => now);
        final store = SmartPlaylistStore(
          client,
          read: (_) async => disk,
          write: (_, value) async {
            if (failSave) throw StateError('disk');
            disk = value;
          },
        );
        final playback = PlaybackService(player: FakePlayer());
        addTearDown(() async {
          final disposing = playback.dispose();
          await tester.pump();
          await disposing;
          store.dispose();
          client.close();
        });
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: hyperstreamTheme(Brightness.dark),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(size.width == 320 ? 1.4 : 1),
              ),
              child: child!,
            ),
            home: Scaffold(
              body: SmartPlaylistsScreen(
                catalog: catalog,
                store: store,
                playback: playback,
                onPageChanged: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tapVisible(tester, find.byTooltip('New smart playlist'));
        await tester.enterText(field('Playlist name'), 'My recent mix');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        await tapVisible(
          tester,
          find.text('Date added: within the last 30 days'),
        );
        await tester.enterText(field('Value'), '0');
        await tapVisible(tester, find.text('Apply'));
        expect(find.text('Choose 1 to 3650 days.'), findsOneWidget);
        await tester.enterText(field('Value'), '7');
        await tapVisible(tester, find.text('Apply'));
        await tapVisible(tester, find.text('Add group').first);
        expect(find.text('Rule group'), findsOneWidget);
        await tapVisible(tester, find.text('Done'));
        if (const bool.fromEnvironment('CAPTURE_PREVIEWS')) {
          tester
              .state<ScrollableState>(
                find
                    .descendant(
                      of: find.byType(ListView).first,
                      matching: find.byType(Scrollable),
                    )
                    .first,
              )
              .position
              .jumpTo(0);
          await tester.pumpAndSettle();
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(
              '../build/previews/smart-rules-${size.width.toInt()}.png',
            ),
          );
        }
        await tapVisible(tester, find.text('Preview tracks'));
        expect(find.text('2 matched · 2 selected'), findsOneWidget);
        await tapVisible(tester, find.text('Play playlist'));
        expect(playback.queue.value.map((t) => t.id), ['old', 'new']);
        await tapVisible(tester, find.text('Mix'));
        await tapVisible(tester, find.text('Recently added · 60%'));
        await tester.enterText(field('Pool name'), 'New discoveries');
        await tapVisible(tester, find.text('Done'));
        await tapVisible(tester, find.text('Rules'));
        expect(find.text('Include'), findsOneWidget);
        await tapVisible(tester, find.text('Mix'));
        expect(find.text('New discoveries · 60%'), findsOneWidget);
        if (const bool.fromEnvironment('CAPTURE_PREVIEWS')) {
          tester
              .state<ScrollableState>(
                find
                    .descendant(
                      of: find.byType(ListView).first,
                      matching: find.byType(Scrollable),
                    )
                    .first,
              )
              .position
              .jumpTo(0);
          await tester.pumpAndSettle();
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(
              '../build/previews/smart-mix-${size.width.toInt()}.png',
            ),
          );
        }
        await tapVisible(tester, find.text('Preview tracks'));
        await tapVisible(tester, find.text('Play playlist'));
        expect(playback.queue.value.map((t) => t.id), ['new', 'old']);
        failSave = true;
        await tapVisible(tester, find.text('Save'));
        expect(find.byType(SmartPlaylistEditor), findsOneWidget);
        expect(store.items, isEmpty);
        failSave = false;
        await tapVisible(tester, find.text('Save'));
        expect(find.byType(SmartPlaylistEditor), findsNothing);
        expect(store.items.single.type, SmartPlaylistType.mix);
        expect(
          (store.items.single.include.children.first as SmartCondition).value,
          '7',
        );
        expect(store.items.single.include.children.last, isA<SmartGroup>());
        expect(store.items.single.pools.first.name, 'New discoveries');
        expect(find.text('My recent mix'), findsOneWidget);
        now = now.add(const Duration(minutes: 4));
        client.recordLocalListen(catalog.tracks.first, now);
        await tester.pumpAndSettle();
        expect(scans, 1);
        expect(playback.queue.value.map((t) => t.id), ['new', 'old']);
        await tapVisible(tester, find.byTooltip('Playlist options'));
        await tapVisible(tester, find.text('Edit configuration'));
        expect(find.text('New discoveries · 60%'), findsOneWidget);
        await tapVisible(tester, find.text('Rules'));
        await tapVisible(tester, find.text('Save'));
        expect(store.items.single.type, SmartPlaylistType.rules);
        expect(store.items.single.pools.first.name, 'New discoveries');
        expect(find.text('Rules · Latest activity'), findsOneWidget);
        await tapVisible(tester, find.byTooltip('Playlist options'));
        await tapVisible(tester, find.text('Delete'));
        await tapVisible(tester, find.text('Cancel'));
        expect(store.items, hasLength(1));
        await tapVisible(tester, find.byTooltip('Playlist options'));
        await tapVisible(tester, find.text('Delete'));
        await tapVisible(tester, find.text('Delete'));
        expect(store.items, isEmpty);
        expect(find.text('Smart playlists'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await playback.pause();
        await tester.pumpWidget(const SizedBox());
        catalog.dispose();
        await tester.pumpAndSettle();
      },
    );
  }
}
