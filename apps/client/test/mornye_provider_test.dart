import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyperstream_client/models/source_reference.dart';
import 'package:hyperstream_client/services/mornye_provider.dart';
import 'package:hyperstream_client/services/mornye_sources.dart';
import 'package:hyperstream_client/services/music_provider.dart';
import 'package:hyperstream_client/services/playback_diagnostics.dart';
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
      diagnostics: PlaybackDiagnostics(),
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
            extension('ytmusic-spotiflac'),
            extension('soundcloud'),
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
    'SoundCloud links use its own resolver and strip tracking tokens',
    () async {
      final requests = <Map<String, dynamic>>[];
      operation = (r) async {
        requests.add(r);
        return {
          'track': {
            'id': '12345',
            'name': 'Midnight remix',
            'artists': 'Independent DJ',
            'duration_ms': 240000,
            'is_playable': true,
          },
        };
      };
      final provider = MornyeProvider(sources, 'soundcloud', proxy);
      for (final link in [
        'https://soundcloud.com/artist/track?utm_source=test',
        'https://www.soundcloud.com/track/remix#t=3',
        'https://m.soundcloud.com/artist/remix',
        'https://on.soundcloud.com/example?si=tracking',
      ]) {
        final found = await provider.search(link);
        final track = found.tracks.single;
        expect(track.title, 'Midnight remix');
        expect(track.source!.sourceId, 'mornye:soundcloud');
        expect(track.source!.trackId, '12345');
        expect(track.duration, const Duration(minutes: 4));
      }
      expect(requests.every((r) => r['method'] == 'handleUrl'), true);
      expect(requests.map((r) => r['args'][0]), [
        'https://soundcloud.com/artist/track',
        'https://soundcloud.com/track/remix',
        'https://soundcloud.com/artist/remix',
        'https://on.soundcloud.com/example',
      ]);
      for (final link in [
        'http://soundcloud.com/artist/track',
        'https://soundcloud.com.evil.test/artist/track',
        'https://user:secret@soundcloud.com/artist/track',
        'https://soundcloud.com:9443/artist/track',
        'https://soundcloud.com/artist',
        'https://soundcloud.com/artist/likes',
        'https://soundcloud.com/artist/track/private-token',
        'https://on.soundcloud.com/artist/track',
      ]) {
        await expectLater(
          provider.search(link),
          throwsA(isA<SourceException>()),
        );
      }
      expect(requests, hasLength(4));
    },
  );

  test(
    'SoundCloud set links retain repeats and expose unavailable entries',
    () async {
      operation = (r) async {
        expect(r['method'], 'handleUrl');
        expect(r['args'], ['https://soundcloud.com/artist/sets/practice']);
        return {
          'type': 'playlist',
          'name': 'Practice',
          'total_tracks': 3,
          'tracks': [
            for (final id in ['123', '456', '123'])
              {'id': id, 'name': 'Upload $id', 'is_playable': id != '456'},
          ],
        };
      };
      final provider = MornyeProvider(sources, 'soundcloud', proxy);
      final found = await provider.search(
        'https://soundcloud.com/artist/sets/practice?si=tracking',
      );
      expect(
        found.albums.single.id,
        'link:https://soundcloud.com/artist/sets/practice',
      );
      final tracks = await provider.album(found.albums.single);
      expect(tracks.map((t) => t.source!.trackId), ['123', '456', '123']);
      expect(tracks[1].source!.available, false);
    },
  );

  test(
    'SoundCloud acquisition keeps the upload and uses its returned format',
    () async {
      await sources.choose(audio: 'tidal-web');
      const ref = SourceReference(
        sourceId: 'mornye:soundcloud',
        trackId: '12345',
      );
      final calls = <String>[];
      String? downloaded;
      operation = (r) async {
        calls.add(r['method'] as String);
        expect(r['id'], 'soundcloud');
        expect(r['args'][0], '12345');
        expect(r['args'][1], 'aac_160');
        if (r['method'] == 'hyperstreamResolve') return {'prepare': true};
        downloaded = (r['args'][2] as String).replaceFirst('.m4a', '.mp3');
        await File(downloaded!).writeAsBytes([1, 2, 3]);
        return {'success': true, 'file_path': downloaded};
      };
      expect(
        await MornyeAcquisition(sources).resolve(ref, Completer<void>().future),
        {'prepare': true, 'sourceId': 'mornye:soundcloud'},
      );
      final response = await MornyeProvider(
        sources,
        'soundcloud',
        proxy,
      ).download(ref, Completer<void>().future);
      expect(response.headers['content-type'], 'audio/mpeg');
      expect(await response.stream.toBytes(), [1, 2, 3]);
      expect(await File(downloaded!).exists(), false);
      expect(calls, ['hyperstreamResolve', 'hyperstreamDownload']);
    },
  );

  test('SoundCloud unavailable responses are actionable without exposing provider details', () async {
    operation = (r) async => r['op'] == 'pending'
        ? null
        : {
            'success': false,
            'error_code': 'track_unavailable',
            'error_message': 'https://example.test/?secret=hidden',
          };
    await expectLater(
      MornyeAcquisition(sources).resolve(
        const SourceReference(sourceId: 'mornye:soundcloud', trackId: '12345'),
        Completer<void>().future,
      ),
      throwsA(
        isA<SourceException>().having(
          (e) => e.message,
          'message',
          'This SoundCloud upload does not offer a full playable stream. Try another upload.',
        ),
      ),
    );
    expect(sources.verification.value, isNull);
  });

  test(
    'YouTube links resolve exact uploads synchronously and reject lookalikes',
    () async {
      final requests = <Map<String, dynamic>>[];
      operation = (r) async {
        requests.add(r);
        return {
          'id': r['args'][0],
          'name': 'A homemade remix',
          'artists': 'Uploader',
          'duration_ms': 145000,
          'cover_url': 'https://i.ytimg.com/vi/abcdefghijk/hqdefault.jpg',
        };
      };
      final provider = MornyeProvider(sources, 'ytmusic-spotiflac', proxy);
      for (final link in [
        'https://www.youtube.com/watch?v=abcdefghijk&list=PLother',
        'https://music.youtube.com/watch?v=abcdefghijk',
        'https://youtu.be/abcdefghijk?t=20',
        'https://m.youtube.com/shorts/abcdefghijk',
        'https://www.youtube.com/live/abcdefghijk',
      ]) {
        final found = await provider.search(link);
        expect(found.tracks.single.source!.trackId, 'abcdefghijk');
        expect(found.tracks.single.title, 'A homemade remix');
        expect(found.tracks.single.duration, const Duration(seconds: 145));
        expect(found.tracks.single.source!.artwork?.host, 'i.ytimg.com');
      }
      expect(requests.every((r) => r['method'] == 'getTrack'), true);
      for (final link in [
        'https://youtube.com.evil.test/watch?v=abcdefghijk',
        'https://user:pass@youtube.com/watch?v=abcdefghijk',
        'https://youtube.com/watch?v=bad',
        'https://youtube.com/@channel',
      ]) {
        await expectLater(
          provider.search(link),
          throwsA(isA<SourceException>()),
        );
      }
      expect(requests, hasLength(5));
    },
  );

  test('YouTube public playlists retain upload IDs and repeat order', () async {
    operation = (r) async {
      expect(r['method'], 'getPlaylist');
      expect(r['args'], ['PLpublic']);
      return {
        'name': 'Practice uploads',
        'total_tracks': 3,
        'tracks': [
          for (final id in ['abcdefghijk', 'lmnopqrstuv', 'abcdefghijk'])
            {'id': id, 'name': 'Upload $id', 'artists': 'Uploader'},
        ],
      };
    };
    final provider = MornyeProvider(sources, 'ytmusic-spotiflac', proxy);
    final found = await provider.search(
      'https://youtube.com/playlist?list=PLpublic',
    );
    expect(found.albums.single.id, 'playlist:PLpublic');
    final tracks = await provider.album(found.albums.single);
    expect(tracks.map((t) => t.source!.trackId), [
      'abcdefghijk',
      'lmnopqrstuv',
      'abcdefghijk',
    ]);
  });

  test(
    'YouTube acquisition uses best audio and the actual returned format',
    () async {
      final recording = const SourceReference(
        sourceId: 'mornye:ytmusic-spotiflac',
        trackId: 'abcdefghijk',
      );
      final calls = <String>[];
      operation = (r) async {
        calls.add(r['method'] as String);
        expect(r['id'], 'ytmusic-spotiflac');
        expect(r['args'][0], 'abcdefghijk');
        expect(r['args'][1], 'best');
        if (r['method'] == 'hyperstreamResolve') return {'prepare': true};
        final path = (r['args'][2] as String).replaceFirst('.m4a', '.opus');
        await File(path).writeAsBytes([1, 2, 3]);
        return {'success': true, 'file_path': path};
      };
      final acquisition = MornyeAcquisition(sources);
      expect(await acquisition.resolve(recording, Completer<void>().future), {
        'prepare': true,
        'sourceId': 'mornye:ytmusic-spotiflac',
      });
      final response = await MornyeProvider(
        sources,
        'ytmusic-spotiflac',
        proxy,
      ).download(recording, Completer<void>().future);
      expect(response.headers['content-type'], 'audio/ogg');
      expect(await response.stream.toBytes(), [1, 2, 3]);
      expect(calls, ['hyperstreamResolve', 'hyperstreamDownload']);
    },
  );

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
    'Spotify matching passes ISRC and duration and links the playback report',
    () async {
      await sources.choose(audio: 'tidal-web');
      operation = (r) async {
        if (r['method'] == 'getTrack') {
          return {
            'id': 'private-spotify-recording',
            'name': 'Song',
            'artists': 'Artist',
            'isrc': 'SYNTHETICISRC',
            'duration_ms': 120000,
          };
        }
        expect(r['id'], 'tidal-web');
        if (r['method'] == 'hyperstreamResolve') {
          expect(r['args'][0], 'private-tidal-recording');
          return {'url': 'https://private-media.example/audio?token=secret'};
        }
        expect(r['args'][0], 'SYNTHETICISRC');
        expect(r['args'][3]['duration_ms'], 120000);
        return {'available': true, 'track_id': 'private-tidal-recording'};
      };
      final acquisition = MornyeAcquisition(sources);
      final abort = Completer<void>().future;
      final resolved = await acquisition.resolve(
        const SourceReference(
          sourceId: 'mornye:spotify-web',
          trackId: 'private-spotify-recording',
        ),
        abort,
      );
      expect(resolved['sourceId'], 'mornye:tidal-web');
      final report = sources.diagnostics.report();
      final events = (jsonDecode(report) as Map)['events'] as List;
      final match = events.singleWhere((event) => event['stage'] == 'match');
      final resolve = events.last;
      final catalog = events.firstWhere(
        (event) => event['method'] == 'getTrack',
      );
      expect(catalog['recording'], match['recording']);
      expect(match['matched_recording'], resolve['recording']);
      expect(match['recording'], isNot(match['matched_recording']));
      expect(resolve['method'], 'hyperstreamResolve');
      expect(resolve['outcome'], 'ready');
      expect(report, isNot(contains('private-')));
      expect(report, isNot(contains('token=secret')));
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
