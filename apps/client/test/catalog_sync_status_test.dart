import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:hyperstream_client/features/playlists/recent_radio_screen.dart';
import 'package:hyperstream_client/services/playback_service.dart';
import 'package:hyperstream_client/services/recent_radio_service.dart';
import 'package:hyperstream_client/models/library.dart';
import 'package:hyperstream_client/widgets/library_sync_status.dart';

import 'catalog_count_test.dart' show countClient, login, count;
import 'recent_radio_service_test.dart' show envelope, song;
import 'support/fake_player.dart';

void main() {
  final now = DateTime.utc(2026, 11, 11, 18);
  test(
    'count lookup coalesces with refresh and local listens never query totals',
    () async {
      final gate = Completer<http.Response>();
      var calls = 0;
      final client = countClient((request) {
        calls++;
        if (request.method == 'POST') return gate.future;
        if (request.url.path.endsWith('/api/song')) return count('0', rows: []);
        return envelope({'searchResult3': {}});
      });
      final radio = RecentRadioService(client, now: () => now);
      addTearDown(() {
        radio.dispose();
        client.close();
      });
      final pending = radio.refresh();
      expect(identical(pending, radio.refresh()), isTrue);
      client.recordLocalListen(Track.fromJson(song('a')), now);
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1);
      gate.complete(login());
      await pending;
      expect(radio.preview!.matches.single.track.id, 'a');
      expect(
        radio.lastSyncTrackCount,
        0,
      ); // Session-only additions aren't synced tracks.
      final afterSync = calls;
      client.recordLocalListen(Track.fromJson(song('b')), now);
      await Future<void>.delayed(Duration.zero);
      await radio.ensureLoaded();
      expect(calls, afterSync);
      expect(radio.preview!.matches, hasLength(2));
    },
  );
  testWidgets(
    'Recent Radio shows the stable total and bar until complete validation',
    (tester) async {
      final secondPage = Completer<http.Response>();
      final endPage = Completer<http.Response>();
      final client = countClient((request) {
        if (request.method == 'POST') return login();
        if (request.url.path.endsWith('/api/song')) return count('4');
        return switch (request.url.queryParameters['songOffset']) {
          '0' => envelope({
            'searchResult3': {
              'song': [song('a'), song('b')],
            },
          }),
          '2' => secondPage.future,
          _ => endPage.future,
        };
      });
      final radio = RecentRadioService(client, now: () => now);
      final playback = PlaybackService(player: FakePlayer());
      addTearDown(() async {
        final disposing = playback.dispose();
        await tester.pump();
        await disposing;
        client.close();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RecentRadioScreen(radio: radio, playback: playback),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('4 tracks'), findsOneWidget);
      expect(find.textContaining('Syncing library ·'), findsNothing);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        .5,
      );
      expect(radio.preview, isNull);
      secondPage.complete(
        envelope({
          'searchResult3': {
            'song': [song('c'), song('d')],
          },
        }),
      );
      await tester.pump();
      expect(find.text('4 tracks'), findsOneWidget);
      expect(radio.syncProgress, .99);
      expect(radio.loading, isTrue);
      endPage.complete(envelope({'searchResult3': {}}));
      await tester.pumpAndSettle();
      expect(radio.syncProgress, 1);
      expect(radio.lastSyncTrackCount, 4);
      expect(find.text('4 tracks'), findsOneWidget);
      expect(find.text('4 songs · 30 days'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      radio.dispose();
      await tester.pump();
    },
  );
  testWidgets(
    'unknown count animates without a fetched total, then shows the actual catalog size',
    (tester) async {
      final end = Completer<http.Response>();
      final client = countClient((request) {
        if (request.method == 'POST') return http.Response('', 404);
        return request.url.queryParameters['songOffset'] == '0'
            ? envelope({
                'searchResult3': {
                  'song': [song('a')],
                },
              })
            : end.future;
      });
      final radio = RecentRadioService(client, now: () => now);
      radio.ensureLoaded();
      await tester.pumpWidget(
        MaterialApp(
          home: ListenableBuilder(
            listenable: radio,
            builder: (_, _) => LibrarySyncStatus(catalog: radio),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Syncing library'), findsOneWidget);
      expect(find.text('1 track'), findsNothing);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        isNull,
      );
      end.complete(envelope({'searchResult3': {}}));
      await tester.pumpAndSettle();
      expect(find.text('1 track'), findsOneWidget);
      expect(radio.syncProgress, 1);
      await tester.pumpWidget(const SizedBox());
      radio.dispose();
      client.close();
    },
  );
  test(
    'a growing library invalidates the count and never truncates the scan',
    () async {
      final end = Completer<http.Response>();
      final offsets = <String>[];
      final client = countClient((request) {
        if (request.method == 'POST') return login();
        if (request.url.path.endsWith('/api/song')) return count('1');
        final offset = request.url.queryParameters['songOffset']!;
        offsets.add(offset);
        return offset == '0'
            ? envelope({
                'searchResult3': {
                  'song': [song('a'), song('b')],
                },
              })
            : end.future;
      });
      final radio = RecentRadioService(client, now: () => now);
      addTearDown(() {
        radio.dispose();
        client.close();
      });
      final pending = radio.refresh();
      await Future<void>.delayed(Duration.zero);
      expect(radio.loadedCount, 2);
      expect(radio.syncTotal, isNull);
      expect(radio.syncProgress, isNull);
      end.complete(envelope({'searchResult3': {}}));
      await pending;
      expect(offsets, ['0', '2']);
      expect(radio.lastSyncTrackCount, 2);
      expect(radio.syncProgress, 1);
    },
  );
  test('failed sync retains the last actual total; retry replaces it including zero', () async {
    var total = '5';
    var fail = false;
    var empty = false;
    final client = countClient((request) {
      if (request.method == 'POST') return login();
      if (request.url.path.endsWith('/api/song')) {
        return count(
          total,
          rows: total == '0'
              ? []
              : [
                  {'id': 'a'},
                ],
        );
      }
      if (fail) return http.Response('private', 500);
      return envelope({
        'searchResult3': {
          'song': !empty && request.url.queryParameters['songOffset'] == '0'
              ? [song('a'), song('b')]
              : [],
        },
      });
    });
    final radio = RecentRadioService(client, now: () => now);
    addTearDown(() {
      radio.dispose();
      client.close();
    });
    await radio.refresh();
    expect(radio.lastSyncTrackCount, 2);
    expect(radio.syncTotal, 2);
    fail = true;
    total = '8';
    await radio.refresh();
    expect(radio.lastSyncTrackCount, 2);
    expect(radio.syncProgress, isNull);
    expect(radio.error, isNotNull);
    fail = false;
    empty = true;
    total = '0';
    await radio.refresh();
    expect(radio.lastSyncTrackCount, 0);
    expect(radio.syncProgress, 1);
    expect(radio.error, isNull);
  });
  test(
    'dispose during count prevents catalog fetch and late status publication',
    () async {
      final gate = Completer<http.Response>();
      var requests = 0;
      final client = countClient((_) {
        requests++;
        return gate.future;
      });
      final radio = RecentRadioService(client);
      final pending = radio.refresh();
      radio.dispose();
      gate.complete(login());
      await pending;
      expect(requests, 1);
      expect(radio.lastSyncedAt, isNull);
      expect(radio.syncTotal, isNull);
      client.close();
    },
  );
  testWidgets(
    'total formatting and accessible labels fit narrow screens with large text',
    (tester) async {
      final client = countClient((_) => http.Response('', 404));
      final radio = RecentRadioService(client)
        ..loading = true
        ..syncTotal = 12345
        ..loadedCount = 6172;
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: LibrarySyncStatus(catalog: radio),
              ),
            ),
          ),
        ),
      );
      expect(find.text('12,345 tracks'), findsOneWidget);
      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.semanticsLabel, 'Syncing library, 12,345 tracks');
      expect(
        bar.semanticsValue,
        isNull,
      ); // Let Flutter expose numeric progress.
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      radio.dispose();
      client.close();
    },
  );
}
