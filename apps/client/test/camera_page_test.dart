import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperstream_client/app_theme.dart';
import 'package:hyperstream_client/features/player/player_controls.dart';
import 'package:hyperstream_client/models/library.dart';
import 'package:hyperstream_client/services/camera_service.dart';
import 'package:hyperstream_client/services/navidrome_client.dart';
import 'package:hyperstream_client/services/playback_service.dart';

import 'support/fake_player.dart';

class FakeCamera extends CameraService {
  int starts = 0;
  int stops = 0;
  int closes = 0;
  bool? restoredTempo;
  @override
  Future<void> open() async {
    ready = true;
    texture = 1;
    notifyListeners();
  }

  @override
  Future<void> start({required bool originalTempo}) async {
    starts++;
    restoredTempo = originalTempo;
    phase = 'recording';
    notifyListeners();
  }

  @override
  Future<void> stop() async {
    stops++;
    phase = 'idle';
    notifyListeners();
  }

  @override
  Future<void> close() async {
    closes++;
  }
}

void main() {
  const tracks = [
    Track(
      id: 'one',
      title: 'First song',
      artist: 'Artist',
      album: 'Album',
      duration: Duration(minutes: 3),
    ),
    Track(
      id: 'two',
      title: 'Next song',
      artist: 'Artist',
      album: 'Album',
      duration: Duration(minutes: 3),
    ),
  ];

  for (final paused in [true, false]) {
    testWidgets(
      'camera preserves the current queue and tempo when paused=$paused',
      (tester) async {
        final player = FakePlayer();
        final playback = PlaybackService(
          player: player,
          configureSession: (_) async {},
        );
        final client = NavidromeClient(
          serverUrl: 'https://music.example.com',
          username: 'test',
          password: 'test',
        );
        final camera = FakeCamera();
        addTearDown(() async {
          camera.dispose();
          client.close();
          final disposing = playback.dispose();
          await tester.pump();
          await disposing;
        });
        await playback.playAlbum(client, tracks, 0);
        await playback.setSpeed(.75);
        if (paused) await playback.pause();
        player.position = const Duration(seconds: 45);
        final calls = player.playCalls;
        await tester.pumpWidget(
          MaterialApp(
            theme: hyperstreamTheme(Brightness.dark),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => CameraPage(
                        playback: playback,
                        client: client,
                        camera: camera,
                      ),
                    ),
                  ),
                  child: const Text('Open camera'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open camera'));
        await tester.pumpAndSettle();
        expect(camera.starts, 0);
        expect(player.position, const Duration(seconds: 45));
        expect(player.speed, .75);
        expect(player.playCalls, calls);
        expect(player.playing, !paused);
        expect(playback.queue.value.map((track) => track.id), ['one', 'two']);
        expect(find.byTooltip('Previous track'), findsOneWidget);
        await tester.tap(find.text('Stream'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Full Screen'));
        await tester.pumpAndSettle();
        expect(find.byTooltip('Previous track'), findsOneWidget);
        await tester.pump(const Duration(seconds: 6));
        expect(find.text('Exit'), findsNothing);
        await tester.tapAt(const Offset(300, 300));
        await tester.pump();
        await tester.tap(find.text('Exit'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Record'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Start recording'));
        await tester.pump();
        expect(camera.starts, 1);
        expect(camera.restoredTempo, false);
        expect(player.playing, !paused);
        await tester.tap(find.byTooltip('Stop and save take'));
        await tester.pumpAndSettle();
        expect(camera.stops, 1);
        await tester.tap(find.text('Music'));
        await tester.pumpAndSettle();
        expect(find.text('Open camera'), findsOneWidget);
        expect(player.playCalls, calls);
        expect(player.currentIndex, 0);
        await playback.pause();
      },
    );
  }

  for (final size in [const Size(320, 640), const Size(640, 320)]) {
    testWidgets('camera controls fit $size with large text', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final player = FakePlayer();
      final playback = PlaybackService(player: player);
      final client = NavidromeClient(
        serverUrl: 'https://music.example.com',
        username: 'test',
        password: 'test',
      );
      final camera = FakeCamera();
      addTearDown(() async {
        camera.dispose();
        client.close();
        final disposing = playback.dispose();
        await tester.pump();
        await disposing;
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: hyperstreamTheme(Brightness.dark),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.4)),
            child: child!,
          ),
          home: CameraPage(playback: playback, client: client, camera: camera),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Stream'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  test('camera bridge reads native state and closes once', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('dev.hyperstream/camera-test');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'open') {
            return {
              'texture': 8,
              'ready': true,
              'phase': 'idle',
              'pending': 2,
              'captured': true,
            };
          }
          return null;
        });
    final camera = CameraService(channel: channel);
    await camera.open();
    expect(camera.texture, 8);
    expect(camera.pending, 2);
    expect(camera.captured, true);
    await camera.start(originalTempo: true);
    await camera.close();
    await camera.close();
    expect(calls.where((call) => call.method == 'close'), hasLength(1));
    expect(calls.firstWhere((call) => call.method == 'start').arguments, {
      'originalTempo': true,
    });
    camera.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
}
