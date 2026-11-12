import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:hyperstream_client/models/library.dart';
import 'package:hyperstream_client/services/catalog_cache.dart';
import 'package:hyperstream_client/services/recent_radio_service.dart';

import 'recent_radio_service_test.dart' as fixtures;

class MemoryCatalogCache implements CatalogCache {
  CatalogSnapshot? saved;
  Completer<CatalogSnapshot?>? readGate;
  int writes = 0;
  @override
  Future<CatalogSnapshot?> read() async =>
      readGate == null ? saved : readGate!.future;
  @override
  Future<void> write(CatalogSnapshot snapshot) async {
    writes++;
    saved = snapshot;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime.utc(2026, 11, 12, 14);
  final song = Track(
    id: 'a',
    title: 'A',
    artist: 'Artist',
    album: 'Album',
    duration: const Duration(milliseconds: 123456),
    number: 7,
    coverArt: 'cover',
    starred: true,
    addedAt: now.subtract(const Duration(days: 60)),
    lastPlayedAt: now.subtract(const Duration(minutes: 15)),
    playCount: 8,
    invalidActivityDates: true,
    albumId: 'album',
    artistId: 'artist',
    container: 'mp3',
    bitRate: 320,
    userRating: 4,
  );
  CatalogSnapshot snapshot(DateTime time) =>
      CatalogSnapshot(syncedAt: time, tracks: [song]);

  test(
    'atomic file cache preserves track data and isolates server, path and user',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'hyperstream-catalog-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final client = fixtures.api((_) => http.Response('', 500));
      addTearDown(client.close);
      final cache = FileCatalogCache(client, directory: () async => directory);
      final data = CatalogSnapshot(
        syncedAt: now,
        syncedTrackCount: 0, // This track arrived locally after an empty scan.
        tracks: [song],
        listens: {'a': CachedListen(now, 9)},
        favorites: {'a': false},
      );
      await cache.write(data);
      final restored = (await cache.read())!;
      expect(restored.syncedTrackCount, 0);
      final track = restored.tracks.single;
      expect(track.id, song.id);
      expect(track.duration, song.duration);
      expect(track.audioDetails, song.audioDetails);
      expect(track.starred, true);
      expect(track.playCount, 8);
      expect(track.lastPlayedAt, song.lastPlayedAt);
      expect(track.addedAt, song.addedAt);
      expect(track.invalidActivityDates, true);
      expect(track.albumId, 'album');
      expect(track.artistId, 'artist');
      expect(track.userRating, 4);
      expect(track.coverArt, 'cover');
      expect(track.number, 7);
      expect(restored.listens['a']!.minimumCount, 9);
      expect(restored.favorites, {'a': false});
      final keys = {cache.accountKey};
      for (final variant in [
        fixtures.api((_) => http.Response('', 500), user: 'two'),
        fixtures.api(
          (_) => http.Response('', 500),
          url: 'https://other.example.com/',
        ),
        fixtures.api(
          (_) => http.Response('', 500),
          url: 'https://music.example.com/sub/',
        ),
      ]) {
        addTearDown(variant.close);
        final other = FileCatalogCache(
          variant,
          directory: () async => directory,
        );
        expect(await other.read(), isNull);
        keys.add(other.accountKey);
      }
      expect(keys, hasLength(4));
      final file = File(
        '${directory.path}/catalog-v1/${cache.accountKey}.json',
      );
      final raw = await file.readAsString();
      for (final secret in [
        'synthetic',
        'password',
        'https://',
        'stream.view',
      ]) {
        expect(raw, isNot(contains(secret)));
      }
      // Replacement of an existing file works on Windows too; readers see the
      // last serialized write even if a prior screen's save is still running.
      final writing = cache.write(CatalogSnapshot(syncedAt: now, tracks: []));
      expect((await cache.read())!.tracks, isEmpty);
      await writing;
      await file.writeAsString('{broken');
      expect(await cache.read(), isNull);
      await file.writeAsString('{"schemaVersion": 2}');
      expect(await cache.read(), isNull);
    },
  );

  testWidgets(
    'fresh cache opens without network and syncs at the saved deadline',
    (tester) async {
      final time = tester.binding.clock.now().toUtc();
      var calls = 0;
      final client = fixtures.api((_) {
        calls++;
        return fixtures.envelope({'searchResult3': {}});
      });
      final cache = MemoryCatalogCache()..saved = snapshot(time);
      final service = RecentRadioService(
        client,
        now: tester.binding.clock.now,
        cache: cache,
      );
      service.ensureLoaded();
      await tester.pump();
      expect(service.tracks, hasLength(1));
      expect(service.loading, false);
      expect(calls, 0);
      await tester.pump(const Duration(minutes: 29));
      service.ensureLoaded();
      await tester.pump();
      expect(calls, 0);
      await tester.pump(const Duration(minutes: 1));
      expect(calls, 1);
      expect(service.tracks, isEmpty); // Completed scans reconcile deletions.
      expect(cache.saved!.tracks, isEmpty);
      service.dispose();
      client.close();
    },
  );

