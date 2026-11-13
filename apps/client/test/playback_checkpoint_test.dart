import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyperstream_client/services/navidrome_client.dart';
import 'package:hyperstream_client/services/playback_service.dart';
import 'package:hyperstream_client/services/playback_store.dart';

import 'playback_continuity_test.dart'
    show MemoryPlaybackStore, continuityTracks;
import 'support/fake_player.dart';

class ObservedCheckpointStore extends MemoryPlaybackStore {
  final checkpoint = Completer<void>();
  @override
  Future<void> write(PlaybackSnapshot snapshot) async {
    await super.write(snapshot);
    if (snapshot.position == const Duration(seconds: 29) &&
        !checkpoint.isCompleted) {
      checkpoint.complete();
    }
  }
}

void main() {
  test('playing position checkpoints without a UI action', () async {
    final store = ObservedCheckpointStore();
    final player = FakePlayer();
    final playback = PlaybackService(
      player: player,
      playbackStore: (_) => store,
    );
    final client = NavidromeClient(
      serverUrl: 'https://example.test',
      username: 'user',
      password: 'synthetic',
    );
    addTearDown(() async {
      await playback.dispose();
      client.close();
    });
    await playback.attachAccount(client, remember: true);
    await playback.playAlbum(client, continuityTracks, 0);
    await playback.savePlayback();
    player.position = const Duration(seconds: 29);
    // Observe the checkpoint itself; wall-clock sleeps can race timer callbacks
    // when the full suite saturates the host. No UI/state event triggers this.
    await store.checkpoint.future.timeout(const Duration(seconds: 20));
    expect(store.value!.position, const Duration(seconds: 29));
  });
}
