import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hyperstream_client/services/navidrome_client.dart';

http.Response ok([Map<String, dynamic> data = const {}]) => http.Response(
  jsonEncode({
    'subsonic-response': {'status': 'ok', ...data},
  }),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  NavidromeClient clientWith(
    Future<http.Response> Function(http.Request) handler,
  ) {
    final client = NavidromeClient(
      serverUrl: 'https://music.example.com/navidrome/',
      username: 'a user',
      password: 'not-a-real-password',
      httpClient: MockClient(handler),
    );
    addTearDown(client.close);
    return client;
  }

  test(
    'auth uses a fresh salted token and preserves reverse proxy subpaths',
    () async {
      final requests = <Uri>[];
      final client = clientWith((request) async {
        requests.add(request.url);
        return ok();
      });
      await client.ping();
      await client.ping();
      expect(requests.first.path, '/navidrome/rest/ping.view');
      final parameters = requests.first.queryParameters;
      expect(parameters['u'], 'a user');
      expect(
        parameters['t'],
        md5
            .convert(utf8.encode('not-a-real-password${parameters['s']}'))
            .toString(),
      );
      expect(parameters.containsKey('p'), isFalse);
      expect(requests.first.toString(), isNot(contains('not-a-real-password')));
      expect(parameters['s'], isNot(requests.last.queryParameters['s']));
    },
  );

  test('stream identifiers are encoded as data and request original audio', () {
    final client = clientWith((_) async => ok());
    final uri = client.streamUri('track&u=intruder/#one');
    expect(uri.path, '/navidrome/rest/stream.view');
    expect(uri.queryParameters['id'], 'track&u=intruder/#one');
    expect(uri.queryParameters['u'], 'a user');
    expect(uri.queryParameters['format'], 'raw');
  });

  test('rejects ambiguous addresses and embedded credentials', () {
    for (final url in [
      'music.example.com',
      'ftp://music.example.com',
      'https://a:b@music.example.com',
      'https://music.example.com/?token=abc',
      'https://music.example.com/#login',
    ]) {
      expect(
        () => NavidromeClient.parseServerUrl(url),
        throwsA(isA<NavidromeException>()),
      );
    }
    expect(
      NavidromeClient.parseServerUrl(' http://localhost:4664 ').toString(),
      'http://localhost:4664/',
    );
  });

  test('paginates albums and accepts an empty library', () async {
    final client = clientWith((request) async {
      expect(request.url.queryParameters['offset'], '40');
      expect(request.url.queryParameters['size'], '40');
      expect(request.url.queryParameters['type'], 'newest');
      return ok({'albumList2': <String, dynamic>{}});
    });
    expect(await client.albums(offset: 40), isEmpty);
  });

  test(
    'search encodes queries and pages each result type independently',
    () async {
      final client = clientWith((request) async {
        expect(request.url.path, '/navidrome/rest/search3.view');
        final parameters = request.url.queryParameters;
        expect(parameters['query'], 'Café & u=someone');
        expect(parameters['u'], 'a user');
        expect(parameters['artistCount'], '0');
        expect(parameters['albumCount'], '0');
        expect(parameters['albumOffset'], '0');
        expect(parameters['songCount'], '20');
        expect(parameters['songOffset'], '40');
        return ok({
          'searchResult3': {
            'song': [
              {
                'id': 'song',
                'title': 'Café',
                'coverArt': 'art',
                'duration': 90,
              },
            ],
          },
        });
      });
      final results = await client.search(
        '  Café & u=someone  ',
        albumCount: 0,
        songOffset: 40,
      );
      expect(results.albums, isEmpty);
      expect(results.tracks.single.title, 'Café');
      expect(results.tracks.single.coverArt, 'art');
    },
  );

  test('blank search never requests the entire server library', () async {
    final client = clientWith(
      (_) async => throw StateError('Unexpected request'),
    );
    final results = await client.search('   ');
    expect(results.albums, isEmpty);
    expect(results.tracks, isEmpty);
  });

  test('search distinguishes no matches from a malformed payload', () async {
    final empty = clientWith(
      (_) async => ok({'searchResult3': <String, dynamic>{}}),
    );
    expect((await empty.search('nothing')).tracks, isEmpty);
    for (final payload in [
      <String, dynamic>{},
      {
        'searchResult3': {'album': 'secret'},
      },
      {
        'searchResult3': {
          'song': [
            {'title': 'missing id'},
          ],
        },
      },
    ]) {
      final client = clientWith((_) async => ok(payload));
      await expectLater(
        client.search('query'),
        throwsA(
          isA<NavidromeException>().having(
            (e) => e.message,
            'message',
            'The server returned invalid search results.',
          ),
        ),
      );
    }
  });

  test('reads unicode album names and fractional track durations', () async {
    final client = clientWith(
      (request) async => request.url.path.contains('getAlbumList2')
          ? ok({
              'albumList2': {
                'album': [
                  {'id': 'a', 'name': 'Café 🎵', 'artist': 'Artist'},
                ],
              },
            })
          : ok({
              'album': {
                'song': [
                  {'id': 't', 'title': 'Song', 'duration': 12.5, 'track': 2},
                ],
              },
            }),
    );
    expect((await client.albums()).single.name, 'Café 🎵');
    final track = (await client.tracks('a')).single;
    expect(track.duration, const Duration(seconds: 12));
    expect(track.number, 2);
  });

  test('API errors do not expose server-supplied secrets', () async {
    final client = clientWith(
      (_) async => http.Response(
        jsonEncode({
          'subsonic-response': {
            'status': 'failed',
            'error': {'code': 40, 'message': 'private-token'},
          },
        }),
        200,
      ),
    );
    await expectLater(
      client.ping(),
      throwsA(
        isA<NavidromeException>()
            .having(
              (e) => e.message,
              'message',
              'Check your username and password.',
            )
            .having(
              (e) => e.authenticationRejected,
              'authentication rejected',
              isTrue,
            ),
      ),
    );
  });

  test('transport errors do not expose credential-bearing URLs', () async {
    final client = clientWith(
      (request) async => throw http.ClientException('secret', request.url),
    );
    await expectLater(
      client.ping(),
      throwsA(
        isA<NavidromeException>().having(
          (e) => e.message,
          'message',
          allOf(isNot(contains('secret')), isNot(contains('?u='))),
        ),
      ),
    );
  });

  test('redirects are disabled on credential-bearing API requests', () async {
    final client = clientWith((request) async {
      expect(request.followRedirects, isFalse);
      return http.Response(
        '',
        302,
        headers: {'location': 'https://different.example'},
      );
    });
    await expectLater(
      client.ping(),
      throwsA(
        isA<NavidromeException>().having(
          (e) => e.message,
          'message',
          contains('final address'),
        ),
      ),
    );
  });

  test('HTML and malformed responses become understandable failures', () async {
    for (final body in [
      '<html>Proxy login</html>',
      '{}',
      '{"subsonic-response":[]}',
    ]) {
      final client = clientWith((_) async => http.Response(body, 200));
      await expectLater(client.ping(), throwsA(isA<NavidromeException>()));
    }
  });

  test(
    'malformed album payload is not mistaken for an empty library',
    () async {
      final client = clientWith((_) async => ok());
      await expectLater(client.albums(), throwsA(isA<NavidromeException>()));
    },
  );
}
