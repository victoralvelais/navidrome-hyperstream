import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

// Fake only the native boundary; exercise the real queue and command handling.
class FakePlayer extends Fake implements AudioPlayer {
  final events = StreamController<PlaybackEvent>.broadcast(sync: true);
  final errors = StreamController<PlayerException>.broadcast(sync: true);
  final loaded = <List<AudioSource>>[];
  Completer<void>? loadGate;
  Completer<void>? seekGate;
  bool failNextLoad = false;
  bool failVolume = false;
  int playCalls = 0;
  int seekCalls = 0;
  final volumeCalls = <double>[];
  @override
  double volume = 1;
  @override
  Stream<Duration> get positionStream => const Stream.empty();
  @override
  Future<void> setVolume(double value) async {
    if (failVolume) throw StateError('native details');
    volumeCalls.add(value);
    volume = value;
  }

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
    seekCalls++;
    if (seekGate != null) await seekGate!.future;
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
