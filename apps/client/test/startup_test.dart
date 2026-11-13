import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperstream_client/features/connect/connection_screen.dart';
import 'package:hyperstream_client/features/startup/startup_screen.dart';
import 'package:hyperstream_client/main.dart';
import 'package:hyperstream_client/services/playback_service.dart';
import 'package:hyperstream_client/services/startup_stage.dart';
import 'package:hyperstream_client/services/account_session.dart';
import 'package:hyperstream_client/services/account_store.dart';
import 'package:hyperstream_client/features/library/library_screen.dart';

import 'support/fake_player.dart';
import 'support/account_fakes.dart';
import 'playback_continuity_test.dart' show MemoryPlaybackStore, savedQueue;

class ObservedPlayback extends PlaybackService {
  ObservedPlayback({super.playbackStore, FakePlayer? player})
    : super(
        player: player ?? FakePlayer(),
        artworkLoader: (_, _) async => null,
      );
  bool disposed = false;
  @override
  Future<void> dispose() async {
    disposed = true;
    await super.dispose();
  }
}

void main() {
  testWidgets(
    'queue restore waits for verified login and lifecycle saves its position',
    (tester) async {
      final accounts = MemoryAccountStore()..account = exampleAccount();
      final gate = Completer<void>();
      final session = AccountSession(
        store: accounts,
        createClient:
            ({required serverUrl, required username, required password}) =>
                AccountClient(
                  serverUrl: serverUrl,
                  username: username,
                  password: password,
                )..pingGate = gate,
      );
      final saved = MemoryPlaybackStore()..value = savedQueue();
      final native = FakePlayer();
      final playback = ObservedPlayback(
        player: native,
        playbackStore: (_) => saved,
      );
      await tester.pumpWidget(
        HyperstreamApp(
          accountSession: session,
          initialize: (_) async => playback,
        ),
      );
      await tester.pump();
      expect(saved.reads, 0);
      expect(native.loaded, isEmpty);
      gate.complete();
      await tester.pumpAndSettle();
      expect(saved.reads, 1);
      expect(playback.queue.value, hasLength(3));
      expect(native.playCalls, 0);
      native.position = const Duration(seconds: 62);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(saved.value!.position, const Duration(seconds: 62));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed server verification never reads or loads a saved queue', (
    tester,
  ) async {
    final accounts = MemoryAccountStore()..account = exampleAccount();
    final session = AccountSession(
      store: accounts,
      createClient:
          ({required serverUrl, required username, required password}) =>
              AccountClient(
                serverUrl: serverUrl,
                username: username,
                password: password,
              )..pingError = StateError('unavailable'),
    );
    final saved = MemoryPlaybackStore()..value = savedQueue();
    final native = FakePlayer();
    final playback = ObservedPlayback(
      player: native,
      playbackStore: (_) => saved,
    );
    await tester.pumpWidget(
      HyperstreamApp(
        accountSession: session,
        initialize: (_) async => playback,
      ),
    );
    await tester.pumpAndSettle();
    expect(saved.reads, 0);
    expect(native.loaded, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('Home settings switches saved servers and rebuilds the library', (
    tester,
  ) async {
    final first = exampleAccount();
    final second = SavedAccount(
      serverUrl: 'https://second.example.com',
      username: 'other',
      password: 'synthetic',
      name: 'Second library',
    );
    final store = MemoryAccountStore()
      ..servers = SavedServers(accounts: [first, second], activeId: first.id)
      ..account = first;
    final session = AccountSession(
      store: store,
      createClient: AccountClient.new,
    );
    final playback = ObservedPlayback();
    await tester.pumpWidget(
      HyperstreamApp(
        accountSession: session,
        initialize: (_) async => playback,
      ),
    );
    await tester.pumpAndSettle();
    final oldScreen = tester.widget<LibraryScreen>(find.byType(LibraryScreen));
    await tester.tap(find.text('Servers'));
    await tester.pumpAndSettle();
    expect(find.text('Second library'), findsOneWidget);
    await tester.tap(find.text('Second library'));
    await tester.pumpAndSettle();
    expect(session.client!.username, 'other');
    expect(store.servers!.accounts, hasLength(2));
    final newScreen = tester.widget<LibraryScreen>(find.byType(LibraryScreen));
    expect(newScreen.key, isNot(oldScreen.key));
    expect(playback.queue.value, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
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
      expect(find.text('Disconnect from server'), findsNothing);
      await tester.tap(find.text('Servers'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Disconnect from server'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Disconnect from server'));
      await tester.pumpAndSettle();
      expect(store.account, isNotNull);
      expect(find.byType(ConnectionScreen), findsNothing);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(first.phase, AccountPhase.connected);
      expect(store.account, isNotNull);
      await tester.tap(find.text('Disconnect from server'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Disconnect'));
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
