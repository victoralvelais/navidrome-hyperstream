import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:hyperstream_client/models/library.dart';
import 'package:hyperstream_client/models/smart_playlist.dart';
import 'package:hyperstream_client/services/library_catalog.dart';
import 'package:hyperstream_client/services/navidrome_client.dart';
import 'package:hyperstream_client/services/smart_playlist_publisher.dart';

import 'recent_radio_service_test.dart' show api, envelope;

class PublishFixture {
  final now = DateTime.utc(2026, 11, 13);
  final Map<String, List<String>> server = {};
  final Map<String, String> names = {};
  String? disk;
  int creates = 0, replaces = 0, writes = 0, reads = 0;
  int? failWriteAt;
  bool loseCreateResponse = false, loseUpdateResponse = false, truncate = false;
  bool readonly = false, incomplete = false;
  String owner = 'one';
  Completer<void>? createGate;
  void Function()? duringSave;
  late final NavidromeClient client = api((request) async {
    final parameters = request.method == 'POST'
        ? Uri(query: request.body).queryParametersAll
        : request.url.queryParametersAll;
    String? parameter(String name) => parameters[name]?.first;
    Map<String, dynamic> playlist(String id) => {
      'id': id,
      'name': names[id] ?? 'Server copy',
      'owner': owner,
      'readonly': readonly,
      'songCount': server[id]!.length + (incomplete ? 1 : 0),
      'entry': [
        for (final song in server[id]!) {'id': song, 'title': song},
      ],
    };
    if (request.url.path.contains('getPlaylists')) {
      return envelope({
        'playlists': {'playlist': server.keys.map(playlist).toList()},
      });
    }
    if (request.url.path.contains('getPlaylist')) {
      reads++;
      final id = parameter('id')!;
      if (!server.containsKey(id)) return http.Response('', 404);
      return envelope({'playlist': playlist(id)});
    }
    if (request.url.path.contains('createPlaylist')) {
      expect(request.method, 'POST');
      expect(
        request.url.query,
        isEmpty,
      ); // credentials and long sequences are in the form body
      final existing = parameter('playlistId');
      final id = existing ?? 'remote-${++creates}';
      if (existing != null) {
        replaces++;
        expect(parameter('name'), isNull);
      }
      final ids = parameters['songId'] ?? [];
      server[id] = truncate ? ids.take(1).toList() : [...ids];
      names.putIfAbsent(id, () => parameter('name')!);
      if (createGate != null) await createGate!.future;
      if ((existing == null && loseCreateResponse) ||
          (existing != null && loseUpdateResponse)) {
        return http.Response('', 503);
      }
      return envelope({'playlist': playlist(id)});
    }
    return envelope({});
  });
  late final catalog = LibraryCatalog(client, now: () => now)
    ..lastSyncedAt = now;
  late SmartPlaylistPublisher publisher = fresh();
  SmartPlaylistPublisher fresh() => SmartPlaylistPublisher(
    client,
    read: (_) async => disk,
    write: (_, value) async {
      writes++;
      if (writes == failWriteAt) throw StateError('disk');
      disk = value;
      duringSave?.call();
    },
  );
  SmartPlaylistResult result(List<String> ids) => SmartPlaylistResult(
    matches: [
      for (final id in ids) SmartMatch(Track.fromJson({'id': id}), 'All songs'),
    ],
    matchedCount: ids.length,
    contributions: [ids.length],
    scarce: false,
    evaluatedAt: now,
  );
  Future<MusicPlaylist> publish(
    List<String> ids, {
    bool separate = false,
    MusicPlaylist? reviewed,
  }) => publisher.publish(
    definitionId: 'smart',
    name: 'Smart copy',
    result: result(ids),
    catalog: catalog,
    separateCopy: separate,
    reviewed: reviewed,
  );
  void dispose() {
    publisher.dispose();
    catalog.dispose();
    client.close();
  }
}

