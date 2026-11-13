import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

// Fake only the native boundary; exercise the real queue and command handling.
class FakePlayer extends Fake implements AudioPlayer {
  final events = StreamController<PlaybackEvent>.broadcast(sync: true);
  final errors = StreamController<PlayerException>.broadcast(sync: true);
  final loaded = <List<AudioSource>>[];
  final preloads = <bool>[];
  ShuffleOrder? activeShuffleOrder;
  Completer<void>? loadGate;
  Completer<void>? seekGate;
  bool failNextLoad = false;
  bool failVolume = false;
  bool failEdit = false;
  Completer<void>? editGate;
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
  double speed = 1;
  @override
  bool shuffleModeEnabled = false;
  @override
  LoopMode loopMode = LoopMode.off;
  @override
  List<int> shuffleIndices = [];
  @override
  Future<void> setSpeed(double value) async {
    speed = value;
  }

  @override
  Future<void> setLoopMode(LoopMode value) async {
    loopMode = value;
  }

  @override
  Future<void> setShuffleModeEnabled(bool value) async {
    shuffleModeEnabled = value;
  }

  @override
  Future<void> shuffle() async {
    if (activeShuffleOrder != null) {
      activeShuffleOrder!.shuffle(initialIndex: currentIndex);
      shuffleIndices = List.of(activeShuffleOrder!.indices);
      return;
    }
    shuffleIndices = List.generate(
      loaded.isEmpty ? 0 : loaded.last.length,
      (i) => i,
    );
  }

  @override
  Future<void> seekToPrevious() =>
      seek(Duration.zero, index: (currentIndex ?? 1) - 1);
  @override
  Future<void> seekToNext() =>
      seek(Duration.zero, index: (currentIndex ?? 0) + 1);
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
    preloads.add(preload);
    if (loadGate != null) await loadGate!.future;
    if (failNextLoad) {
      failNextLoad = false;
      throw PlayerException(1, 'secret-auth-url', 0);
    }
    // Match just_audio's idle player: initial seek arguments are deferred until
    // activation, so paused restoration must explicitly seek the idle queue.
    currentIndex = preload ? initialIndex ?? 0 : 0;
    position = preload ? initialPosition ?? Duration.zero : Duration.zero;
    activeShuffleOrder = shuffleOrder;
    shuffleOrder?.clear();
    shuffleOrder?.insert(0, audioSources.length);
    shuffleOrder?.shuffle(initialIndex: currentIndex);
    shuffleIndices = shuffleOrder == null
        ? List.generate(audioSources.length, (i) => i)
        : List.of(shuffleOrder.indices);
    processingState = preload ? ProcessingState.ready : ProcessingState.idle;
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
    processingState = ProcessingState.ready;
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
    position = Duration.zero;
  }

  @override
  Future<void> moveAudioSource(int from, int to) async {
    if (editGate != null) await editGate!.future;
    if (failEdit) throw StateError('native edit failed');
    final current = currentIndex == null ? null : loaded.last[currentIndex!];
    loaded.last.insert(to, loaded.last.removeAt(from));
    currentIndex = current == null ? null : loaded.last.indexOf(current);
    emit();
  }

  @override
  Future<void> removeAudioSourceAt(int index) async {
    if (editGate != null) await editGate!.future;
    if (failEdit) throw StateError('native edit failed');
    final current = currentIndex == null ? null : loaded.last[currentIndex!];
    loaded.last.removeAt(index);
    currentIndex = current == null ? null : loaded.last.indexOf(current);
    emit();
  }

  @override
  Future<void> seek(Duration? position, {int? index}) async {
    seekCalls++;
    if (seekGate != null) await seekGate!.future;
    this.position = position ?? Duration.zero;
    currentIndex = index ?? currentIndex;
    if (processingState != ProcessingState.idle) {
      processingState = ProcessingState.ready;
    }
    emit();
  }

  @override
  Future<void> dispose() async {
    await events.close();
    await errors.close();
  }
}
