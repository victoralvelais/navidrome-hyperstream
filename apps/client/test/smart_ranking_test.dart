import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyperstream_client/models/smart_playlist.dart';

import 'smart_playlist_test.dart' show song, now, ids;

SmartPlaylistDefinition ranked({
  SmartRanking ranking = const SmartRanking(),
  List<SmartPool>? pools,
  int gap = 0,
  int? limit,
}) => SmartPlaylistDefinition(
  id: 'rank',
  name: 'Recent Radio Plus',
  type: pools == null ? SmartPlaylistType.rules : SmartPlaylistType.mix,
  include: SmartGroup(),
  exclude: SmartGroup(
    all: false,
    children: const [
      SmartCondition(SmartField.title, SmartOperator.equal, 'excluded'),
    ],
  ),
  order: SmartOrder.customRanking,
  ranking: ranking,
  limit: limit,
  artistGap: gap,
  pools: pools ?? [SmartPool(name: 'All', rules: SmartGroup(), share: 100)],
);

void main() {
  test('recency fades linearly; favorite bonus and bounded count penalty explain the score', () {
    final score = const SmartRanking().score(
      song('a', added: 15, played: 6, favorite: true, count: 5),
      now,
    );
    expect(score.contributions, {
      'Added recency': 30.0,
      'Played recency': 20.0,
      'Favorite': 15.0,
      'Play-count penalty': -5.0,
    });
    expect(score.total, 60);
    expect(score.explanation, contains('Score 60.0'));
    expect(score.explanation, contains('Play-count penalty -5.0'));
    expect(
      const SmartRanking()
          .score(song('a', added: 30, played: 40, count: 100000), now)
          .total,
      -20,
    );
    expect(
      const SmartRanking()
          .score(song('a', added: -1, played: -2, count: -2), now)
          .total,
      0,
    );
    expect(const SmartRanking().score(song('a'), now).total, 0);
    final halfDay = const SmartRanking().score(
      song('a', added: 0),
      now.add(const Duration(hours: 12)),
    );
    expect(halfDay.total, 59);
  });

  test('ranking filters first, limits last and keeps deterministic ties and artist spacing', () {
    final tracks = [
      song('excluded', added: 0, favorite: true),
      song('a', added: 1, artist: 'A'),
      song('b', added: 2, artist: 'A'),
      song('c', added: 20, artist: 'B'),
      song('d', added: 20, artist: 'C'),
    ];
    final definition = ranked(gap: 1, limit: 3);
    final result = SmartPlaylistResult.evaluate(tracks, definition, now);
    expect(ids(result), ['a', 'c', 'b']);
    expect(result.matches.map((m) => m.score!.total), [
      closeTo(58, 1e-10),
      closeTo(20, 1e-10),
      closeTo(56, 1e-10),
    ]);
    expect(
      ids(SmartPlaylistResult.evaluate(tracks.reversed, definition, now)),
      ids(result),
    );
    expect(ids(SmartPlaylistResult.evaluate(tracks, ranked(), now)), [
      'a',
      'b',
      'c',
      'd',
    ]);
  });

  test(
    'each pool has independent ranking; pool shares remain selection shares',
    () {
      final tracks = [
        for (var i = 0; i < 10; i++) song('$i', added: i, favorite: i >= 5),
      ];
      final definition = ranked(
        pools: [
          SmartPool(
            name: 'Fresh',
            rules: SmartGroup(),
            share: 60,
            order: SmartOrder.customRanking,
            ranking: const SmartRanking(
              playedWeight: 0,
              favoriteWeight: 0,
              playCountWeight: 0,
            ),
          ),
          SmartPool(
            name: 'Favorites',
            rules: SmartGroup(),
            share: 40,
            order: SmartOrder.customRanking,
            ranking: const SmartRanking(
              addedWeight: 0,
              playedWeight: 0,
              favoriteWeight: 100,
              playCountWeight: 0,
            ),
          ),
        ],
        limit: 5,
      );
      final result = SmartPlaylistResult.evaluate(tracks, definition, now);
      expect(ids(result), ['0', '5', '1', '6', '2']);
      expect(result.contributions, [3, 2]);
      expect(result.matches[1].score!.total, 100);
    },
  );

  test(
    'version 1 and 2 definitions migrate without changing ordinary ordering',
    () {
      for (final version in [1, 2]) {
        final old = SmartPlaylistDefinition.initial('old').toJson()
          ..['schemaVersion'] = version;
        old.remove('ranking');
        for (final pool in old['pools'] as List) {
          (pool as Map).remove('ranking');
        }
        final loaded = SmartPlaylistDefinition.fromJson(old);
        expect(loaded.order, SmartOrder.activity);
        expect(loaded.ranking.toJson(), const SmartRanking().toJson());
      }
      final original = ranked(
        ranking: const SmartRanking(addedWeight: 87, addedDays: 14),
      );
      final loaded = SmartPlaylistDefinition.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
      );
      expect(loaded.toJson(), original.toJson());
      expect(loaded.reshuffled().ranking.toJson(), original.ranking.toJson());
      final missing = original.toJson()..remove('ranking');
      expect(
        () => SmartPlaylistDefinition.fromJson(missing),
        throwsA(isA<TypeError>()),
      );
    },
  );

  test('invalid weights, windows and penalty caps cannot evaluate or save', () {
    for (final ranking in [
      const SmartRanking(addedWeight: -1),
      const SmartRanking(favoriteWeight: 101),
      const SmartRanking(addedDays: 0),
      const SmartRanking(playedDays: 3651),
      const SmartRanking(playCountCap: 0),
    ]) {
      expect(() => ranked(ranking: ranking).validate(), throwsFormatException);
    }
    const off = SmartRanking(
      addedWeight: 0,
      playedWeight: 0,
      favoriteWeight: 0,
      playCountWeight: 0,
    );
    expect(
      ids(
        SmartPlaylistResult.evaluate(
          [song('b'), song('a')],
          ranked(ranking: off),
          now,
        ),
      ),
      ['a', 'b'],
    );
  });
}