void main() {
  test('create uses full ordered POST, preserves same-named playlists, reloads and replaces by ID', () async {
    final f = PublishFixture();
    addTearDown(f.dispose);
    f.server['manual'] = ['manual'];
    f.names['manual'] = 'Smart copy';
    final many = [for (var i = 0; i < 15000; i++) 'song-$i'];
    final created = await f.publish(many);
    expect(created.tracks.map((t) => t.id), many);
    expect(f.server['manual'], ['manual']);
    expect(f.publisher.link('smart')!.pendingIds, isNull);
    f.publisher.dispose();
    f.publisher = f.fresh();
    f.names[created.id] = 'Renamed in another client';
    await f.publish(['new-b', 'new-a']);
    expect(f.names[created.id], 'Renamed in another client');
    expect(f.publisher.link('smart')!.name, 'Renamed in another client');
    expect(f.creates, 1);
    expect(f.replaces, 1);
    expect(f.server[created.id], ['new-b', 'new-a']);
    await f.publish(['new-b', 'new-a']);
    expect(f.replaces, 1); // unchanged copy does not write to server
    expect(f.disk, isNot(contains('synthetic')));
  });

  test('outside edits stop writes; reviewed replacement rechecks, separate copy preserves manual edits', () async {
    final f = PublishFixture();
    addTearDown(f.dispose);
    final first = await f.publish(['a', 'b']);
    f.server[first.id] = ['manual'];
    await expectLater(
      f.publish(['c']),
      throwsA(isA<PlaylistPublishConflict>()),
    );
    expect(f.replaces, 0);
    final reviewed = await f.client.playlist(first.id);
    f.server[first.id] = ['changed-again'];
    await expectLater(
      f.publish(['c'], reviewed: reviewed),
      throwsA(isA<PlaylistPublishConflict>()),
    );
    expect(f.replaces, 0);
    await f.publish(['c'], reviewed: await f.client.playlist(first.id));
    expect(f.server[first.id], ['c']);
    f.server[first.id] = ['keep'];
    final other = await f.publish(['separate'], separate: true);
    expect(other.id, isNot(first.id));
    expect(f.server[first.id], ['keep']);
  });

  test('a change during local intent persistence is caught before server replacement', () async {
    final f = PublishFixture();
    addTearDown(f.dispose);
    final first = await f.publish(['a']);
    f.duringSave = () => f.server[first.id] = ['edited-during-save'];
    await expectLater(
      f.publish(['b']),
      throwsA(isA<PlaylistPublishConflict>()),
    );
    expect(f.replaces, 0);
  });

  test('failed create response survives restart and blocks duplicates until explicit ID recovery', () async {
    final f = PublishFixture();
    addTearDown(f.dispose);
    f.loseCreateResponse = true;
    await expectLater(
      f.publish(['a', 'b']),
      throwsA(isA<NavidromeException>()),
    );
    expect(f.publisher.link('smart')!.creationUncertain, isTrue);
    f.publisher.dispose();
    f.publisher = f.fresh();
    await expectLater(
      f.publish(['a', 'b']),
      throwsA(isA<PlaylistPublishException>()),
    );
    expect(f.creates, 1);
    f.server['wrong'] = ['other'];
    f.names['wrong'] = 'Smart copy';
    await expectLater(
      f.publisher.recover('smart', 'wrong'),
      throwsA(isA<PlaylistPublishException>()),
    );
    await f.publisher.recover('smart', 'remote-1');
    expect(f.publisher.link('smart')!.trackIds, ['a', 'b']);
    expect(f.creates, 1);
  });

  test('lost update response and failed final storage save recover by verifying, not resending', () async {
    final f = PublishFixture();
    addTearDown(f.dispose);
    await f.publish(['a']);
    f.loseUpdateResponse = true;
    await expectLater(f.publish(['b']), throwsA(isA<NavidromeException>()));
    expect(f.replaces, 1);
    f.publisher.dispose();
    f.publisher = f.fresh();
    await f.publish(['b']);
    expect(f.replaces, 1);
    f.loseUpdateResponse = false;
    f.failWriteAt =
        f.writes +
        2; // pending persists; server updates; final local save fails
    await expectLater(
      f.publish(['c']),
      throwsA(isA<PlaylistPublishException>()),
    );
    expect(f.server['remote-1'], ['c']);
    f.failWriteAt = null;
    await f.publish(['c']);
    expect(f.replaces, 2);
  });

  test('failed create ID persistence keeps in-memory ID and durable uncertainty after restart', () async {
    final f = PublishFixture();
    addTearDown(f.dispose);
    f.failWriteAt = 2;
    await expectLater(
      f.publish(['a']),
      throwsA(isA<PlaylistPublishException>()),
    );
    expect(f.publisher.link('smart')!.remoteId, 'remote-1');
    expect((jsonDecode(f.disk!)['links']['smart'] as Map)['remoteId'], isNull);
    f.failWriteAt = null;
    await f.publish(['a']);
    expect(f.creates, 1);
  });

  test('no remote writes after failed local intent, bad sync, empty results, wrong owner or readonly', () async {
    final f = PublishFixture();
    addTearDown(f.dispose);
    f.failWriteAt = 1;
    await expectLater(
      f.publish(['a']),
      throwsA(isA<PlaylistPublishException>()),
    );
    expect(f.creates, 0);
    f.failWriteAt = null;
    f.catalog.error = 'sync failed';
    await expectLater(
      f.publish(['a']),
      throwsA(isA<PlaylistPublishException>()),
    );
    f.catalog.error = null;
    f.catalog.loading = true;
    await expectLater(
      f.publish(['a']),
      throwsA(isA<PlaylistPublishException>()),
    );
    f.catalog.loading = false;
    await expectLater(f.publish([]), throwsA(isA<PlaylistPublishException>()));
    expect(f.creates, 0);
    await f.publish(['a']);
    f.owner = 'someone-else';
    await expectLater(
      f.publish(['b']),
      throwsA(isA<PlaylistPublishException>()),
    );
    f.owner = 'one';
    f.readonly = true;
    await expectLater(
      f.publish(['b']),
      throwsA(isA<PlaylistPublishException>()),
    );
    f.readonly = false;
    f.incomplete = true;
    await expectLater(
      f.publish(['b']),
      throwsA(isA<PlaylistPublishException>()),
    );
    expect(f.replaces, 0);
  });

  test('truncated server publication is never recorded as verified', () async {
    final f = PublishFixture();
    addTearDown(f.dispose);
    f.truncate = true;
    await expectLater(
      f.publish(['a', 'b']),
      throwsA(isA<PlaylistPublishConflict>()),
    );
    expect(f.publisher.link('smart')!.pendingIds, ['a', 'b']);
    expect(f.publisher.link('smart')!.trackIds, isEmpty);
  });

  test('duplicate actions are blocked and closing account prevents later verification or writes', () async {
    final f = PublishFixture();
    addTearDown(f.dispose);
    f.createGate = Completer();
    final first = f.publish(['a']);
    final failed = expectLater(first, throwsA(isA<PlaylistPublishException>()));
    await Future<void>.delayed(Duration.zero);
    await expectLater(
      f.publish(['a']),
      throwsA(isA<PlaylistPublishException>()),
    );
    expect(f.creates, 1);
    f.publisher.dispose();
    f.client.close();
    f.createGate!.complete();
    await failed;
    expect(f.reads, 0);
    expect(f.writes, 1);
  });

  test(
    'unknown storage is preserved and separate accounts have separate keys',
    () async {
      final f = PublishFixture();
      addTearDown(f.dispose);
      f.disk = '{"schemaVersion":2,"links":{}}';
      await expectLater(
        f.publish(['a']),
        throwsA(isA<PlaylistPublishException>()),
      );
      expect(f.writes, 0);
      expect(f.creates, 0);
      final other = api((_) => envelope({}), user: 'two');
      addTearDown(other.close);
      final publisher = SmartPlaylistPublisher(other);
      addTearDown(publisher.dispose);
      expect(publisher.storageKey, isNot(f.publisher.storageKey));
    },
  );
}
