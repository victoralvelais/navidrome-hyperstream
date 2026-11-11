import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hyperstream_client/models/recent_radio.dart';
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
  test('listen request submits milliseconds once and successful writes notify the same client', () async {
    final requests = <http.Request>[];
    final client = api((request) {
      requests.add(request);
      return envelope({});
    });
    addTearDown(client.close);
    final event = client.listens.first;
    await client.scrobble('a', now);
    await event;
    expect(requests.single.url.path, '/rest/scrobble.view');
    expect(requests.single.url.queryParameters['submission'], 'true');
    expect(
      requests.single.url.queryParameters['time'],
      '${now.millisecondsSinceEpoch}',
    );
    expect(requests.single.url.queryParameters['id'], 'a');
    expect(requests.single.followRedirects, isFalse);
  });
  test(
    'an uncertain scrobble response is not retried or broadcast as success',
    () async {
      var calls = 0;
      var events = 0;
      final client = api((_) {
        calls++;
        throw http.ClientException('private-url');
      });
      final subscription = client.listens.listen((_) => events++);
      await expectLater(
        client.scrobble('a', now),
        throwsA(isA<NavidromeException>()),
      );
      expect(calls, 1);
      expect(events, 0);
      await subscription.cancel();
      client.close();
    },
  );

  test('failed refresh retains the exact last preview; successful listens mark it dirty', () async {
    var fail = false;
    final client = api((request) {
      if (request.url.path.contains('scrobble')) return envelope({});
      if (fail) return http.Response('private response', 500);
      return envelope({
        'searchResult3': {
          'song': request.url.queryParameters['songOffset'] == '0'
              ? [song('a')]
              : [],
        },
      });
    });
    final service = RecentRadioService(
      client,
      read: (_) async => null,
      write: (_, _) async {},
      now: () => now,
    );
    await service.refresh();
    final preview = service.preview;
    expect(preview!.matches.single.track.id, 'a');
    await client.scrobble('a', now);
    await Future<void>.delayed(Duration.zero);
    expect(service.activityChanged, isTrue);
    expect(identical(service.preview, preview), isTrue);
    fail = true;
    await service.refresh();
    expect(identical(service.preview, preview), isTrue);
    expect(service.error, isNotNull);
    service.dispose();
    client.close();
  });
  test('saved settings are scoped to server/user and newer records are not overwritten', () async {
    final keys = <String>{};
    for (final scope in [
      ('one', 'https://a.example'),
      ('two', 'https://a.example'),
      ('one', 'https://b.example'),
    ]) {
      var writes = 0;
      final client = api(
        (_) => envelope({'searchResult3': {}}),
        user: scope.$1,
        url: scope.$2,
      );
      final service = RecentRadioService(
        client,
        read: (_) async => jsonEncode({'schemaVersion': 99}),
        write: (_, _) async {
          writes++;
        },
      );
      keys.add(service.storageKey);
      await service.configure(const RecentRadioDefinition(days: 14));
      expect(service.storageNotice, contains('only to this session'));
      expect(service.definition.days, 14);
      expect(writes, 0);
      service.dispose();
      client.close();
    }
    expect(keys, hasLength(3));
  });
  test(
    'dispose during an in-flight scan never publishes a late preview',
    () async {
      final gate = Completer<http.Response>();
      final entered = Completer<void>();
      final client = api((_) {
        entered.complete();
        return gate.future;
      });
      final service = RecentRadioService(client, read: (_) async => null);
      final loading = service.refresh();
      await entered.future;
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
  test('changed definition supersedes even an old failed request and persists the latest rule', () async {
    final gate = Completer<http.Response>();
    final entered = Completer<void>();
    var calls = 0;
    String? saved;
    final client = api((_) {
      if (calls++ == 0) {
        entered.complete();
        return gate.future;
      }
      return envelope({'searchResult3': {}});
    });
    final service = RecentRadioService(
      client,
      read: (_) async => null,
      write: (_, value) async => saved = value,
      now: () => now,
    );
    final initial = service.refresh();
    await entered.future;
    final change = service.configure(
      const RecentRadioDefinition(name: 'My radio', days: 7),
    );
    await Future<void>.delayed(Duration.zero);
    gate.complete(http.Response('old failure', 500));
    await Future.wait([initial, change]);
    expect(service.error, isNull);
    expect(service.preview!.definition.days, 7);
    expect(jsonDecode(saved!)['name'], 'My radio');
    service.dispose();
    client.close();
  });
}
