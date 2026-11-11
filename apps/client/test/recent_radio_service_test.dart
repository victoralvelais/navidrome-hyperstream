import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hyperstream_client/models/library.dart';
import 'package:hyperstream_client/services/navidrome_client.dart';
import 'package:hyperstream_client/services/recent_radio_service.dart';

http.Response envelope(Map<String, dynamic> contents) => http.Response(
  jsonEncode({
    'subsonic-response': {
      'status': 'ok',
      'type': 'navidrome',
      'serverVersion': 'test-version',
      'openSubsonic': true,
      ...contents,
    },
  }),
  200,
);
Map<String, dynamic> song(String id) => {
  'id': id,
  'created': '2026-11-10T00:00:00Z',
  'played': '2026-11-11T00:00:00Z',
  'playCount': 1,
};
NavidromeClient api(
  FutureOr<http.Response> Function(http.Request) handler, {
  String user = 'one',
  String url = 'https://music.example.com/',
}) => NavidromeClient(
  serverUrl: url,
  username: user,
  password: 'synthetic',
  httpClient: MockClient((request) async => handler(request)),
);

void main() {
  final now = DateTime.utc(2026, 11, 11, 18);
  test('complete pagination uses actual page size, deduplicates, and preserves metadata', () async {
    final offsets = <int>[];
    final client = api((request) {
      final offset = int.parse(request.url.queryParameters['songOffset']!);
      offsets.add(offset);
      return envelope({
        'searchResult3': {
          'song': switch (offset) {
            0 => [song('a'), song('b')],
            2 => [song('b'), song('c')],
            _ => [],
          },
        },
      });
    });
    addTearDown(client.close);
    final tracks = await client.radioTracks(cancelled: () => false);
    expect(offsets, [0, 2, 4]);
    expect(tracks.map((s) => s.id), ['a', 'b', 'c']);
    expect(tracks.first.lastPlayedAt, DateTime.utc(2026, 11, 11));
    expect(client.serverVersion, 'test-version');
  });
  test(
    'repeated pages and missing history are errors, never partial success',
    () async {
      for (final repeated in [true, false]) {
        var page = 0;
        final client = api(
          (_) => envelope({
            'searchResult3': {
              'song': repeated
                  ? [song('a')]
                  : page++ == 0
                  ? [
                      {...song('a'), 'played': null},
                    ]
                  : [],
            },
          }),
        );
        await expectLater(
          client.radioTracks(cancelled: () => false),
          throwsA(isA<NavidromeException>()),
        );
        client.close();
      }
    },
  );
  test(
    'canceling a page read discards its results and prevents further requests',
    () async {
      final gate = Completer<http.Response>();
      var cancelled = false;
      var calls = 0;
      final client = api((_) {
        calls++;
        return gate.future;
      });
      addTearDown(client.close);
      final reading = client.radioTracks(cancelled: () => cancelled);
      cancelled = true;
      gate.complete(
        envelope({
          'searchResult3': {
            'song': [song('a')],
          },
        }),
      );
      expect(await reading, isEmpty);
      expect(calls, 1);
    },
  );
  test(
    'listen request submits milliseconds once without fetching the catalog',
    () async {
      final requests = <http.Request>[];
      final client = api((request) {
        requests.add(request);
        return envelope({});
      });
      addTearDown(client.close);
      await client.scrobble('a', now);
      expect(requests.single.url.path, '/rest/scrobble.view');
      expect(requests.single.url.queryParameters['submission'], 'true');
      expect(
        requests.single.url.queryParameters['time'],
        '${now.millisecondsSinceEpoch}',
      );
      expect(requests.single.url.queryParameters['id'], 'a');
      expect(requests.single.followRedirects, isFalse);
    },
  );
  test('an uncertain scrobble response is not retried', () async {
    var calls = 0;
    var events = 0;
    final client = api((_) {
      calls++;
      throw http.ClientException('private-url');
    });
    final subscription = client.localListens.listen((_) => events++);
    await expectLater(
      client.scrobble('a', now),
      throwsA(isA<NavidromeException>()),
    );
    expect(calls, 1);
    expect(events, 0);
    await subscription.cancel();
    client.close();
  });

  test(
    'local listens add and reorder songs without any network requests',
    () async {
      var calls = 0;
      final old = {
        ...song('old'),
        'created': '2020-01-01T00:00:00Z',
        'played': null,
        'playCount': 0,
      };
      final client = api((request) {
        calls++;
        return envelope({
          'searchResult3': {
            'song': request.url.queryParameters['songOffset'] == '0'
                ? [song('a'), old]
                : [],
          },
        });
      });
      final service = RecentRadioService(client, now: () => now);
      addTearDown(service.dispose);
      addTearDown(client.close);
      await service.ensureLoaded();
      expect(service.preview!.matches.map((m) => m.track.id), ['a']);
      final requests = calls;
      final synced = service.lastSyncedAt;
      client.recordLocalListen(Track.fromJson(old), now);
      await Future<void>.delayed(Duration.zero);
      expect(service.preview!.matches.map((m) => m.track.id), ['old', 'a']);
      expect(service.preview!.matches.first.reason, 'Played recently');
      client.recordLocalListen(Track.fromJson(old), now);
      await Future<void>.delayed(Duration.zero);
      await service.ensureLoaded();
      expect(service.preview!.matches, hasLength(2));
      expect(calls, requests);
      expect(service.lastSyncedAt, synced);
      expect(service.loading, isFalse);
    },
  );

  test(
    'sync races preserve local activity, reconcile history, and honor deletion',
    () async {
      var songs = [song('a')];
      Completer<http.Response>? gate;
      final client = api((request) {
        if (gate != null) return gate.future;
        return envelope({
          'searchResult3': {
            'song': request.url.queryParameters['songOffset'] == '0'
                ? songs
                : [],
          },
        });
      });
      final service = RecentRadioService(client, now: () => now);
      addTearDown(service.dispose);
      addTearDown(client.close);
      await service.refresh();
      gate = Completer<http.Response>();
      final refreshing = service.refresh();
      final sameRefresh = service.refresh();
      expect(identical(refreshing, sameRefresh), isTrue);
      final local = Track.fromJson({...song('new'), 'title': 'Local title'});
      client.recordLocalListen(local, now);
      await Future<void>.delayed(Duration.zero);
      expect(service.preview!.matches.first.track.id, 'new');
      gate.complete(envelope({'searchResult3': {}}));
      await refreshing;
      expect(service.preview!.matches.single.track.id, 'new');
      gate = null;
      // A stale server play date must not undo a local listen.
      songs = [
        {...song('new'), 'title': 'Renamed on server'},
      ];
      await service.refresh();
      expect(service.preview!.matches.single.track.lastPlayedAt, now);
      expect(service.preview!.matches.single.track.title, 'Renamed on server');
      // Server history catches up; its fresh metadata still wins.
      songs = [
        {...song('new'), 'played': now.toIso8601String()},
      ];
      await service.refresh();
      expect(service.preview!.matches.single.track.lastPlayedAt, now);
      songs = [];
      await service.refresh();
      expect(service.preview!.matches, isEmpty);
    },
  );

  test(
    'failed sync retains local updates and does not claim a new sync time',
    () async {
      var fail = false;
      final client = api((request) {
        if (fail) return http.Response('private response', 500);
        return envelope({
          'searchResult3': {
            'song': request.url.queryParameters['songOffset'] == '0'
                ? [song('a')]
                : [],
          },
        });
      });
      final service = RecentRadioService(client, now: () => now);
      addTearDown(service.dispose);
      addTearDown(client.close);
      await service.refresh();
      final synced = service.lastSyncedAt;
      fail = true;
      await service.refresh();
      client.recordLocalListen(Track.fromJson(song('b')), now);
      await Future<void>.delayed(Duration.zero);
      expect(service.preview!.matches.first.track.id, 'b');
      expect(service.error, isNotNull);
      expect(service.lastSyncedAt, synced);
    },
  );

  test(
    'local listens before first open are retained when the catalog arrives',
    () async {
      var calls = 0;
      final client = api((request) {
        calls++;
        return envelope({
          'searchResult3': {
            'song': request.url.queryParameters['songOffset'] == '0'
                ? [song('a')]
                : [],
          },
        });
      });
      final service = RecentRadioService(client, now: () => now);
      addTearDown(service.dispose);
      addTearDown(client.close);
      client.recordLocalListen(Track.fromJson(song('a')), now);
      await Future<void>.delayed(Duration.zero);
      expect(calls, 0);
      expect(service.lastSyncedAt, isNull);
      expect(service.preview!.matches.single.track.lastPlayedAt, now);
      await service.ensureLoaded();
      expect(service.preview!.matches.single.track.lastPlayedAt, now);
      expect(service.lastSyncedAt, now);
    },
  );

  test(
    'same song IDs and local activity stay isolated by authenticated client',
    () async {
      final first = api((_) => envelope({'searchResult3': {}}));
      final second = api((_) => envelope({'searchResult3': {}}), user: 'two');
      final a = RecentRadioService(first, now: () => now);
      final b = RecentRadioService(second, now: () => now);
      first.recordLocalListen(Track.fromJson(song('a')), now);
      await Future<void>.delayed(Duration.zero);
      expect(a.preview!.matches.single.track.id, 'a');
      expect(b.preview, isNull);
      a.dispose();
      first.recordLocalListen(Track.fromJson(song('b')), now);
      await Future<void>.delayed(Duration.zero);
      expect(b.preview, isNull);
      b.dispose();
      first.close();
      second.close();
    },
  );

  test(
    'dispose during an in-flight scan never publishes a late preview',
    () async {
      final gate = Completer<http.Response>();
      final client = api((_) => gate.future);
      final service = RecentRadioService(client);
      final loading = service.refresh();
      service.dispose();
      gate.complete(
        envelope({
          'searchResult3': {
            'song': [song('a')],
          },
        }),
      );
      await loading;
      expect(service.preview, isNull);
      client.close();
    },
  );

  testWidgets(
    '30-minute schedule survives navigation, coalesces triggers, and resets on manual refresh',
    (tester) async {
      var calls = 0;
      final client = api((_) {
        calls++;
        return envelope({'searchResult3': {}});
      });
      final service = RecentRadioService(client, now: tester.binding.clock.now);
      service.ensureLoaded();
      await tester.pumpAndSettle();
      expect(calls, 1);
      await tester.pump(const Duration(minutes: 29, seconds: 59));
      service.ensureLoaded();
      await tester.pumpAndSettle();
      expect(calls, 1);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(calls, 2);
      await tester.pump(const Duration(minutes: 20));
      service.refresh();
      service.refresh();
      await tester.pumpAndSettle();
      expect(calls, 3);
      await tester.pump(const Duration(minutes: 29, seconds: 59));
      expect(calls, 3);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(calls, 4);
      service.dispose();
      await tester.pump(const Duration(hours: 1));
      expect(calls, 4);
      client.close();
    },
  );

  testWidgets('background suspension waits for one overdue sync on resume', (
    tester,
  ) async {
    var calls = 0;
    final client = api((_) {
      calls++;
      return envelope({'searchResult3': {}});
    });
    final service = RecentRadioService(client, now: tester.binding.clock.now);
    service.ensureLoaded();
    await tester.pumpAndSettle();
    service.setAppActive(false);
    await tester.pump(const Duration(minutes: 10));
    service.setAppActive(true);
    await tester.pumpAndSettle();
    expect(calls, 1);
    service.setAppActive(false);
    await tester.pump(const Duration(hours: 2));
    expect(calls, 1);
    service.setAppActive(true);
    service.setAppActive(true);
    await tester.pumpAndSettle();
    expect(calls, 2);
    service.dispose();
    client.close();
  });

  testWidgets(
    'failed scheduled sync waits another interval and expires old matches on next visit',
    (tester) async {
      var fail = false;
      var calls = 0;
      final initial = tester.binding.clock.now().toUtc();
      final boundary = {
        ...song('boundary'),
        'created': initial.subtract(const Duration(days: 30)).toIso8601String(),
        'played': null,
        'playCount': 0,
      };
      final client = api((request) {
        calls++;
        if (fail) return http.Response('', 500);
        return envelope({
          'searchResult3': {
            'song': request.url.queryParameters['songOffset'] == '0'
                ? [boundary]
                : [],
          },
        });
      });
      final service = RecentRadioService(client, now: tester.binding.clock.now);
      service.ensureLoaded();
      await tester.pump();
      expect(service.preview!.matches, hasLength(1));
      fail = true;
      await tester.pump(const Duration(minutes: 30));
      await tester.pumpAndSettle();
      final failedCalls = calls;
      service.ensureLoaded();
      await tester.pumpAndSettle();
      expect(service.preview!.matches, isEmpty);
      expect(service.error, isNotNull);
      await tester.pump(const Duration(minutes: 29));
      expect(calls, failedCalls);
      await tester.pump(const Duration(minutes: 1));
      await tester.pumpAndSettle();
      expect(calls, failedCalls + 1);
      service.dispose();
      client.close();
    },
  );
}
