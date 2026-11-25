import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hyperstream_client/models/library.dart';
import 'package:hyperstream_client/models/source_reference.dart';
import 'package:hyperstream_client/services/music_provider.dart';
import 'package:hyperstream_client/services/music_sources.dart';

Map<String, dynamic> sourceSong(String id, {int disc = 1, int number = 1}) => {
  'trackId': id,
  'title': 'Song $id',
  'artistNames': ['Artist'],
  'duration': 180125,
  'releaseId': 'album',
  'playable': true,
  'discNumber': disc,
  'trackNumber': number,
  'isrc': 'TEST12345678',
  'artwork': 'https://images.example/cover.jpg',
};

void main() {
  test(
    'search keeps source identity, milliseconds and credentials separate',
    () async {
      final provider = MonochromeProvider(
        id: 'source',
        baseUri: Uri.parse('https://source.example/prefix'),
        client: MockClient((request) async {
          expect(request.url.path, '/prefix/search');
          expect(request.url.queryParameters, {'q': 'a & b'});
          expect(request.headers.containsKey('authorization'), isFalse);
          return http.Response(
            jsonEncode({
              'tracks': [sourceSong('one')],
              'releases': [
                {
                  'releaseId': 'album',
                  'title': 'Album',
                  'artistNames': ['Artist'],
                },
              ],
            }),
            200,
          );
        }),
      );
      addTearDown(provider.close);
      final result = await provider.search(' a & b ');
      final track = result.tracks.single;
      expect(track.id, 'external:source:one');
      expect(track.duration, const Duration(milliseconds: 180125));
      expect(track.coverArt, isNull);
      expect(
        track.source!.artwork.toString(),
        'https://images.example/cover.jpg',
      );
      expect(
        provider.streamUri(track.source!).toString(),
        'https://source.example/prefix/track/one',
      );
      expect(result.albums.single.sourceId, 'source');
      expect(
        () => provider.streamUri(
          const SourceReference(sourceId: 'other', trackId: 'one'),
        ),
        throwsA(isA<SourceException>()),
      );
    },
  );

  test('album validates completeness and retains disc order', () async {
    var incomplete = false;
    final provider = MonochromeProvider(
      id: 'source',
      baseUri: Uri.parse('https://source.example'),
      client: MockClient(
        (request) async => http.Response(
          jsonEncode({
            'releaseId': 'album',
            'title': 'Album',
            'artists': [
              {'name': 'Artist'},
            ],
            'trackCount': incomplete ? 3 : 2,
            'tracks': [sourceSong('two', disc: 2), sourceSong('one')],
          }),
          200,
        ),
      ),
    );
    addTearDown(provider.close);
    const album = SourceAlbum(
      id: 'album',
      sourceId: 'source',
      title: 'Album',
      artist: 'Artist',
    );
    final tracks = await provider.album(album);
    expect(tracks.map((t) => t.source!.trackId), ['one', 'two']);
    expect(tracks.every((t) => t.album == 'Album'), isTrue);
    incomplete = true;
    await expectLater(provider.album(album), throwsA(isA<SourceException>()));
  });

  for (final status in [302, 401, 429, 503]) {
    test('source HTTP $status is a sanitized failure', () async {
      var calls = 0;
      final provider = MonochromeProvider(
        id: 'source',
        baseUri: Uri.parse('https://private.example'),
        client: MockClient((_) async {
          calls++;
          return http.Response(
            'secret error details',
            status,
            headers: {'location': 'https://elsewhere.example'},
          );
        }),
      );
      addTearDown(provider.close);
      await expectLater(
        provider.search('song'),
        throwsA(
          isA<SourceException>().having(
            (e) => e.message,
            'safe',
            isNot(contains('secret')),
          ),
        ),
      );
      expect(calls, 1);
    });
  }

  test(
    'download uses its own request and rejects a partial response',
    () async {
      final provider = MonochromeProvider(
        id: 'source',
        baseUri: Uri.parse('https://source.example'),
        client: MockClient((request) async {
          expect(request.url.path, '/track/one');
          expect(request.headers.containsKey('authorization'), isFalse);
          return http.Response.bytes([102, 76, 97, 67], 206);
        }),
      );
      addTearDown(provider.close);
      await expectLater(
        provider.download(
          const SourceReference(sourceId: 'source', trackId: 'one'),
          Completer<void>().future,
        ),
        throwsA(isA<SourceException>()),
      );
    },
  );

  test('source settings restore securely and a failed write keeps the old selection', () async {
    String? value;
    var fail = false;
    final sources = MusicSources(
      read: () async => value,
      write: (next) async {
        if (fail) throw StateError('private details');
        value = next;
      },
    );
    addTearDown(sources.dispose);
    await sources.restore();
    expect(sources.enabled, isFalse);
    await sources.save(endpoint: 'https://source.example/api/', enabled: true);
    final id = sources.sourceId;
    final restored = MusicSources(read: () async => value);
    addTearDown(restored.dispose);
    await restored.restore();
    expect(restored.enabled, isTrue);
    expect(restored.sourceId, id);
    expect(restored.searchSource, isNull);
    await sources.chooseSearchSource(id);
    await sources.save(endpoint: 'https://source.example/api/', enabled: true);
    final scoped = MusicSources(read: () async => value);
    addTearDown(scoped.dispose);
    await scoped.restore();
    expect(scoped.searchSource, id);
    await sources.chooseSearchSource(null);
    expect(sources.searchSource, isNull);
    expect(jsonDecode(value!)['searchSource'], isNull);
    fail = true;
    await expectLater(
      sources.save(endpoint: 'https://other.example', enabled: false),
      throwsA(isA<SourceException>()),
    );
    expect(sources.sourceId, id);
    expect(sources.enabled, isTrue);
    await expectLater(
      sources.chooseSearchSource(id),
      throwsA(isA<SourceException>()),
    );
    expect(sources.searchSource, isNull);
    expect(
      () => MusicSources.parseEndpoint('https://user:password@example.com'),
      throwsFormatException,
    );
    expect(
      () => MusicSources.parseEndpoint('https://example.com?token=secret'),
      throwsFormatException,
    );
  });

  test('external identity can only be restored from a saved queue', () {
    final data = {
      'id': 'one',
      'source': const SourceReference(
        sourceId: 'source',
        trackId: 'one',
      ).toJson(),
    };
    expect(Track.fromJson(data).source, isNull);
    expect(Track.fromJson(data, saved: true).source!.trackId, 'one');
    expect(publicArtwork('https://example.com/cover?secret=x'), isNull);
    expect(publicArtwork('file:///private/file'), isNull);
  });
}
