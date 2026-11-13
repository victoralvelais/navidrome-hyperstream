import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyperstream_client/services/navidrome_client.dart';
import 'package:hyperstream_client/services/playback_store.dart';

import 'playback_continuity_test.dart' show savedQueue;

void main() {
  late Directory directory;
  late NavidromeClient client;
  late FilePlaybackStore store;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'hyperstream-playback-test-',
    );
    client = NavidromeClient(
      serverUrl: 'https://example.test/music',
      username: 'user',
      password: 'must-not-be-stored',
    );
    store = FilePlaybackStore(client, directory: () async => directory);
  });
  tearDown(() async {
    client.close();
    await directory.delete(recursive: true);
  });
  File queueFile() =>
      File('${directory.path}/playback-v1/${store.accountKey}/queue.json');
  File positionFile() =>
      File('${directory.path}/playback-v1/${store.accountKey}/position.json');

  test('atomic queue/checkpoint roundtrip preserves duplicates without auth or URLs', () async {
    final queue = savedQueue(index: 2, order: [1, 2, 0]);
    await store.write(queue);
    final raw = await queueFile().readAsString();
    expect(raw, isNot(contains('must-not-be-stored')));
    expect(raw, isNot(contains('https://')));
    expect(raw, isNot(contains('stream.view')));
    final read = await FilePlaybackStore(
      client,
      directory: () async => directory,
    ).read();
    expect(read!.tracks.map((e) => e.id), ['one', 'two', 'one']);
    expect(read.index, 2);
    expect(read.shuffleOrder, [1, 2, 0]);
    expect(read.position, const Duration(seconds: 47));
    expect(await File('${queueFile().path}.tmp').exists(), isFalse);
    await store.clear();
    expect(await store.read(), isNull);
  });

  test('position updates do not rewrite large queues and stale checkpoints are ignored', () async {
    final queue = savedQueue();
    await store.write(queue);
    final raw = await queueFile().readAsString();
    await store.write(
      PlaybackSnapshot(
        tracks: queue.tracks,
        coverArtIds: queue.coverArtIds,
        index: 2,
        position: const Duration(seconds: 76),
      ),
    );
    expect(await queueFile().readAsString(), raw);
    expect((await store.read())!.position, const Duration(seconds: 76));
    final stale =
        jsonDecode(await positionFile().readAsString()) as Map<String, dynamic>;
    stale['generation'] = 'different-queue';
    await positionFile().writeAsString(jsonEncode(stale));
    final read = await store.read();
    expect(read!.index, 1);
    expect(read.position, const Duration(seconds: 47));
  });

  test(
    'corrupt checkpoint falls back; unknown queue schema stays untouched',
    () async {
      await store.write(savedQueue());
      await positionFile().writeAsString('{broken');
      expect((await store.read())!.index, 1);
      final raw =
          jsonDecode(await queueFile().readAsString()) as Map<String, dynamic>;
      raw['schemaVersion'] = 99;
      final futureData = jsonEncode(raw);
      await queueFile().writeAsString(futureData);
      await expectLater(store.read(), throwsFormatException);
      expect(await queueFile().readAsString(), futureData);
    },
  );

  test('same track IDs on another account cannot restore this queue', () async {
    await store.write(savedQueue());
    final other = NavidromeClient(
      serverUrl: 'https://example.test/music',
      username: 'different',
      password: 'password',
    );
    addTearDown(other.close);
    final separate = FilePlaybackStore(other, directory: () async => directory);
    expect(separate.accountKey, isNot(store.accountKey));
    expect(await separate.read(), isNull);
  });

  test('invalid shuffle permutations and positions are rejected', () async {
    await expectLater(
      store.write(savedQueue(order: [0, 0, 2])),
      throwsFormatException,
    );
    await expectLater(store.write(savedQueue(index: 9)), throwsFormatException);
    expect(savedQueue().safePosition, const Duration(seconds: 47));
    final completed = PlaybackSnapshot(
      tracks: savedQueue().tracks,
      coverArtIds: savedQueue().coverArtIds,
      index: 1,
      position: const Duration(minutes: 3),
    );
    expect(completed.safePosition, Duration.zero);
  });
}
