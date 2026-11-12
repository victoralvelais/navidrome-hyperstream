import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hyperstream_client/services/navidrome_client.dart';

http.Response login([
  String user = 'listener',
  String token = 'session.token',
]) => http.Response(jsonEncode({'username': user, 'token': token}), 200);
http.Response count(
  String? total, {
  Object? rows = const [
    {'id': 'a', 'missing': false},
  ],
}) => http.Response(jsonEncode(rows), 200, headers: {'x-total-count': ?total});

NavidromeClient countClient(
  FutureOr<http.Response> Function(http.Request) handler, {
  String user = 'listener',
  String url = 'https://music.example.com/music/',
}) => NavidromeClient(
  serverUrl: url,
  username: user,
  password: 'synthetic',
  httpClient: MockClient((request) async => handler(request)),
)..serverType = 'navidrome';

void main() {
  test('count uses the same account, proxy path and missing filter; token stays out of URLs', () async {
    final requests = <http.Request>[];
    final client = countClient((request) {
      requests.add(request);
      return request.method == 'POST' ? login() : count('1234');
    });
    addTearDown(client.close);
    expect(await client.catalogTrackCount(cancelled: () => false), 1234);
    expect(await client.catalogTrackCount(cancelled: () => false), 1234);
    expect(requests.map((r) => r.url.path), [
      '/music/auth/login',
      '/music/api/song',
      '/music/api/song',
    ]);
    expect(jsonDecode(requests.first.body), {
      'username': 'listener',
      'password': 'synthetic',
    });
    expect(
      requests.first.headers['content-type'],
      contains('application/json'),
    );
    expect(requests[1].headers['x-nd-authorization'], 'Bearer session.token');
    expect(requests[1].url.queryParameters, {
      '_start': '0',
      '_end': '1',
      'missing': 'false',
    });
    expect(requests.every((r) => !r.followRedirects), isTrue);
    expect(
      requests.every(
        (r) =>
            !r.url.toString().contains('session.token') &&
            !r.url.toString().contains('synthetic'),
      ),
      isTrue,
    );
  });
  test('cached expiry renews once; new rejected tokens never loop', () async {
    var logins = 0;
    var expired = false;
    var rejectNew = false;
    final client = countClient((request) {
      if (request.method == 'POST') {
        return login('listener', 'token${++logins}');
      }
      if (rejectNew ||
          (expired &&
              request.headers['x-nd-authorization'] == 'Bearer token1')) {
        return http.Response('', 401);
      }
      return count('2');
    });
    addTearDown(client.close);
    expect(await client.catalogTrackCount(cancelled: () => false), 2);
    expired = true;
    expect(await client.catalogTrackCount(cancelled: () => false), 2);
    expect(logins, 2);
    rejectNew = true;
    expect(await client.catalogTrackCount(cancelled: () => false), isNull);
    expect(logins, 3);
  });
  test('unknown, malformed and inconsistent counts remain unknown; a true empty library is zero', () async {
    final responses = [
      count(null),
      count(''),
      count('-1'),
      count('1.5'),
      count('NaN'),
      count('2,000'),
      count('999999999999999999999999'),
      count('0'),
      count('2', rows: []),
      count('2', rows: {}),
      count(
        '2',
        rows: [
          {'id': 'a', 'missing': true},
        ],
      ),
      count(
        '2',
        rows: [
          {'id': 'a'},
          {'id': 'b'},
        ],
      ),
      http.Response('not json', 200, headers: {'x-total-count': '2'}),
    ];
    for (final response in responses) {
      final client = countClient(
        (request) => request.method == 'POST' ? login() : response,
      );
      expect(await client.catalogTrackCount(cancelled: () => false), isNull);
      client.close();
    }
    final empty = countClient(
      (request) => request.method == 'POST' ? login() : count('0', rows: []),
    );
    expect(await empty.catalogTrackCount(cancelled: () => false), 0);
    empty.close();
  });
  test('native API failures and redirects do not reject the working Subsonic login', () async {
    for (final status in [301, 302, 401, 403, 404, 500]) {
      var gets = 0;
      final client = countClient((request) {
        if (request.url.path.endsWith('ping.view')) {
          return http.Response('{"subsonic-response":{"status":"ok"}}', 200);
        }
        if (request.method == 'POST') {
          return http.Response(
            'private body',
            status,
            headers: {'location': 'https://elsewhere.example.com'},
          );
        }
        gets++;
        return count('2');
      });
      expect(await client.catalogTrackCount(cancelled: () => false), isNull);
      expect(gets, 0);
      await client.ping();
      client.close();
    }
    for (final status in [302, 403, 404, 500]) {
      var calls = 0;
      final client = countClient((request) {
        calls++;
        return request.method == 'POST' ? login() : http.Response('', status);
      });
      expect(await client.catalogTrackCount(cancelled: () => false), isNull);
      expect(calls, 2);
      client.close();
    }
    final client = countClient(
      (_) => throw http.ClientException('private URL'),
    );
    expect(await client.catalogTrackCount(cancelled: () => false), isNull);
    client.close();
  });
  test(
    'wrong account and invalid credentials from login are not reused',
    () async {
      for (final response in [
        login('other'),
        login('listener', ''),
        login('listener', 'unsafe\r\nheader'),
        http.Response('{"token":"session.token"}', 200),
      ]) {
        var requests = 0;
        final client = countClient((_) {
          requests++;
          return response;
        });
        expect(await client.catalogTrackCount(cancelled: () => false), isNull);
        expect(requests, 1);
        client.close();
      }
    },
  );
  test(
    'non-Navidrome, cancellation and disposal do not send later count requests',
    () async {
      var requests = 0;
      var cancelled = false;
      final gate = Completer<http.Response>();
      final client = countClient((_) {
        requests++;
        return gate.future;
      });
      client.serverType = 'other';
      expect(await client.catalogTrackCount(cancelled: () => false), isNull);
      expect(requests, 0);
      client.serverType = 'navidrome';
      final pending = client.catalogTrackCount(cancelled: () => cancelled);
      cancelled = true;
      gate.complete(login());
      expect(await pending, isNull);
      expect(requests, 1);
      client.close();
      expect(await client.catalogTrackCount(cancelled: () => false), isNull);
      expect(requests, 1);
    },
  );
  test('native sessions are isolated across server and user clients', () async {
    for (final (user, host, total) in [
      ('one', 'one.example.com', 5),
      ('two', 'one.example.com', 3),
      ('one', 'two.example.com', 8),
    ]) {
      final client = countClient(
        (request) {
          expect(request.url.host, host);
          if (request.method == 'POST') {
            expect(jsonDecode(request.body)['username'], user);
            return login(user, '$user.$host');
          }
          expect(request.headers['x-nd-authorization'], 'Bearer $user.$host');
          return count('$total');
        },
        user: user,
        url: 'https://$host/',
      );
      expect(await client.catalogTrackCount(cancelled: () => false), total);
      client.close();
    }
  });
  testWidgets(
    'optional count timeout is bounded and never starts a later song request',
    (tester) async {
      final gate = Completer<http.Response>();
      var requests = 0;
      final client = countClient((_) {
        requests++;
        return gate.future;
      });
      final pending = client.catalogTrackCount(cancelled: () => false);
      await tester.pump(const Duration(seconds: 4));
      expect(await pending, isNull);
      gate.complete(login());
      await tester.pump();
      expect(requests, 1);
      client.close();
    },
  );
}
