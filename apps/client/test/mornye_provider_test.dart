import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyperstream_client/models/source_reference.dart';
import 'package:hyperstream_client/services/mornye_provider.dart';
import 'package:hyperstream_client/services/mornye_sources.dart';
import 'package:hyperstream_client/services/music_provider.dart';
import 'package:hyperstream_client/services/source_stream_proxy.dart';
import 'package:mornye_host/mornye_host.dart';

Map<String, dynamic> extension(String id, {bool audio = true}) => {
  'id': id,
  'display_name': id,
  'version': '1.0.0',
  'download_url': 'https://example.test/provider.sflx',
  'sha256': '0' * 64,
  'audio': audio,
  'installed': true,
  'enabled': true,
};
void main() {
  test('mixed search distinguishes songs, albums, playlists and artists', () {
    final results = MornyeProvider.parseSearch('tidal-web', [
      {
        'id': 't1',
        'name': 'Song',
        'item_type': 'track',
        'artists': 'Artist',
        'duration_ms': 12500,
        'disc_number': 0,
      },
      {'id': 'a1', 'name': 'Album', 'item_type': 'album', 'total_tracks': 10},
      {
        'id': 'p1',
        'name': 'Playlist',
        'item_type': 'playlist',
        'total_tracks': 4,
      },
      {'id': 'artist1', 'name': 'Artist', 'item_type': 'artist'},
    ]);
    expect(results.tracks.single.title, 'Song');
    expect(results.tracks.single.duration, const Duration(milliseconds: 12500));
    expect(results.tracks.single.source!.disc, 1);
    expect(results.albums.map((a) => a.id), ['a1', 'playlist:p1']);
    expect(results.tracks.single.source!.toJson().containsKey('url'), false);
  });
  test('links require the selected provider’s actual public hostname', () {
    expect(
      MornyeProvider.acceptsLink(
        'spotify-web',
        Uri.parse('https://open.spotify.com/playlist/public?si=example'),
      ),
      true,
    );
    for (final link in [
      'https://open.spotify.com.evil.test/playlist/a',
      'http://open.spotify.com/playlist/a',
      'https://user:pass@open.spotify.com/playlist/a',
    ]) {
      expect(MornyeProvider.acceptsLink('spotify-web', Uri.parse(link)), false);
    }
  });

  late Directory root;
  late MornyeSources sources;
  late SourceStreamProxy proxy;
  late Map<String, String> store;
  late Future<dynamic> Function(Map<String, dynamic>) operation;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('hyperstream-mornye-test-');
    store = {};
    operation = (r) async => null;
    sources = MornyeSources(
      directory: () async => root,
      read: (k) async => store[k],
      write: (k, v) async {
        store[k] = v;
      },
      native: (r) async {
        if (r['op'] == 'init') {
          await Directory('${r['root']}/downloads').create(recursive: true);
          return null;
        }
        if (r['op'] == 'list') {
          return [
            extension('spotify-web', audio: false),
            extension('tidal-web'),
          ];
        }
        if (r['op'] == 'ffmpeg_poll') return [];
        return operation(r);
      },
    );
    await sources.restore();
    expect(sources.error, isNull);
    proxy = SourceStreamProxy(sources);
  });
  tearDown(() async {
    await proxy.close();
    sources.dispose();
    await root.delete(recursive: true);
  });

  test(
    'playlist links open a collection and retain repeat tracks in order',
    () async {
      final requests = <Map<String, dynamic>>[];
      operation = (r) async {
        requests.add(r);
        return {
          'success': true,
          'type': 'playlist',
          'name': 'Practice',
          'tracks': [
            {
              'id': 'b',
              'name': 'Second',
              'artists': 'Artist',
              'album_name': 'Record',
              'item_type': 'track',
            },
            {
              'id': 'a',
              'name': 'First',
              'artists': 'Artist',
              'album_name': 'Record',
              'item_type': 'track',
            },
            {
              'id': 'b',
              'name': 'Second',
              'artists': 'Artist',
              'album_name': 'Record',
              'item_type': 'track',
            },
          ],
        };
      };
      final provider = MornyeProvider(sources, 'spotify-web', proxy);
      final search = await provider.search(
        'https://open.spotify.com/playlist/public',
      );
      expect(search.albums.single.title, 'Practice');
      final tracks = await provider.album(search.albums.single);
      expect(tracks.map((t) => t.source!.trackId), ['b', 'a', 'b']);
      expect(requests.every((r) => r['method'] == 'getPlaylist'), true);
    },
  );
  test(
    'incomplete collections are not silently offered as full downloads',
    () async {
      operation = (r) async => {
        'total_tracks': 3,
        'tracks': [
          {'id': 'a', 'name': 'Song'},
        ],
      };
      final provider = MornyeProvider(sources, 'tidal-web', proxy);
      expect(
        provider.album(
          const SourceAlbum(
            id: 'a',
            sourceId: 'mornye:tidal-web',
            title: 'Album',
            artist: 'Artist',
          ),
        ),
        throwsA(isA<SourceException>()),
      );
    },
  );
  test(
    'Spotify matching passes ISRC and duration to chosen audio provider',
    () async {
      await sources.choose(audio: 'tidal-web');
      operation = (r) async {
        if (r['method'] == 'getTrack') {
          return {
            'id': 's',
            'name': 'Song',
            'artists': 'Artist',
            'isrc': 'SYNTHETICISRC',
            'duration_ms': 120000,
          };
        }
        expect(r['id'], 'tidal-web');
        expect(r['args'][0], 'SYNTHETICISRC');
        expect(r['args'][3]['duration_ms'], 120000);
        return {'available': true, 'track_id': 'matched'};
      };
      final match = await MornyeAcquisition(sources).match(
        const SourceReference(sourceId: 'mornye:spotify-web', trackId: 's'),
        Completer<void>().future,
      );
      expect(match, ('tidal-web', 'matched'));
    },
  );
  test('verification failure surfaces a provider action without leaking native URLs', () async {
    operation = (r) async {
      if (r['op'] == 'pending') {
        return {'auth_url': 'https://example.test/verify?secret=hidden'};
      }
      throw const MornyeHostException(
        'Error at https://example.test/?secret=hidden',
      );
    };
    await expectLater(
      sources.execute({
        'op': 'call',
        'id': 'tidal-web',
        'method': 'getTrack',
        'args': ['t'],
      }),
      throwsA(isA<ProviderVerificationRequired>()),
    );
    expect(sources.verification.value, 'tidal-web');
  });
  test(
    'provider output streams into import then removes private original',
    () async {
      String? output;
      operation = (r) async {
        output = r['args'][2] as String;
        await File(output!).writeAsBytes([1, 2, 3, 4]);
        return {'success': true, 'file_path': output};
      };
      final response = await MornyeProvider(sources, 'tidal-web', proxy)
          .download(
            const SourceReference(sourceId: 'mornye:tidal-web', trackId: 't'),
            Completer<void>().future,
          );
      expect(await response.stream.toBytes(), [1, 2, 3, 4]);
      expect(await File(output!).exists(), false);
    },
  );
  test(
    'cancelled native downloads are awaited before staging cleanup',
    () async {
      final abort = Completer<void>();
      final cancelled = Completer<void>();
      final started = Completer<String>();
      operation = (r) async {
        if (r['op'] == 'cancel') {
          cancelled.complete();
          return null;
        }
        final path = r['args'][2] as String;
        started.complete(path);
        await cancelled.future;
        await File(path).writeAsBytes([1, 2]);
        return {'success': true, 'file_path': path};
      };
      final download = MornyeAcquisition(sources).download(
        const SourceReference(sourceId: 'mornye:tidal-web', trackId: 't'),
        abort.future,
      );
      final assertion = expectLater(download, throwsA(isA<SourceException>()));
      final path = await started.future;
      abort.complete();
      await assertion;
      expect(await File(path).exists(), false);
    },
  );
}
