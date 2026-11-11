import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperstream_client/features/connect/connection_screen.dart';
import 'package:hyperstream_client/features/startup/startup_screen.dart';
import 'package:hyperstream_client/main.dart';
import 'package:hyperstream_client/services/playback_service.dart';
import 'package:hyperstream_client/services/startup_stage.dart';
import 'package:hyperstream_client/services/account_session.dart';
import 'package:hyperstream_client/features/library/library_screen.dart';

import 'support/fake_player.dart';
import 'support/account_fakes.dart';

class ObservedPlayback extends PlaybackService {
  ObservedPlayback() : super(player: FakePlayer());
  bool disposed = false;
  @override
  Future<void> dispose() async {
    disposed = true;
    await super.dispose();
  }
}

void main() {
  testWidgets(
    'startup screen is built before native initialization and stalled stage remains visible',
    (tester) async {
      final gate = Completer<PlaybackService>();
      var calls = 0;
      await tester.pumpWidget(
        HyperstreamApp(
          accountSession: AccountSession(store: MemoryAccountStore()),
          initialize: (onStage) {
            calls++;
            expect(find.byType(StartupScreen), findsOneWidget);
            onStage(StartupStage.audioSession);
            return gate.future;
          },
        ),
      );
      await tester.pump();
      expect(find.text('Hyperstream'), findsOneWidget);
      expect(find.text('Preparing audio'), findsOneWidget);
      await tester.pump(const Duration(seconds: 16));
      expect(find.textContaining('taking longer'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      expect(calls, 1);

      final playback = ObservedPlayback();
      gate.complete(playback);
      await tester.pumpAndSettle();
      expect(find.byType(ConnectionScreen), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(playback.disposed, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'startup failure gives a sanitized stage and retry reaches sign-in',
    (tester) async {
      var calls = 0;
      final playback = ObservedPlayback();
      await tester.pumpWidget(
        HyperstreamApp(
          accountSession: AccountSession(store: MemoryAccountStore()),
          initialize: (onStage) async {
            calls++;
            onStage(StartupStage.player);
            if (calls == 1) throw StateError('private native details');
            return playback;
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Could not finish: starting the music player.'),
        findsOneWidget,
      );
      expect(find.textContaining('private native details'), findsNothing);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.byType(ConnectionScreen), findsOneWidget);
      expect(calls, 2);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(playback.disposed, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'closing during initialization disposes a late player without rebuilding',
    (tester) async {
      final gate = Completer<PlaybackService>();
      final playback = ObservedPlayback();
      late ValueChanged<StartupStage> report;
      await tester.pumpWidget(
        HyperstreamApp(
          accountSession: AccountSession(store: MemoryAccountStore()),
          initialize: (onStage) {
            report = onStage;
            return gate.future;
          },
        ),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      report(StartupStage.volume);
      gate.complete(playback);
      await tester.pump();
      expect(playback.disposed, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cold start restores account and disconnect prevents next restoration',
    (tester) async {
      final store = MemoryAccountStore()..account = exampleAccount();
      AccountSession session() =>
          AccountSession(store: store, createClient: AccountClient.new);
      final first = session();
      await tester.pumpWidget(
        HyperstreamApp(
          accountSession: first,
          initialize: (_) async => ObservedPlayback(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(LibraryScreen), findsOneWidget);
      expect(find.byType(ConnectionScreen), findsNothing);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Disconnect from server'));
      await tester.tap(find.text('Disconnect from server'));
      await tester.pumpAndSettle();
      expect(find.byType(ConnectionScreen), findsOneWidget);
      expect(store.account, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        HyperstreamApp(
          accountSession: session(),
          initialize: (_) async => ObservedPlayback(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ConnectionScreen), findsOneWidget);
      expect(find.text('Connect'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