  testWidgets('stale cache is usable during a slow or failed background scan', (
    tester,
  ) async {
    final time = tester.binding.clock.now().toUtc();
    final gate = Completer<http.Response>();
    final client = fixtures.api((_) => gate.future);
    final cache = MemoryCatalogCache()
      ..saved = snapshot(time.subtract(const Duration(hours: 1)));
    final service = RecentRadioService(
      client,
      now: tester.binding.clock.now,
      cache: cache,
    );
    var opened = false;
    service.ensureLoaded().then((_) => opened = true);
    await tester.pump();
    expect(opened, true);
    expect(service.tracks.single.id, 'a');
    await tester.pump(
      const Duration(milliseconds: 1),
    ); // Run the overdue timer.
    expect(service.loading, true);
    gate.complete(http.Response('', 500));
    await tester.pump();
    expect(service.error, isNotNull);
    expect(service.tracks.single.id, 'a');
    expect(cache.writes, 0);
    service.dispose();
    client.close();
  });

  test(
    'listens persist across restarts and survive a server history lag',
    () async {
      var calls = 0;
      final client = fixtures.api((request) {
        calls++;
        return fixtures.envelope({
          'searchResult3': {
            'song': request.url.queryParameters['songOffset'] == '0'
                ? [
                    {...fixtures.song('a'), 'playCount': 8},
                  ]
                : [],
          },
        });
      });
      addTearDown(client.close);
      final cache = MemoryCatalogCache()..saved = snapshot(now);
      final first = RecentRadioService(client, now: () => now, cache: cache);
      await first.ensureLoaded();
      client.recordLocalListen(song, now);
      await Future<void>.delayed(Duration.zero);
      expect(first.tracks.single.playCount, 9);
      expect(first.tracks.single.lastPlayedAt, now);
      expect(calls, 0);
      await first.flushCache();
      first.dispose();
      final second = RecentRadioService(client, now: () => now, cache: cache);
      addTearDown(second.dispose);
      await second.ensureLoaded();
      expect(second.preview!.matches.first.track.lastPlayedAt, now);
      expect(second.tracks.single.playCount, 9);
      await second.refresh();
      expect(second.tracks.single.lastPlayedAt, now);
      expect(second.tracks.single.playCount, 9);
    },
  );

  test(
    'listens persist even when the account never opens a playlist page',
    () async {
      var calls = 0;
      final client = fixtures.api((_) {
        calls++;
        return http.Response('', 500);
      });
      addTearDown(client.close);
      final cache = MemoryCatalogCache()..saved = snapshot(now);
      final first = RecentRadioService(client, now: () => now, cache: cache);
      await Future<void>.delayed(
        Duration.zero,
      ); // Account restore, no ensureLoaded.
      client.recordLocalListen(song, now);
      await Future<void>.delayed(Duration.zero);
      first.dispose(); // Flush the local update when leaving the account.
      await Future<void>.delayed(Duration.zero);
      final reopened = RecentRadioService(client, now: () => now, cache: cache);
      addTearDown(reopened.dispose);
      await reopened.ensureLoaded();
      expect(reopened.tracks.single.lastPlayedAt, now);
      expect(reopened.tracks.single.playCount, 9);
      expect(calls, 0);
    },
  );

  test('listen during restore wins over cached history; disposal blocks late restore', () async {
    final client = fixtures.api((_) => http.Response('', 500));
    addTearDown(client.close);
    final cache = MemoryCatalogCache()
      ..readGate = Completer<CatalogSnapshot?>();
    final service = RecentRadioService(client, now: () => now, cache: cache);
    final opening = service.ensureLoaded();
    client.recordLocalListen(song, now);
    await Future<void>.delayed(Duration.zero);
    cache.readGate!.complete(snapshot(now));
    await opening;
    expect(service.tracks.single.lastPlayedAt, now);
    await service.flushCache();
    service.dispose();
    final nextCache = MemoryCatalogCache()
      ..readGate = Completer<CatalogSnapshot?>();
    final next = RecentRadioService(client, now: () => now, cache: nextCache);
    final pending = next.ensureLoaded();
    next.dispose();
    nextCache.readGate!.complete(snapshot(now));
    await pending;
    expect(next.revision, 0);
  });
}
