import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperstream_client/features/player/audio_share_dialog.dart';
import 'package:hyperstream_client/models/library.dart';
import 'package:hyperstream_client/services/audio_file_share.dart';
import 'package:hyperstream_client/services/navidrome_client.dart';

const song = Track(
  id: 'song',
  title: 'Shared song',
  artist: 'Artist',
  album: 'Album',
  duration: Duration(minutes: 4),
  container: 'mp3',
);

class FakeExport extends AudioFileShare {
  FakeExport(NavidromeClient client) : super(client: client, track: song);
  final prepared = Completer<File>();
  final nativeFinished = Completer<void>();
  int shares = 0;
  bool cleaned = false;
  @override
  Future<File> prepare() => prepared.future;
  @override
  void cancel() {
    if (!prepared.isCompleted) {
      prepared.completeError(const AudioShareCancelled());
    }
    super.cancel();
  }

  void advance() {
    received = 500000;
    total = 1000000;
    notifyListeners();
  }

  @override
  Future<void> share() async {
    shares++;
    await nativeFinished.future;
  }

  @override
  Future<void> cleanup() async {
    cleaned = true;
  }
}

void main() {
  for (final action in ['share', 'cancel', 'dismiss', 'error']) {
    testWidgets(
      'audio preparation $action preserves the page and file lifetime',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final client = NavidromeClient(
          serverUrl: 'https://music.example.com',
          username: 'test',
          password: 'secret',
        );
        addTearDown(client.close);
        final export = FakeExport(client);
        Object? error;
        var completed = false;
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
                  onPressed: () async {
                    try {
                      await shareAudioFile(
                        context,
                        client,
                        song,
                        transfer: export,
                      );
                    } catch (failure) {
                      error = failure;
                    }
                    completed = true;
                  },
                  child: const Text('Share test song'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Share test song'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Preparing audio file'), findsOneWidget);
        export.advance();
        await tester.pump();
        expect(find.text('0.5 MB of 1.0 MB'), findsOneWidget);
        expect(
          tester
              .widget<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator),
              )
              .value,
          .5,
        );
        switch (action) {
          case 'share':
            export.prepared.complete(File('Artist - Shared song.mp3'));
            await tester.pumpAndSettle();
            expect(find.text('Preparing audio file'), findsNothing);
            expect(export.shares, 1);
            expect(export.cleaned, isFalse);
            expect(completed, isFalse);
            export.nativeFinished.complete();
          case 'cancel':
            await tester.tap(find.text('Cancel'));
          case 'dismiss':
            await tester.tapAt(const Offset(5, 5));
          case 'error':
            export.prepared.completeError(
              const NavidromeException('Download unavailable.'),
            );
        }
        await tester.pumpAndSettle();
        expect(find.text('Share test song'), findsOneWidget);
        expect(find.text('Preparing audio file'), findsNothing);
        expect(completed, isTrue);
        expect(export.cleaned, isTrue);
        expect(export.shares, action == 'share' ? 1 : 0);
        expect(error, action == 'error' ? isA<NavidromeException>() : isNull);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
