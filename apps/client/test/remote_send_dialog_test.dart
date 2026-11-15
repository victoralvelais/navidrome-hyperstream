import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperstream_client/features/player/remote_send_dialog.dart';
import 'package:hyperstream_client/models/library.dart';
import 'package:hyperstream_client/services/audio_file_share.dart';
import 'package:hyperstream_client/services/navidrome_client.dart';
import 'package:hyperstream_client/services/remote_folder.dart';
import 'package:hyperstream_client/services/remote_transfer_background.dart';

import 'remote_folder_test.dart'
    show MemoryRemoteFs, MemoryRemoteStore, destination;

const song = Track(
  id: 'song',
  title: 'Test song',
  artist: 'Artist',
  album: 'Album',
  duration: Duration(minutes: 4),
);

class MemoryAudioFile implements File {
  @override
  Uri get uri => Uri.file('Song.mp3');
  @override
  Future<int> length() async => 3;
  @override
  Stream<List<int>> openRead([int? start, int? end]) async* {
    yield [73, 68, 51];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class PendingExport extends AudioFileShare {
  PendingExport(NavidromeClient client) : super(client: client, track: song);
  final prepared = Completer<File>();
  bool started = false;
  bool cancelled = false;
  bool cleaned = false;
  @override
  Future<File> prepare() {
    started = true;
    return prepared.future;
  }

  @override
  void cancel() {
    cancelled = true;
    if (started && !prepared.isCompleted) {
      prepared.completeError(const AudioShareCancelled());
    }
  }

  @override
  Future<void> cleanup() async {
    cleaned = true;
  }
}

class PendingRemoteFs extends MemoryRemoteFs {
  final writing = Completer<void>();
  @override
  Future<void> write(
    String path,
    Stream<List<int>> chunks,
    int length,
    void Function(int) progress,
    bool Function() cancelled,
  ) async {
    await writing.future;
    await super.write(path, chunks, length, progress, cancelled);
  }
}

class FakeBackground extends RemoteTransferBackground {
  FakeBackground(this.mode);
  final RemoteBackgroundMode mode;
  Completer<void>? grant;
  VoidCallback? expire;
  final results = <bool>[];
  final stages = <String>[];
  @override
  Future<RemoteBackgroundMode> begin(VoidCallback onExpired) async {
    expire = onExpired;
    await grant?.future;
    return mode;
  }

  @override
  void update({
    required int completed,
    required int total,
    required String stage,
  }) {
    stages.add(stage);
  }

  @override
  Future<void> finish({required bool success}) async {
    results.add(success);
  }
}

void main() {
  for (final scenario in [
    'continued',
    'limited',
    'desktop',
    'expire-download',
    'expire-upload',
    'cancel',
    'foreground',
    'delayed-denial',
  ]) {
    testWidgets('remote transfer lifecycle $scenario', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final client = NavidromeClient(
        serverUrl: 'https://music.example.com',
        username: 'listener',
        password: 'test-password',
      );
      addTearDown(client.close);
      final fs = PendingRemoteFs();
      final store = MemoryRemoteStore()
        ..value = RemoteFolderConfig.forDestination(destination());
      final remote = RemoteFolders(store: store, connect: (_) async => fs);
      await remote.restore();
      addTearDown(remote.dispose);
      final export = PendingExport(client);
      final background = FakeBackground(switch (scenario) {
        'limited' => RemoteBackgroundMode.limited,
        'desktop' => RemoteBackgroundMode.desktop,
        'foreground' || 'delayed-denial' => RemoteBackgroundMode.foreground,
        _ => RemoteBackgroundMode.continued,
      });
      if (scenario == 'delayed-denial') background.grant = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(1.4)),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => sendSongToRemote(
                  context,
                  client,
                  song,
                  remote: remote,
                  export: export,
                  background: background,
                ),
                child: const Text('Send'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Send'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(remote.busy, isTrue);

      if (scenario == 'cancel') {
        await tester.tap(find.text('Cancel'));
      } else {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();
        if (scenario == 'delayed-denial') {
          background.grant!.complete();
        } else if (scenario == 'expire-download') {
          background.expire!();
        } else if (scenario != 'foreground') {
          expect(export.cancelled, isFalse);
          export.prepared.complete(MemoryAudioFile());
          await tester.pump();
          if (scenario == 'expire-upload') background.expire!();
          fs.writing.complete();
        }
      }
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      final success = ['continued', 'limited', 'desktop'].contains(scenario);
      expect(background.results, [success]);
      expect(remote.busy, isFalse);
      expect(export.cleaned, isTrue);
      expect(fs.closed, scenario != 'delayed-denial');
      expect(
        fs.files,
        success
            ? {
                'Test/Song.mp3': [73, 68, 51],
              }
            : isEmpty,
      );
      if (success) {
        expect(
          background.stages,
          containsAllInOrder(['Sending audio', 'Finishing']),
        );
        expect(find.textContaining('Sent Song.mp3'), findsOneWidget);
      } else if (scenario != 'cancel') {
        expect(
          find.textContaining('Background execution ended'),
          findsOneWidget,
        );
      }
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('Send'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
