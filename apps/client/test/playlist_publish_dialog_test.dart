import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperstream_client/app_theme.dart';
import 'package:hyperstream_client/features/playlists/playlist_publish_dialog.dart';
import 'package:hyperstream_client/models/library.dart';
import 'package:hyperstream_client/models/smart_playlist.dart';

import 'smart_playlist_publisher_test.dart' show PublishFixture;
import 'smart_playlist_screen_test.dart' show tapVisible;

void main() {
  for (final width in [320.0, 1280.0]) {
    testWidgets(
      'publish, cancel, review conflict and preserve edits at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final f = PublishFixture();
        addTearDown(f.dispose);
        MusicPlaylist? published;
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
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    published = await showDialog<MusicPlaylist>(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => PlaylistPublishDialog(
                        publisher: f.publisher,
                        definition: SmartPlaylistDefinition.initial('smart'),
                        result: f.result(['a', 'b']),
                        catalog: f.catalog,
                      ),
                    );
                  },
                  child: const Text('Open publisher'),
                ),
              ),
            ),
          ),
        );
        await tapVisible(tester, find.text('Open publisher'));
        await tapVisible(tester, find.text('Cancel'));
        expect(f.creates, 0);
        await tapVisible(tester, find.text('Open publisher'));
        await tapVisible(tester, find.text('Create server copy'));
        expect(published!.tracks.map((t) => t.id), ['a', 'b']);
        expect(f.creates, 1);
        f.server[published!.id] = ['manual', 'edit'];
        await tapVisible(tester, find.text('Open publisher'));
        await tapVisible(tester, find.text('Update server copy'));
        expect(find.text('Replace reviewed copy'), findsOneWidget);
        await tapVisible(tester, find.text('Keep server edits'));
        expect(f.server['remote-1'], ['manual', 'edit']);
        expect(f.replaces, 0);
        await tapVisible(tester, find.text('Open publisher'));
        await tapVisible(tester, find.text('Update server copy'));
        await tapVisible(tester, find.text('Replace reviewed copy'));
        expect(f.server['remote-1'], ['a', 'b']);
        expect(f.replaces, 1);
        await tapVisible(tester, find.text('Open publisher'));
        await tapVisible(tester, find.text('Create separate copy'));
        expect(find.text('Create a separate copy?'), findsOneWidget);
        await tapVisible(tester, find.text('Cancel').last);
        expect(f.creates, 1);
        await tapVisible(tester, find.text('Cancel'));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'uncertain create exposes verification instead of a blind retry',
    (tester) async {
      final f = PublishFixture();
      addTearDown(f.dispose);
      f.loseCreateResponse = true;
      await tester.pumpWidget(
        MaterialApp(
          theme: hyperstreamTheme(Brightness.dark),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<MusicPlaylist>(
                  context: context,
                  builder: (_) => PlaylistPublishDialog(
                    publisher: f.publisher,
                    definition: SmartPlaylistDefinition.initial('smart'),
                    result: f.result(['a', 'b']),
                    catalog: f.catalog,
                  ),
                ),
                child: const Text('Publish'),
              ),
            ),
          ),
        ),
      );
      await tapVisible(tester, find.text('Publish'));
      await tapVisible(tester, find.text('Create server copy'));
      expect(f.creates, 1);
      expect(find.text('Create server copy'), findsNothing);
      await tapVisible(tester, find.text('Check existing copies'));
      await tapVisible(
        tester,
        find.widgetWithText(ListTile, 'My smart playlist'),
      );
      expect(find.byType(PlaylistPublishDialog), findsNothing);
      expect(f.publisher.link('smart')!.remoteId, 'remote-1');
      expect(f.creates, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
