import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperstream_client/models/library.dart';
import 'package:hyperstream_client/services/navidrome_client.dart';
import 'package:hyperstream_client/services/playback_service.dart';
import 'package:just_audio/just_audio.dart';

// Fake only the native boundary; exercise the real queue and command handling.
class FakePlayer extends Fake implements AudioPlayer {
  final events = StreamController<PlaybackEvent>.broadcast(sync: true);
  final errors = StreamController<PlayerException>.broadcast(sync: true);
  final loaded = <List<AudioSource>>[];
  Completer<void>? loadGate;
  bool failNextLoad = false;
  int playCalls = 0;

  @override
  int? currentIndex;
  @override
  bool playing = false;
  @override
  ProcessingState processingState = ProcessingState.idle;
  @override
  Duration position = Duration.zero;
  @override
  Duration get bufferedPosition => Duration.zero;
  @override
  double get speed => 1;
  @override
  Duration? get duration => const Duration(minutes: 3);
  @override
  bool get hasPrevious => (currentIndex ?? 0) > 0;
  @override
  bool get hasNext =>
      loaded.isNotEmpty && (currentIndex ?? 0) < loaded.last.length - 1;
  @override
  Stream<PlaybackEvent> get playbackEventStream => events.stream;
  @override
  Stream<PlayerException> get errorStream => errors.stream;
  @override
  Stream<PlayerState> get playerStateStream => const Stream.empty();
  @override
  Stream<int?> get currentIndexStream => const Stream.empty();
  @override
  Stream<Duration?> get durationStream => const Stream.empty();

  void emit() => events.add(PlaybackEvent());

  @override
  Future<Duration?> setAudioSources(
    List<AudioSource> audioSources, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
    ShuffleOrder? shuffleOrder,
  }) async {
    loaded.add(audioSources);
    if (loadGate != null) await loadGate!.future;
    if (failNextLoad) {
      failNextLoad = false;
      throw PlayerException(1, 'secret-auth-url', 0);
    }
    currentIndex = initialIndex ?? 0;
    processingState = ProcessingState.ready;
    emit();
    return duration;
  }

  @override
  Future<void> pause() async {
    playing = false;
    emit();
  }

  @override
  Future<void> play() async {
    playCalls++;
    playing = true;
    emit();
  }

  @override
  Future<void> stop() async {
    playing = false;
    processingState = ProcessingState.idle;
    emit();
  }

  @override
  Future<void> clearAudioSources() async {
    currentIndex = null;
  }

  @override
  Future<void> seek(Duration? position, {int? index}) async {
    this.position = position ?? Duration.zero;
    currentIndex = index ?? currentIndex;
    processingState = ProcessingState.ready;
    emit();
  }

  @override
  Future<void> dispose() async {
    await events.close();
    await errors.close();
  }
}

void main() {
  late FakePlayer player;
  late PlaybackService service;
  late NavidromeClient client;
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
    player = FakePlayer();
    service = PlaybackService(player: player);
    client = NavidromeClient(
      serverUrl: 'https://music.example.com',
      username: 'test',
      password: 'test',
    );
  });
  tearDown(() async {
    await service.dispose();
    client.close();
  });

  test('loads the whole album natively at the selected track', () async {
    await service.playAlbum(client, tracks, 1);
    expect(player.loaded.single.length, 2);
    expect(player.currentIndex, 1);
    expect(service.mediaItem.value?.title, 'Second');
    expect(service.queue.value.map((item) => item.id), ['one', 'two']);
    expect(player.playCalls, 1);
  });

  test(
    'a newer selection supersedes an in-flight album without stale autoplay',
    () async {
      player.loadGate = Completer<void>();
      final first = service.playAlbum(client, tracks, 0);
      await Future<void>.delayed(Duration.zero);
      final second = service.playAlbum(client, tracks, 1);
      player.loadGate!.complete();
      await Future.wait([first, second]);
      expect(player.currentIndex, 1);
      expect(player.playCalls, 1);
      expect(service.mediaItem.value?.id, 'two');
    },
  );

  test('pause during loading cancels autoplay', () async {
    player.loadGate = Completer<void>();
    final loading = service.playAlbum(client, tracks, 0);
    await Future<void>.delayed(Duration.zero);
    await service.pause();
    player.loadGate!.complete();
    await loading;
    expect(player.playCalls, 0);
    expect(service.playbackState.value.playing, isFalse);
  });

  test(
    'disconnect during loading clears queue and prevents autoplay',
    () async {
      player.loadGate = Completer<void>();
      final loading = service.playAlbum(client, tracks, 0);
      await Future<void>.delayed(Duration.zero);
      final reset = service.reset();
      player.loadGate!.complete();
      await Future.wait([loading, reset]);
      expect(player.playCalls, 0);
      expect(service.queue.value, isEmpty);
      expect(service.mediaItem.value, isNull);
    },
  );

  test('native failures are sanitized and a new selection recovers', () async {
    player.failNextLoad = true;
    await service.playAlbum(client, tracks, 0);
    expect(
      service.playbackState.value.processingState,
      AudioProcessingState.error,
    );
    expect(service.error.value, isNot(contains('secret-auth-url')));
    expect(player.playCalls, 0);
    await service.playAlbum(client, tracks, 1);
    expect(service.error.value, isNull);
    expect(
      service.playbackState.value.processingState,
      AudioProcessingState.ready,
    );
    expect(player.playCalls, 1);
  });

  test('play after album completion restarts at the beginning', () async {
    await service.playAlbum(client, tracks, 1);
    player.processingState = ProcessingState.completed;
    player.emit();
    expect(service.playbackState.value.playing, isFalse);
    await service.play();
    expect(player.currentIndex, 0);
    expect(player.position, Duration.zero);
  });
}
