import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyperstream_client/models/smart_playlist.dart';
import 'package:hyperstream_client/services/smart_playlist_store.dart';

import 'recent_radio_service_test.dart' show api, envelope;

void main() {
  test('legacy definitions migrate on write and reshuffle survives reload and failed saves', () async {
    final client = api((_) => envelope({}));
    addTearDown(client.close);
    var fail = false;
    var writes = 0;
    final legacy = SmartPlaylistDefinition.initial('a').toJson()
      ..['schemaVersion'] = 1
      ..remove('artistGap')
      ..remove('relaxArtistGap')
      ..remove('shuffleSeed');
    var raw = jsonEncode({
      'schemaVersion': 1,
      'playlists': [legacy],
    });
    final original = raw;
    SmartPlaylistStore open() => SmartPlaylistStore(
      client,
      read: (_) async => raw,
      write: (_, value) async {
        writes++;
        if (fail) throw StateError('disk');
        raw = value;
      },
    );
    final store = open();
    addTearDown(store.dispose);
    await store.load();
    expect(raw, original);
    expect(writes, 0);
    expect(store.items.single.artistGap, 0);
    final edited = SmartPlaylistDefinition.fromJson({
      ...store.items.single.toJson(),
      'artistGap': 3,
      'relaxArtistGap': false,
      'order': 'stableShuffle',
    });
    await store.save(edited);
    expect(await store.reshuffle('a'), isTrue);
    expect(store.items.single.shuffleSeed, 1);
    fail = true;
    expect(await store.reshuffle('a'), isFalse);
    expect(store.items.single.shuffleSeed, 1);
    fail = false;
    final results = await Future.wait([
      store.reshuffle('a'),
      store.reshuffle('a'),
    ]);
    expect(results, [true, true]);
    expect(store.items.single.shuffleSeed, 3);
    final reopened = open();
    addTearDown(reopened.dispose);
    await reopened.load();
    expect(reopened.items.single.toJson(), store.items.single.toJson());
    await Future.wait([reopened.remove('a'), reopened.reshuffle('a')]);
    expect(reopened.items, isEmpty);
  });

  test('definitions persist separately by server and user, across reload and deletion', () async {
    final clients = [
      api((_) => envelope({})),
      api((_) => envelope({}), user: 'two'),
      api((_) => envelope({}), url: 'https://second.example.com'),
    ];
    final disk = <String, String>{};
    SmartPlaylistStore store(int i) => SmartPlaylistStore(
      clients[i],
      read: (key) async => disk[key],
      write: (key, value) async {
        disk[key] = value;
      },
    );
    final first = store(0), second = store(1), third = store(2);
    addTearDown(() {
      for (final client in clients) {
        client.close();
      }
      first.dispose();
      second.dispose();
      third.dispose();
    });
    expect({
      first.storageKey,
      second.storageKey,
      third.storageKey,
    }, hasLength(3));
    expect(await first.save(SmartPlaylistDefinition.initial('a')), isTrue);
    expect(await first.save(SmartPlaylistDefinition.initial('b')), isTrue);
    await second.load();
    await third.load();
    expect(second.items, isEmpty);
    expect(third.items, isEmpty);
    final reopened = store(0);
    addTearDown(reopened.dispose);
    await reopened.load();
    expect(reopened.items.map((d) => d.id), ['a', 'b']);
    expect(await reopened.remove('a'), isTrue);
    expect(
      (jsonDecode(disk[first.storageKey]!)['playlists'] as List).length,
      1,
    );
  });
  test(
    'malformed or newer saved data is preserved and blocks overwrite',
    () async {
      final client = api((_) => envelope({}));
      addTearDown(client.close);
      for (final raw in ['broken', '{"schemaVersion":2,"playlists":[]}']) {
        var writes = 0;
        final store = SmartPlaylistStore(
          client,
          read: (_) async => raw,
          write: (_, _) async {
            writes++;
          },
        );
        await store.load();
        expect(store.canWrite, isFalse);
        expect(await store.save(SmartPlaylistDefinition.initial('a')), isFalse);
        expect(writes, 0);
        expect(store.error, contains('preserved'));
        store.dispose();
      }
    },
  );
  test(
    'failed writes preserve saved definitions and a retry succeeds',
    () async {
      final client = api((_) => envelope({}));
      addTearDown(client.close);
      var fail = false;
      final store = SmartPlaylistStore(
        client,
        read: (_) async => null,
        write: (_, _) async {
          if (fail) throw StateError('disk unavailable');
        },
      );
      addTearDown(store.dispose);
      await store.save(SmartPlaylistDefinition.initial('a'));
      fail = true;
      expect(await store.save(SmartPlaylistDefinition.initial('b')), isFalse);
      expect(store.items.map((d) => d.id), ['a']);
      fail = false;
      expect(await store.save(SmartPlaylistDefinition.initial('b')), isTrue);
      expect(store.items.map((d) => d.id), ['a', 'b']);
      expect(store.error, isNull);
    },
  );
  test(
    'concurrent saves serialize and disposal prevents late publication',
    () async {
      final client = api((_) => envelope({}));
      addTearDown(client.close);
      final gate = Completer<void>();
      var writes = 0;
      final store = SmartPlaylistStore(
        client,
        read: (_) async => null,
        write: (_, _) async {
          if (++writes == 1) await gate.future;
        },
      );
      final a = store.save(SmartPlaylistDefinition.initial('a'));
      final b = store.save(SmartPlaylistDefinition.initial('b'));
      await Future<void>.delayed(Duration.zero);
      expect(writes, 1);
      gate.complete();
      expect(await a, isTrue);
      expect(await b, isTrue);
      expect(store.items.map((d) => d.id), ['a', 'b']);
      store.dispose();
      final read = Completer<String?>();
      final disposed = SmartPlaylistStore(
        client,
        read: (_) => read.future,
        write: (_, _) async {
          fail('write after disposal');
        },
      );
      final pending = disposed.save(SmartPlaylistDefinition.initial('c'));
      disposed.dispose();
      read.complete(null);
      expect(await pending, isFalse);
    },
  );
}
