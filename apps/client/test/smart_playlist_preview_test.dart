import 'package:flutter_test/flutter_test.dart';
import 'package:hyperstream_client/models/library.dart';
import 'package:hyperstream_client/models/smart_playlist.dart';
import 'package:hyperstream_client/services/library_catalog.dart';
import 'package:hyperstream_client/services/smart_playlist_preview.dart';

import 'recent_radio_service_test.dart' show api, envelope;

void main() {
  test('listening and acknowledged favorites update previews without scans; sync reconciles counts', () async {
    var now = DateTime.utc(2026, 11, 11, 18);
    var scans = 0;
    var remoteCount = 0;
    DateTime? remotePlayed;
    var remoteFavorite = false;
    final client = api((request) {
      if (!request.url.path.contains('search3')) return envelope({});
      final first = request.url.queryParameters['songOffset'] == '0';
      if (first) scans++;
      return envelope({
        'searchResult3': {
          'song': first
              ? [
                  {
                    'id': 'a',
                    'created': '2026-01-01T00:00:00Z',
                    'playCount': remoteCount,
                    if (remotePlayed != null)
                      'played': remotePlayed.toIso8601String(),
                    if (remoteFavorite) 'starred': '2026-11-11T00:00:00Z',
                  },
                ]
              : [],
        },
      });
    });
    final catalog = LibraryCatalog(client, now: () => now);
    final preview = SmartPlaylistPreview(catalog);
    addTearDown(() {
      preview.dispose();
      catalog.dispose();
      client.close();
    });
    final rules = SmartPlaylistDefinition.initial('a');
    await preview.update(rules);
    expect(preview.result, isNull);
    await catalog.ensureLoaded();
    expect(preview.result!.matches, isEmpty);
    final old = catalog.tracks.single;
    client.recordLocalListen(old, now);
    await Future<void>.delayed(Duration.zero);
    expect(catalog.tracks.single.playCount, 1);
    expect(preview.result!.matches.single.track.id, 'a');
    final firstListen = now;
    now = now.add(const Duration(minutes: 4));
    client.recordLocalListen(old, now);
    client.recordLocalListen(
      old,
      now,
    ); // Duplicate event is not another listen.
    await Future<void>.delayed(Duration.zero);
    expect(catalog.tracks.single.playCount, 2);
    await client.setFavorite('a', album: false, favorite: true);
    await Future<void>.delayed(Duration.zero);
    expect(catalog.tracks.single.starred, isTrue);
    expect(scans, 1);
    remoteCount = 1;
    remotePlayed = firstListen;
    await catalog.refresh();
    expect(catalog.tracks.single.playCount, 2);
    expect(catalog.tracks.single.lastPlayedAt, now);
    expect(catalog.tracks.single.starred, isTrue);
    remoteCount = 2;
    remotePlayed = now;
    remoteFavorite = true;
    await catalog.refresh();
    expect(catalog.tracks.single.playCount, 2); // Never add local counts twice.
    remoteCount = 3;
    await catalog.refresh();
    expect(catalog.tracks.single.playCount, 3);
    await catalog.ensureLoaded();
    expect(scans, 4);
  });
  test('large catalog evaluates off-thread; superseded definitions cannot replace newer results', () async {
    final client = api((_) => envelope({}));
    final catalog = LibraryCatalog(client);
    final preview = SmartPlaylistPreview(catalog);
    addTearDown(() {
      preview.dispose();
      catalog.dispose();
      client.close();
    });
    final now = DateTime.now().toUtc();
    catalog.lastSyncedAt = now;
    catalog.tracks = List.generate(
      6000,
      (i) => Track(
        id: '$i',
        title: '$i',
        artist: 'Artist',
        album: 'Album',
        duration: const Duration(minutes: 3),
        addedAt: now,
      ),
    );
    final initial = SmartPlaylistDefinition.initial('a');
    final empty = SmartPlaylistDefinition.fromJson({
      ...initial.toJson(),
      'include': SmartGroup(all: false).toJson(),
    });
    final first = preview.update(initial);
    final second = preview.update(empty);
    await Future.wait([first, second]);
    expect(preview.result!.matches, isEmpty);
    expect(preview.busy, isFalse);
    expect(preview.error, isNull);
    final third = preview.update(initial);
    preview.clear();
    await third;
    expect(preview.result, isNull);
  });
}
