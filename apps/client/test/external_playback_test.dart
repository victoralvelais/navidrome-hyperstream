import 'dart:io';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:just_audio/just_audio.dart';
import 'package:hyperstream_client/models/library.dart';
import 'package:hyperstream_client/models/source_reference.dart';
import 'package:hyperstream_client/services/navidrome_client.dart';
import 'package:hyperstream_client/services/playback_service.dart';
import 'package:hyperstream_client/services/playback_store.dart';
import 'package:hyperstream_client/services/music_sources.dart';

import 'support/fake_player.dart';

const externalSong = Track(
  id: 'external:source:one',
  title: 'Song',
  artist: 'Artist',
  album: 'Album',
  duration: Duration(minutes: 3),
  source: SourceReference(sourceId: 'source', trackId: 'one'),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'initial stream failure starts verification and resumes playback automatically',
    (tester) async {
      final sources = MusicSources.instance.extensions!;
      final client = NavidromeClient(
        serverUrl: 'https://library.example',
        username: 'user',
        password: 'private',
      );
      final player = FakePlayer()..failNextLoad = true;
      final verification = Completer<bool>();
      var prompts = 0;
      final playback = PlaybackService(
        player: player,
        sourceStreamUri: (_) => Uri.parse('http://127.0.0.1/synthetic'),
        verifySource: (_) {
          prompts++;
          return verification.future;
        },
      );
      addTearDown(() async {
        sources.issue.value = null;
        sources.verification.value = null;
        client.close();
        final disposing = playback.dispose();
        await tester.pump();
        await disposing;
      });
      sources.issue.value =
          'Tidal needs verification. Open Music sources and choose Verify.';
      sources.verification.value = 'tidal-web';
      await playback.playAlbum(client, [externalSong], 0);
      expect(player.currentIndex, isNull);
      expect(playback.trackAt(0), isNull);
      expect(playback.error.value, contains('Tidal needs verification'));
      expect(playback.reconnecting, false);
      expect(prompts, 1);
      player.errors.add(PlayerException(1, 'private', 0));
      await tester.pump(const Duration(minutes: 1));
      expect(player.loaded, hasLength(1));
      sources.issue.value = null;
      sources.verification.value = null;
      verification.complete(true);
      await tester.pumpAndSettle();
      expect(prompts, 1);
      expect(player.playing, true);
      expect(playback.error.value, isNull);
    },
  );

  for (final action in ['pause', 'new queue', 'cancel', 'challenge again']) {
    testWidgets('$action prevents unwanted verification playback retries', (
      tester,
    ) async {
      final sources = MusicSources.instance.extensions!;
      final client = NavidromeClient(
        serverUrl: 'https://library.example',
        username: 'user',
        password: 'private',
      );
      final player = FakePlayer()..failNextLoad = true;
      final verification = Completer<bool>();
      var prompts = 0;
      final playback = PlaybackService(
        player: player,
        sourceStreamUri: (_) => Uri.parse('http://127.0.0.1/synthetic'),
        verifySource: (_) {
          prompts++;
          return verification.future;
        },
      );
      addTearDown(() async {
        sources.issue.value = null;
        sources.verification.value = null;
        client.close();
        final disposing = playback.dispose();
        await tester.pump();
        await disposing;
      });
      sources.issue.value = 'Tidal needs verification to continue.';
      sources.verification.value = 'tidal-web';
      await playback.playAlbum(client, [externalSong], 0);
      if (action == 'pause') await playback.pause();
      if (action == 'new queue') {
        await playback.playAlbum(client, const [
          Track(
            id: 'library',
            title: 'Library',
            artist: 'Artist',
            album: 'Album',
            duration: Duration(minutes: 3),
          ),
        ], 0);
      }
      if (action == 'challenge again') player.failNextLoad = true;
      verification.complete(action != 'cancel');
      await tester.pumpAndSettle();
      await tester.pump(const Duration(minutes: 1));
      expect(prompts, 1);
      expect(player.playing, action == 'new queue');
      expect(
        player.loaded,
        hasLength(action == 'new queue' || action == 'challenge again' ? 2 : 1),
      );
      if (action == 'new queue') {
        expect(playback.mediaItem.value!.id, 'library');
      }
      await playback.pause();
    });
  }
  testWidgets(
    'external playback uses the shared player and never scrobbles to Navidrome',
    (tester) async {
      final calls = <String>[];
      final client = NavidromeClient(
        serverUrl: 'https://library.example',
        username: 'user',
        password: 'private',
        httpClient: MockClient((request) async {
          calls.add(request.url.path);
          return http.Response('{}', 200);
        }),
      );
      final player = FakePlayer();
      var elapsed = Duration.zero;
      final playback = PlaybackService(
        player: player,
        configureSession: (_) async {},
        listeningClock: () => elapsed,
        sourceStreamUri: (source) =>
            Uri.parse('https://source.example/track/${source.trackId}'),
      );
      addTearDown(() async {
        client.close();
        final disposing = playback.dispose();
        await tester.pump();
        await disposing;
      });
      await playback.playAlbum(client, [externalSong], 0);
      await tester.pump();
      expect(
        (player.loaded.single.single as UriAudioSource).uri.host,
        'source.example',
      );
      expect(playback.trackAt(0)!.source!.sourceId, 'source');
      for (var i = 0; i < 30; i++) {
        elapsed += const Duration(seconds: 4);
        player.emit();
        await tester.pump(const Duration(seconds: 4));
      }
      expect(calls, isEmpty);
      await playback.setSpeed(.75);
      await playback.pause();
      expect(player.speed, .75);
      expect(player.playing, isFalse);
      await playback.playAlbum(client, const [
        Track(
          id: 'library-song',
          title: 'Library',
          artist: 'Artist',
          album: 'Album',
          duration: Duration(minutes: 3),
        ),
      ], 0);
      expect(
        (player.loaded.last.single as UriAudioSource).uri.host,
        'library.example',
      );
      await playback.pause();
    },
  );

  test(
    'external queue roundtrip keeps stable IDs without resolved audio URLs',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'hyperstream-source-queue-',
      );
      final client = NavidromeClient(
        serverUrl: 'https://library.example',
        username: 'user',
        password: 'private',
      );
      try {
        final store = FilePlaybackStore(client, directory: () async => root);
        await store.write(
          const PlaybackSnapshot(
            tracks: [externalSong],
            coverArtIds: [null],
            index: 0,
            position: Duration(seconds: 30),
            speed: .75,
          ),
        );
        final restored = await FilePlaybackStore(
          client,
          directory: () async => root,
        ).read();
        expect(restored!.tracks.single.source!.trackId, 'one');
        expect(restored.position, const Duration(seconds: 30));
        final text = await File(
          '${root.path}/playback-v1/${store.accountKey}/queue.json',
        ).readAsString();
        expect(text, isNot(contains('https://')));
        expect(text, isNot(contains('private')));
      } finally {
        client.close();
        await root.delete(recursive: true);
      }
    },
  );
}
