import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hyperstream_client/models/library.dart';
import 'package:hyperstream_client/services/library_collections.dart';
import 'package:hyperstream_client/services/navidrome_client.dart';

import 'support/collection_server.dart';

void main() {
  late CollectionServer server;
  late NavidromeClient client;
  late LibraryCollections store;
  void setup([Future<http.Response> Function(http.Request)? handler]) {
    server = CollectionServer();
    client = NavidromeClient(
      serverUrl: 'https://music.example.com/navidrome',
      username: 'test',
      password: 'test',
      httpClient: MockClient(handler ?? server.handle),
    );
    store = LibraryCollections(client);
    addTearDown(() {
      store.dispose();
      client.close();
    });
  }

  test('rating changes wait for acknowledgement and failures preserve the prior rating', () async {
    final response = Completer<http.Response>();
    var fail = false;
    setup((request) async => fail ? http.Response('', 500) : response.future);
    const song = Track(
      id: 'song',
      title: 'Song',
      artist: 'Artist',
      album: 'Album',
      duration: Duration.zero,
      userRating: 2,
    );
    final save = store.rate(song, 5);
    expect(store.ratingPending(song), isTrue);
    expect(store.rating(song), 2);
    response.complete(
      http.Response('{"subsonic-response":{"status":"ok"}}', 200),
    );
    await save;
    expect(store.rating(song), 5);
    expect(store.ratingPending(song), isFalse);
    fail = true;
    await expectLater(store.rate(song, 0), throwsA(isA<NavidromeException>()));
    expect(store.rating(song), 5);
  });

  test(
    'favorites use the correct album/song ids and failed writes preserve state',
    () async {
      setup();
      final song = Track.fromJson(server.song('one'));
      final album = Album.fromJson(server.album);
      await store.toggleSong(song);
      await store.toggleAlbum(album);
      expect(server.requests[0].queryParameters['id'], 'one');
      expect(
        server.requests[0].queryParameters.containsKey('albumId'),
        isFalse,
      );
      expect(server.requests[1].queryParameters['albumId'], 'album');
      await store.refreshFavorites();
      expect(store.favoriteSongs.single.id, 'one');
      expect(store.favoriteAlbums.single.id, 'album');
      server.failFavorites = true;
      await expectLater(
        store.toggleSong(song),
        throwsA(isA<NavidromeException>()),
      );
      expect(store.isFavorite('one', album: false), isTrue);
      expect(store.favoritePending('one', album: false), isFalse);
      server.failFavorites = false;
      await store.toggleSong(song);
      expect(server.requests.last.path, '/navidrome/rest/unstar.view');
      expect(store.favoriteSongs, isEmpty);
      expect(store.favoriteAlbums.single.id, 'album');
    },
  );

  test('a delayed read cannot undo a newer favorite and duplicate taps send one write', () async {
    final stale = Completer<http.Response>();
    final write = Completer<http.Response>();
    var reads = 0;
    var writes = 0;
    setup((request) async {
      if (request.url.path.endsWith('getStarred2.view') && reads++ == 0) {
        return stale.future;
      }
      if (request.url.path.endsWith('star.view')) {
        writes++;
        await write.future;
      }
      return server.handle(request);
    });
    final loading = store.refreshFavorites();
    final song = Track.fromJson(server.song('one'));
    final first = store.toggleSong(song);
    await store.toggleSong(song);
    expect(store.isFavorite('one', album: false), isFalse);
    write.complete(collectionResponse({}));
    await first;
    stale.complete(collectionResponse({'starred2': <String, dynamic>{}}));
    await loading;
    expect(writes, 1);
    expect(reads, 2);
    expect(store.favoriteSongs.single.id, 'one');
  });

  test(
    'empty collections and malformed payloads have different outcomes',
    () async {
      setup(
        (request) async => collectionResponse(
          request.url.queryParameters['id'] == 'bad'
              ? {
                  'playlist': {'entry': []},
                }
              : {
                  'playlists': <String, dynamic>{},
                  'starred2': <String, dynamic>{},
                },
        ),
      );
      expect(await client.playlists(), isEmpty);
      expect((await client.favorites()).tracks, isEmpty);
      await expectLater(
        client.playlist('bad'),
        throwsA(isA<NavidromeException>()),
      );
    },
  );

  test('playlist edits preserve existing entries and remove a duplicate by position', () async {
    setup();
    expect((await client.playlists()).length, 2);
    final initial = await client.playlist('owned');
    expect(initial.tracks.map((t) => t.id), ['one', 'two', 'one']);
    await store.removeFromPlaylist(initial, 2);
    final removal = server.requests.singleWhere(
      (uri) => uri.queryParameters.containsKey('songIndexToRemove'),
    );
    expect(removal.queryParameters['songIndexToRemove'], '2');
    expect((await client.playlist('owned')).tracks.map((t) => t.id), [
      'one',
      'two',
    ]);
    await store.addToPlaylist('owned', 'two');
    await store.renamePlaylist('owned', '  Café & Mix  ');
    final result = await client.playlist('owned');
    expect(result.name, 'Café & Mix');
    expect(result.tracks.map((t) => t.id), ['one', 'two', 'two']);
    expect(store.playlists!.first.name, 'Café & Mix');
  });

  test(
    'stale playlist removal is rejected without sending a mutation',
    () async {
      setup();
      final snapshot = await client.playlist('owned');
      server.playlists['owned']!['songs'] = <String>['two', 'one', 'one'];
      await expectLater(
        store.removeFromPlaylist(snapshot, 1),
        throwsA(
          isA<NavidromeException>().having(
            (e) => e.message,
            'message',
            contains('changed'),
          ),
        ),
      );
      expect(
        server.requests.where(
          (uri) => uri.path.endsWith('updatePlaylist.view'),
        ),
        isEmpty,
      );
    },
  );

  test(
    'creating a playlist with a song uses a single creation request',
    () async {
      setup();
      final playlist = await store.createPlaylist(
        '  My mix & more  ',
        songId: 'one',
      );
      expect(playlist.name, 'My mix & more');
      expect(playlist.tracks.single.id, 'one');
      final create = server.requests.singleWhere(
        (uri) => uri.path.endsWith('createPlaylist.view'),
      );
      expect(create.queryParameters['name'], 'My mix & more');
      expect(create.queryParameters['songId'], 'one');
      expect(create.queryParameters.containsKey('playlistId'), isFalse);
      await expectLater(
        store.createPlaylist('   '),
        throwsA(isA<NavidromeException>()),
      );
      expect(
        server.requests
            .where((uri) => uri.path.endsWith('createPlaylist.view'))
            .length,
        1,
      );
    },
  );

  test(
    'permission failures are surfaced without changing the playlist',
    () async {
      setup();
      await expectLater(
        store.renamePlaylist('shared', 'No'),
        throwsA(
          isA<NavidromeException>().having(
            (e) => e.message,
            'message',
            contains('permission'),
          ),
        ),
      );
      expect((await client.playlist('shared')).name, 'Shared set');
      expect(store.playlistRevision, 0);
    },
  );
}
