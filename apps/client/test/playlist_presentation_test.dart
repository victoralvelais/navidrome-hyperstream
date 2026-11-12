import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:hyperstream_client/app_theme.dart';
import 'package:hyperstream_client/features/library/artwork_backdrop.dart';
import 'package:hyperstream_client/features/playlists/playlists_screen.dart';
import 'package:hyperstream_client/models/playlist_icon.dart';
import 'package:hyperstream_client/models/smart_playlist.dart';
import 'package:hyperstream_client/services/library_collections.dart';
import 'package:hyperstream_client/services/navidrome_client.dart';
import 'package:hyperstream_client/services/playlist_icon_store.dart';
import 'package:hyperstream_client/services/smart_playlist_store.dart';
import 'package:hyperstream_client/widgets/edge_back_gesture.dart';
import 'package:hyperstream_client/widgets/floating_chrome.dart';
import 'package:hyperstream_client/widgets/glass_surface.dart';

import 'support/collection_server.dart';

NavidromeClient client([String user = 'test']) => NavidromeClient(
  serverUrl: 'https://music.example.com',
  username: user,
  password: 'synthetic',
  httpClient: MockClient(CollectionServer().handle),
);

void main() {
  test('icon choices persist separately by account and failed writes preserve the prior icon', () async {
    final api = client();
    final other = client('other');
    addTearDown(api.close);
    addTearDown(other.close);
    final disk = <String, String>{};
    var fail = false;
    PlaylistIconStore store(NavidromeClient api) => PlaylistIconStore(
      api,
      read: (key) async => disk[key],
      write: (key, value) async {
        if (fail) throw StateError('disk');
        disk[key] = value;
      },
    );
    final first = store(api);
    expect(await first.setIcon('smart:a', PlaylistIcon.moon), isTrue);
    final restored = store(api);
    final second = store(other);
    await Future.wait([restored.load(), second.load()]);
    expect(restored.iconFor('smart:a'), PlaylistIcon.moon);
    expect(second.iconFor('smart:a'), PlaylistIcon.automatic);
    fail = true;
    expect(await restored.setIcon('smart:a', PlaylistIcon.bolt), isFalse);
    expect(restored.iconFor('smart:a'), PlaylistIcon.moon);
    fail = false;
    expect(await restored.setIcon('smart:a', PlaylistIcon.automatic), isTrue);
    expect(restored.iconFor('smart:a'), PlaylistIcon.automatic);
    for (final value in [first, restored, second]) {
      value.dispose();
    }
  });

  test('unreadable icon data is preserved and concurrent writes retain both choices', () async {
    final api = client();
    addTearDown(api.close);
    var writes = 0;
    final unreadable = PlaylistIconStore(
      api,
      read: (_) async => '{broken',
      write: (_, _) async {
        writes++;
      },
    );
    expect(await unreadable.setIcon('radio', PlaylistIcon.star), isFalse);
    expect(writes, 0);
    String? disk;
    final store = PlaylistIconStore(
      api,
      read: (_) async => null,
      write: (_, value) async => disk = value,
    );
    await Future.wait([
      store.setIcon('a', PlaylistIcon.moon),
      store.setIcon('b', PlaylistIcon.star),
    ]);
    expect(jsonDecode(disk!)['icons'], {'a': 'moon', 'b': 'star'});
    unreadable.dispose();
    store.dispose();
  });

  testWidgets(
    'one searchable list pins smart playlists and lets users pick and reset icons',
    (tester) async {
      final api = client();
      final collections = LibraryCollections(api);
      final smart = SmartPlaylistStore(
        api,
        read: (_) async => null,
        write: (_, _) async {},
      );
      final icons = PlaylistIconStore(
        api,
        read: (_) async => null,
        write: (_, _) async {},
      );
      await collections.refreshPlaylists();
      await smart.save(SmartPlaylistDefinition.initial('smart'));
      final name = smart.items.single.name;
      String? selected;
      await tester.pumpWidget(
        MaterialApp(
          theme: hyperstreamTheme(Brightness.dark),
          home: Scaffold(
            body: PlaylistsScreen(
              collections: collections,
              smartStore: smart,
              icons: icons,
              onSelected: (value) => selected = value.id,
              onSmartSelected: (value) => selected = value.id,
              onRecentRadio: () {},
              onNewSmartPlaylist: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Smart playlists'), findsNothing);
      expect(
        tester.getTopLeft(find.text(name)).dy,
        lessThan(tester.getTopLeft(find.text('Weekend')).dy),
      );
      expect(find.byIcon(Icons.auto_awesome_outlined), findsOneWidget);
      await tester.tap(find.byTooltip('New playlist'));
      await tester.pumpAndSettle();
      expect(find.byType(PopupMenuItem<String>), findsNWidgets(2));
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), name.toUpperCase());
      await tester.pumpAndSettle();
      expect(find.text('Weekend'), findsNothing);
      await tester.tap(find.text(name));
      expect(selected, 'smart');
      await tester.tap(find.byTooltip('Choose icon for $name'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Moon'));
      await tester.tap(find.text('Moon'));
      await tester.pumpAndSettle();
      expect(icons.iconFor('smart:smart'), PlaylistIcon.moon);
      await tester.tap(find.byTooltip('Choose icon for $name'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Default'));
      await tester.pumpAndSettle();
      expect(icons.iconFor('smart:smart'), PlaylistIcon.automatic);
      await tester.enterText(find.byType(TextField), 'missing');
      await tester.pumpAndSettle();
      expect(find.text('No matching playlists.'), findsOneWidget);
      await tester.tap(find.byTooltip('Clear playlist search'));
      await tester.pumpAndSettle();
      expect(find.text('Weekend'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      collections.dispose();
      smart.dispose();
      icons.dispose();
      api.close();
    },
  );

  testWidgets(
    'edge swipe backs once, while interior and vertical drags stay on the page',
    (tester) async {
      var backs = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: EdgeBackGesture(
            onBack: () => backs++,
            child: const Scaffold(body: SizedBox.expand()),
          ),
        ),
      );
      await tester.dragFrom(const Offset(12, 180), const Offset(100, 8));
      expect(backs, 1);
      await tester.dragFrom(const Offset(150, 180), const Offset(100, 8));
      await tester.dragFrom(const Offset(12, 180), const Offset(10, 120));
      await tester.dragFrom(const Offset(12, 180), const Offset(30, 0));
      expect(backs, 1);
    },
  );

  testWidgets('editor edge swipe honors the route unsaved-change guard', (
    tester,
  ) async {
    var blocked = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.push<void>(
              context,
              MenuPageRoute(
                builder: (_) => PopScope(
                  canPop: false,
                  onPopInvokedWithResult: (popped, _) {
                    if (!popped) blocked++;
                  },
                  child: const Scaffold(body: Text('Editing')),
                ),
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.dragFrom(const Offset(12, 180), const Offset(110, 0));
    await tester.pumpAndSettle();
    expect(blocked, 1);
    expect(find.text('Editing'), findsOneWidget);
  });

  testWidgets(
    'tab highlight contains both icon and label, top glass only spans a title',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                FloatingTopBar(
                  leading: IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.arrow_back),
                  ),
                  trailing: IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.add),
                  ),
                ),
                FloatingNavigation(selectedIndex: 1, onSelected: (_) {}),
              ],
            ),
          ),
        ),
      );
      final highlight = tester.getRect(
        find.byKey(const ValueKey('nav-highlight-1')),
      );
      expect(
        highlight.contains(tester.getCenter(find.text('Library'))),
        isTrue,
      );
      expect(
        highlight.contains(
          tester.getCenter(find.byIcon(Icons.library_music_rounded)),
        ),
        isTrue,
      );
      final cornerGlass = find.descendant(
        of: find.byType(FloatingTopBar),
        matching: find.byType(GlassSurface),
      );
      expect(cornerGlass, findsNWidgets(2));
      expect(tester.getSize(cornerGlass.first).width, lessThan(80));
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: FloatingTopBar(title: 'Playlists')),
        ),
      );
      expect(find.byType(GlassSurface), findsOneWidget);
      expect(tester.getSize(find.byType(GlassSurface)).width, greaterThan(600));
    },
  );

  test(
    'artwork palette favors cover colors over black margins and white text',
    () {
      final pixels = Uint8List.fromList([
        for (var i = 0; i < 80; i++) ...[0, 0, 0, 255],
        for (var i = 0; i < 20; i++) ...[255, 255, 255, 255],
        for (var i = 0; i < 10; i++) ...[220, 80, 60, 255],
      ]);
      expect(artworkAccent(pixels), const Color.fromARGB(255, 220, 80, 60));
      expect(artworkAccent(Uint8List.fromList([255, 0, 0, 0])), isNull);
    },
  );
}
