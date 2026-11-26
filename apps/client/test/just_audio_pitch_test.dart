import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

class _TestAudioPlayer extends AudioPlayer {
  _TestAudioPlayer({required this.supportsPitchControl})
    : super(handleInterruptions: false, androidApplyAudioAttributes: false);

  @override
  final bool supportsPitchControl;
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = binding.defaultBinaryMessenger;
  const channels = 'com.ryanheise.just_audio';
  const control = MethodChannel('$channels.methods');
  const codec = StandardMethodCodec();
  final nativeCalls = <(String, MethodCall)>[];
  final instances = <String>[];
  final mockedChannels = <MethodChannel>[];
  var rejectPitch = false;
  Completer<void>? pendingLoad;
  Completer<void>? loadStarted;
  String? pendingPlayer;

  setUp(() {
    messenger.setMockMethodCallHandler(control, (call) async {
      if (call.method == 'disposePlayer' &&
          call.arguments['id'] == pendingPlayer) {
        pendingLoad!.completeError(PlatformException(code: 'abort'));
        pendingPlayer = null;
      }
      if (call.method == 'init') {
        final id = call.arguments['id'] as String;
        instances.add(id);
        final player = MethodChannel('$channels.methods.$id');
        final events = MethodChannel('$channels.events.$id');
        final data = MethodChannel('$channels.data.$id');
        mockedChannels.addAll([player, events, data]);
        messenger.setMockMethodCallHandler(events, (_) async => null);
        messenger.setMockMethodCallHandler(data, (_) async => null);
        messenger.setMockMethodCallHandler(player, (call) async {
          nativeCalls.add((id, call));
          if (call.method == 'setPreservesPitch' && rejectPitch) {
            throw PlatformException(code: 'pitch-not-applied');
          }
          if (call.method == 'load') {
            if (pendingLoad != null) {
              pendingPlayer = id;
              loadStarted!.complete();
              await pendingLoad!.future;
            }
            await messenger.handlePlatformMessage(
              events.name,
              codec.encodeSuccessEnvelope({
                'processingState': ProcessingState.ready.index,
                'updateTime': 0,
                'updatePosition': 0,
                'bufferedPosition': 1000000,
                'duration': 1000000,
                'currentIndex': 0,
              }),
              (_) {},
            );
            return {'duration': 1000000};
          }
          return <String, Object?>{};
        });
      }
      return <String, Object?>{};
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(control, null);
    for (final channel in mockedChannels) {
      messenger.setMockMethodCallHandler(channel, null);
    }
    mockedChannels.clear();
    nativeCalls.clear();
    instances.clear();
    rejectPitch = false;
    pendingLoad = null;
    loadStarted = null;
    pendingPlayer = null;
  });

  const song = 'https://music.example.com/one.mp3';

  List<MethodCall> loadAndPitchCalls(String id) => [
    for (final (instance, call) in nativeCalls)
      if (instance == id &&
          (call.method == 'load' || call.method == 'setPreservesPitch'))
        call,
  ];

  test('pitch choice reaches each new native player before its load', () async {
    final player = _TestAudioPlayer(supportsPitchControl: true);
    addTearDown(player.dispose);
    expect(player.preservesPitch, isTrue);
    await player.setPreservesPitch(false);
    expect(instances, isEmpty);

    await player.setUrl(song);
    final first = instances.single;
    expect(loadAndPitchCalls(first).map((call) => call.method), [
      'setPreservesPitch',
      'load',
    ]);
    expect(loadAndPitchCalls(first).first.arguments, {'enabled': false});

    rejectPitch = true;
    await expectLater(
      player.setPreservesPitch(true),
      throwsA(isA<PlatformException>()),
    );
    expect(player.preservesPitch, isFalse);
    rejectPitch = false;
    await player.stop();
    await player.setUrl(song);
    final second = instances.last;
    expect(second, isNot(first));
    expect(loadAndPitchCalls(second).map((call) => call.method), [
      'setPreservesPitch',
      'load',
    ]);
    expect(loadAndPitchCalls(second).first.arguments, {'enabled': false});
    await player.setPreservesPitch(true);
    expect(player.preservesPitch, isTrue);
    expect(loadAndPitchCalls(second).last.arguments, {'enabled': true});
  });

  test('backend without pitch control loads without a pitch message', () async {
    final player = _TestAudioPlayer(supportsPitchControl: false);
    addTearDown(player.dispose);
    await player.setUrl(song);
    await expectLater(player.setPreservesPitch(false), throwsUnsupportedError);
    expect(loadAndPitchCalls(instances.single).single.method, 'load');
    expect(player.preservesPitch, isTrue);
  });

  test('stop releases a pitch change waiting for the retired load', () async {
    final player = _TestAudioPlayer(supportsPitchControl: true);
    addTearDown(player.dispose);
    pendingLoad = Completer<void>();
    loadStarted = Completer<void>();
    final loading = expectLater(
      player.setUrl(song),
      throwsA(isA<PlayerInterruptedException>()),
    );
    await loadStarted!.future;
    final retired = instances.single;
    final pitchChange = player.setPreservesPitch(false);

    await player.stop();
    await loading;
    await pitchChange;
    expect(loadAndPitchCalls(retired).map((call) => call.method), [
      'setPreservesPitch',
      'load',
    ]);
    expect(player.preservesPitch, isFalse);

    pendingLoad = null;
    await player.setUrl(song);
    final replacement = instances.last;
    expect(replacement, isNot(retired));
    expect(loadAndPitchCalls(replacement).first.arguments, {'enabled': false});
  });
}
