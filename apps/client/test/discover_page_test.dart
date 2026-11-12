import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hyperstream_client/features/search/discover_page.dart';
import 'package:hyperstream_client/services/navidrome_client.dart';

void main() {
  testWidgets(
    'discover opens real genre results and pull-to-refresh replaces them',
    (tester) async {
      final requests = <Uri>[];
      var generation = 1;
      final client = NavidromeClient(
        serverUrl: 'https://example.com/music',
        username: 'test',
        password: 'synthetic',
        httpClient: MockClient((request) async {
          requests.add(request.url);
          return http.Response(
            jsonEncode({
              'subsonic-response': {
                'status': 'ok',
                if (request.url.path.endsWith('getGenres.view'))
                  'genres': {
                    'genre': [
                      {'value': 'Rock', 'albumCount': 2},
                    ],
                  }
                else
                  'albumList2': {
                    'album': [
                      {
                        'id': 'album',
                        'name': 'Album $generation',
                        'artist': 'Artist',
                      },
                    ],
                  },
              },
            }),
            200,
          );
        }),
      );
      addTearDown(client.close);
      String? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DiscoverPage(client: client, onAlbum: (a) => selected = a.id),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Browse your library'), findsOneWidget);
      expect(requests.where((u) => u.path.contains('search3')), isEmpty);
      await tester.ensureVisible(find.text('Rock'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rock'));
      await tester.pumpAndSettle();
      expect(requests.last.queryParameters['genre'], 'Rock');
      expect(requests.last.queryParameters['type'], 'byGenre');
      expect(find.text('Album 1'), findsOneWidget);
      generation = 2;
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 400));
      await tester.pumpAndSettle();
      expect(find.text('Album 1'), findsNothing);
      expect(find.text('Album 2'), findsOneWidget);
      await tester.tap(find.text('Album 2'));
      expect(selected, 'album');
      await tester.dragFrom(const Offset(12, 180), const Offset(110, 4));
      await tester.pumpAndSettle();
      expect(find.text('Rock'), findsOneWidget);
    },
  );
}
