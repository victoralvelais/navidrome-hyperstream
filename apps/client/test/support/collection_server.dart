import 'dart:convert';

import 'package:http/http.dart' as http;

http.Response collectionResponse(Map<String, dynamic> body) => http.Response(
  jsonEncode({
    'subsonic-response': {'status': 'ok', ...body},
  }),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

/// A small Subsonic fixture; tests also inspect the actual request parameters.
class CollectionServer {
  final requests = <Uri>[];
  final favoriteSongs = <String>{};
  final favoriteAlbums = <String>{};
  bool failFavorites = false;
  final songs = <String, Map<String, dynamic>>{
    'one': {
      'id': 'one',
      'title': 'First song',
      'artist': 'Test artist',
      'album': 'Test album',
      'duration': 180,
    },
    'two': {
      'id': 'two',
      'title': 'Second song',
      'artist': 'Test artist',
      'album': 'Test album',
      'duration': 120,
    },
  };
  final album = <String, dynamic>{
    'id': 'album',
    'name': 'Test album',
    'artist': 'Test artist',
    'songCount': 2,
  };
  final playlists = <String, Map<String, dynamic>>{
    'owned': {
      'id': 'owned',
      'name': 'Weekend',
      'owner': 'test',
      'songs': <String>['one', 'two', 'one'],
    },
    'shared': {
      'id': 'shared',
      'name': 'Shared set',
      'owner': 'another-user',
      'songs': <String>['two'],
    },
  };

  Map<String, dynamic> song(String id) => {
    ...songs[id]!,
    if (favoriteSongs.contains(id)) 'starred': '2026-11-10T00:00:00Z',
  };
  Map<String, dynamic> playlist(String id) {
    final data = playlists[id]!;
    final ids = data['songs'] as List<String>;
    return {
      'id': id,
      'name': data['name'],
      'owner': data['owner'],
      'songCount': ids.length,
      'entry': ids.map(song).toList(),
    };
  }

  Future<http.Response> handle(http.Request request) async {
    requests.add(request.url);
    final method = request.url.path.split('/').last.replaceAll('.view', '');
    final p = request.url.queryParameters;
    switch (method) {
      case 'getAlbumList2':
        return collectionResponse({
          'albumList2': {
            'album': [album],
          },
        });
      case 'getAlbum':
        return collectionResponse({
          'album': {
            'song': [song('one'), song('two')],
          },
        });
      case 'getStarred2':
        return collectionResponse({
          'starred2': {
            'album': favoriteAlbums.isEmpty
                ? []
                : [
                    {...album, 'starred': '2026-11-10T00:00:00Z'},
                  ],
            'song': favoriteSongs.map(song).toList(),
          },
        });
      case 'star':
      case 'unstar':
        if (failFavorites) return http.Response('private-server-details', 503);
        final set = p.containsKey('albumId') ? favoriteAlbums : favoriteSongs;
        final id = p['albumId'] ?? p['id']!;
        if (method == 'star') {
          set.add(id);
        } else {
          set.remove(id);
        }
        return collectionResponse({});
      case 'getPlaylists':
        return collectionResponse({
          'playlists': {'playlist': playlists.keys.map(playlist).toList()},
        });
      case 'getPlaylist':
        return collectionResponse({'playlist': playlist(p['id']!)});
      case 'createPlaylist':
        final id = 'new-${playlists.length}';
        playlists[id] = {
          'id': id,
          'name': p['name'],
          'owner': 'test',
          'songs': <String>[if (p['songId'] != null) p['songId']!],
        };
        return collectionResponse({'playlist': playlist(id)});
      case 'updatePlaylist':
        final data = playlists[p['playlistId']]!;
        if (data['owner'] != 'test') {
          return http.Response(
            jsonEncode({
              'subsonic-response': {
                'status': 'failed',
                'error': {'code': 50},
              },
            }),
            200,
          );
        }
        if (p['name'] != null) data['name'] = p['name'];
        if (p['songIdToAdd'] != null) {
          (data['songs'] as List<String>).add(p['songIdToAdd']!);
        }
        if (p['songIndexToRemove'] != null) {
          (data['songs'] as List<String>).removeAt(
            int.parse(p['songIndexToRemove']!),
          );
        }
        return collectionResponse({});
      default:
        throw StateError('Unexpected fixture endpoint: $method');
    }
  }
}
