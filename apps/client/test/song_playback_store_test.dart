import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyperstream_client/models/library.dart';
import 'package:hyperstream_client/models/source_reference.dart';
import 'package:hyperstream_client/services/navidrome_client.dart';
import 'package:hyperstream_client/services/song_playback_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

// This fake models mutable storage and controllable I/O failures.
// ignore: must_be_immutable
class _Storage extends Fake implements SharedPreferencesAsync {
  String? value;
  bool failRead = false;
  bool failWrite = false;
  int writes = 0;
  Completer<void>? writeGate;
  final writeStarted = Completer<void>();

  @override
  Future<String?> getString(String key) async {
    if (failRead) throw StateError('private read error');
    return value;
  }

  @override
  Future<void> setString(String key, String value) async {
    writes++;
    if (!writeStarted.isCompleted) writeStarted.complete();
    await writeGate?.future;
    if (failWrite) throw StateError('private write error');
    this.value = value;
  }
}

Track _track({
  String title = 'Track title',
  String id = 'catalog-song',
  SourceReference? source,
}) => Track(
  id: id,
  title: title,
  artist: 'Artist',
  album: 'Album',
  duration: const Duration(minutes: 3),
  source: source,
);

NavidromeClient _client({
  String server = 'https://music.example.test/library',
  String username = 'example-account',
  String password = 'example-password',
}) {
  final client = NavidromeClient(
    serverUrl: server,
    username: username,
    password: password,
  );
  addTearDown(client.close);
  return client;
}

void main() {
  const changed = SongPlaybackSettings(speed: .75, keepPitch: false);
  const defaults = SongPlaybackSettings();

  test('song identity uses normalized server, account, and source IDs', () {
    final client = _client();
    final key = SongPlaybackStore.keyFor(client, _track());
    expect(
      SongPlaybackStore.keyFor(
        _client(server: 'https://MUSIC.example.test/library/', password: 'new'),
        _track(title: 'Updated title'),
      ),
      key,
    );
    expect(
      SongPlaybackStore.keyFor(_client(username: 'other'), _track()),
      isNot(key),
    );
    expect(
      SongPlaybackStore.keyFor(
        _client(server: 'https://other.test/library'),
        _track(),
      ),
      isNot(key),
    );
    expect(SongPlaybackStore.keyFor(client, _track(id: 'other')), isNot(key));

    final externalKey = SongPlaybackStore.keyFor(
      client,
      _track(
        source: SourceReference(
          sourceId: 'provider-a',
          trackId: 'catalog-song',
          artwork: Uri.parse('https://art.example.test/old?token=abc'),
        ),
      ),
    );
    expect(externalKey, isNot(key));
    expect(
      SongPlaybackStore.keyFor(
        _client(username: 'other'),
        _track(
          id: 'new-local-id',
          source: SourceReference(
            sourceId: 'provider-a',
            trackId: 'catalog-song',
            artwork: Uri.parse('https://art.example.test/new?token=def'),
          ),
        ),
      ),
      externalKey,
    );
    expect(
      SongPlaybackStore.keyFor(
        client,
        _track(
          source: const SourceReference(
            sourceId: 'provider-b',
            trackId: 'catalog-song',
          ),
        ),
      ),
      isNot(externalKey),
    );
  });

  test(
    'in-flight writes serialize and a fresh store loads the final values',
    () async {
      final storage = _Storage()..writeGate = Completer<void>();
      final client = _client();
      final first = SongPlaybackStore.keyFor(client, _track());
      final second = SongPlaybackStore.keyFor(client, _track(id: 'other'));
      final store = await SongPlaybackStore.load(storage: storage);
      expect(store.get(first), defaults);
      final firstWrite = store.set(first, changed);
      await storage.writeStarted.future;
      final secondWrite = store.set(
        second,
        const SongPlaybackSettings(speed: 1.25),
      );
      final finalWrite = store.set(
        first,
        const SongPlaybackSettings(keepPitch: false),
      );
      expect(storage.writes, 1);
      storage.writeGate!.complete();
      await Future.wait([firstWrite, secondWrite, finalWrite, store.flush()]);
      expect(storage.writes, 2);
      final payload = jsonDecode(storage.value!) as Map<String, dynamic>;
      expect(payload['songs'], {
        first: {'speed': 1, 'keepPitch': false},
        second: {'speed': 1.25, 'keepPitch': true},
      });
      for (final key in (payload['songs'] as Map<String, dynamic>).keys) {
        expect(key, matches(r'^[a-f0-9]{64}$'));
      }
      final reloaded = await SongPlaybackStore.load(storage: storage);
      expect(reloaded.get(first), const SongPlaybackSettings(keepPitch: false));
      expect(reloaded.get(second), const SongPlaybackSettings(speed: 1.25));
      await reloaded.set(first, defaults);
      expect(
        (await SongPlaybackStore.load(storage: storage)).get(first),
        defaults,
      );
    },
  );

  for (final failRead in [false, true]) {
    test('preserves unread data when read throws = $failRead', () async {
      final storage = _Storage()
        ..value = '{invalid stored data}'
        ..failRead = failRead;
      final store = await SongPlaybackStore.load(storage: storage);
      final key = SongPlaybackStore.keyFor(_client(), _track());
      expect(store.get(key), defaults);
      expect(store.notice, isNotNull);
      expect(store.notice, isNot(contains('private read error')));
      await store.set(key, changed);
      await store.flush();
      expect(store.get(key), changed);
      expect(storage.writes, 0);
      expect(storage.value, '{invalid stored data}');
    });
  }

  test(
    'a failed write keeps the session edits, then a later write saves them',
    () async {
      final storage = _Storage()..failWrite = true;
      final store = await SongPlaybackStore.load(storage: storage);
      final client = _client();
      final first = SongPlaybackStore.keyFor(client, _track());
      final second = SongPlaybackStore.keyFor(client, _track(id: 'other'));
      await store.set(first, changed);
      expect(store.get(first), changed);
      expect(store.notice, isNotNull);
      expect(store.notice, isNot(contains('private write error')));
      storage.failWrite = false;
      await store.set(second, changed);
      expect(store.notice, isNull);
      final reloaded = await SongPlaybackStore.load(storage: storage);
      expect(reloaded.get(first), changed);
      expect(reloaded.get(second), changed);
    },
  );
}
