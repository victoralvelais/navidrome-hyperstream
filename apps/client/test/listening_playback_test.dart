import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyperstream_client/models/library.dart';
import 'package:hyperstream_client/services/navidrome_client.dart';
import 'package:hyperstream_client/services/playback_service.dart';
import 'package:just_audio/just_audio.dart';

import 'support/fake_player.dart';

class RecordingClient extends NavidromeClient {
  RecordingClient(String username)
    : super(
        serverUrl: 'https://music.example.com',
        username: username,
        password: 'synthetic',
      );
  final submitted = <(String, DateTime)>[];
  Completer<void>? gate;
  @override
  Future<void> scrobble(String trackId, DateTime startedAt) async {
    submitted.add((trackId, startedAt));
    if (gate != null) await gate!.future;
  }
}

void main() {
  late FakePlayer player;
  late PlaybackService playback;
  late RecordingClient client;
  late Duration clock;
  final start = DateTime.utc(2026, 11, 11, 18);
  const tracks = [
    Track(
      id: 'one',
      title: 'First',
      artist: 'Artist',
      album: 'Album',
      duration: Duration(minutes: 3),
    ),
    Track(
      id: 'two',
      title: 'Second',
      artist: 'Artist',
      album: 'Album',
      duration: Duration(minutes: 3),
    ),
  ];
  setUp(() {
    clock = Duration.zero;
    player = FakePlayer();
    client = RecordingClient('first');
    playback = PlaybackService(
      player: player,
      listeningClock: () => clock,
      listeningTime: () => start.add(clock),
    );
  });
  tearDown(() async {
    await playback.dispose();
    client.close();
  });
  void listen(int seconds) {
    for (var i = 0; i < seconds; i++) {
      clock += const Duration(seconds: 1);
      player.emit();
    }
  }

  test(
    'pauses, buffering, and forward seeks do not qualify a short listen',
    () async {
      await playback.playAlbum(client, tracks, 0);
      listen(40);
      await playback.pause();
      listen(120);
      await playback.seek(const Duration(seconds: 179));
      expect(client.submitted, isEmpty);
      await playback.play();
      player.processingState = ProcessingState.buffering;
      player.emit();
      listen(120);
      player.processingState = ProcessingState.ready;
      player.emit();
      listen(49);
      expect(client.submitted, isEmpty);
      listen(1);
      expect(client.submitted, [('one', start)]);
      await playback.seek(Duration.zero);
      listen(100);
      expect(client.submitted, hasLength(1));
    },
  );
  test('time waiting for a native seek earns no credit', () async {
    await playback.playAlbum(client, tracks, 0);
    listen(30);
    player.seekGate = Completer<void>();
    final seek = playback.seek(const Duration(seconds: 170));
    listen(90);
    expect(client.submitted, isEmpty);
    player.seekGate!.complete();
    await seek;
    listen(60);
    expect(client.submitted.map((s) => s.$1), ['one']);
  });
  test('native track transitions have separate counters; completed replay counts anew', () async {
    await playback.playAlbum(client, tracks, 0);
    listen(40);
    player.currentIndex = 1;
    player.emit();
    listen(89);
    expect(client.submitted, isEmpty);
    listen(1);
    expect(client.submitted.map((s) => s.$1), ['two']);
    player.processingState = ProcessingState.completed;
    player.emit();
    await playback.play();
    listen(90);
    expect(client.submitted.map((s) => s.$1), ['two', 'one']);
  });
  test(
    'reporting toggle starts fresh and persists no credit while off',
    () async {
      await playback.playAlbum(client, tracks, 0);
      listen(50);
      await playback.preferences.setReportListens(false);
      listen(100);
      expect(client.submitted, isEmpty);
      await playback.preferences.setReportListens(true);
      listen(89);
      expect(client.submitted, isEmpty);
      listen(1);
      expect(client.submitted, [
        ('one', start.add(const Duration(seconds: 150))),
      ]);
    },
  );
  test(
    'an uncertain submission is not retried or allowed to break playback',
    () async {
      client.gate = Completer<void>();
      await playback.playAlbum(client, tracks, 0);
      listen(90);
      client.gate!.completeError(StateError('private transport error'));
      await Future<void>.delayed(Duration.zero);
      listen(100);
      expect(client.submitted, hasLength(1));
      expect(playback.listeningNotice.value, contains('not retried'));
      expect(playback.error.value, isNull);
      expect(player.playing, isTrue);
    },
  );
  test('switching accounts isolates pending submission results and identical song IDs', () async {
    client.gate = Completer<void>();
    await playback.playAlbum(client, tracks, 0);
    listen(90);
    await playback.reset();
    final other = RecordingClient('second');
    addTearDown(other.close);
    await playback.playAlbum(other, tracks, 0);
    client.gate!.completeError(StateError('old account failure'));
    await Future<void>.delayed(Duration.zero);
    expect(playback.listeningNotice.value, isNull);
    listen(89);
    expect(other.submitted, isEmpty);
    listen(1);
    expect(client.submitted, [('one', start)]);
    expect(other.submitted, [('one', start.add(const Duration(seconds: 90)))]);
  });
}
