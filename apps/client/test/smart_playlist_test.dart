import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyperstream_client/models/library.dart';
import 'package:hyperstream_client/models/smart_playlist.dart';

final now = DateTime.utc(2026, 11, 11, 18);
Track song(
  String id, {
  int? added,
  int? played,
  int count = 0,
  bool favorite = false,
  String artist = 'Artist',
  String album = 'Album',
}) => Track(
  id: id,
  title: id,
  artist: artist,
  album: album,
  duration: const Duration(seconds: 180),
  addedAt: added == null ? null : now.subtract(Duration(days: added)),
  lastPlayedAt: played == null ? null : now.subtract(Duration(days: played)),
  playCount: count,
  starred: favorite,
);
SmartPlaylistDefinition definition({
  SmartGroup? include,
  SmartGroup? exclude,
  List<SmartPool>? pools,
  int? limit,
  bool fill = true,
  SmartOrder order = SmartOrder.activity,
}) => SmartPlaylistDefinition(
  id: 'example',
  name: 'Example',
  type: pools == null ? SmartPlaylistType.rules : SmartPlaylistType.mix,
  include: include ?? SmartPlaylistDefinition.initial('example').include,
  exclude: exclude ?? SmartGroup(all: false),
  pools: pools ?? SmartPlaylistDefinition.initial('example').pools,
  limit: limit,
  fillWhenEmpty: fill,
  order: order,
);
SmartPool pool(String artist, int share) => SmartPool(
  name: artist,
  share: share,
  order: SmartOrder.title,
  rules: SmartGroup(
    children: [SmartCondition(SmartField.artist, SmartOperator.equal, artist)],
  ),
);
List<String> ids(SmartPlaylistResult result) =>
    result.matches.map((m) => m.track.id).toList();

void main() {
  test('Recent Radio rules combine both dates, inclusive cutoff, stable ties and deduplication', () {
    final tracks = [
      song('old', added: 31, played: 31),
      song('played', added: 100, played: 1),
      song('added', added: 2),
      song('edge', added: 30),
      song('future', added: -1),
      song('missing'),
      song('tie', played: 2),
      song('added', added: 2),
    ];
    final result = SmartPlaylistResult.evaluate(tracks, definition(), now);
    expect(ids(result), ['played', 'added', 'tie', 'edge']);
    expect(
      ids(SmartPlaylistResult.evaluate(tracks.reversed, definition(), now)),
      ids(result),
    );
    expect(result.matchedCount, 4);
  });
  test(
    'nested any/all groups and global exclusions apply before the limit',
    () {
      final rules = SmartGroup(
        children: [
          const SmartCondition(SmartField.favorite, SmartOperator.isTrue),
          SmartGroup(
            all: false,
            children: const [
              SmartCondition(SmartField.playCount, SmartOperator.less, '2'),
              SmartCondition(SmartField.played, SmartOperator.older, '90'),
            ],
          ),
        ],
      );
      final result = SmartPlaylistResult.evaluate(
        [
          song(
            'a',
            favorite: true,
            count: 10,
            played: 100,
            album: 'Live recording',
          ),
          song('b', favorite: true, count: 1),
          song('c', favorite: true, count: 10, played: 100),
          song('d', favorite: true, count: 10, played: 1),
          song('e', count: 0),
        ],
        definition(
          include: rules,
          exclude: SmartGroup(
            all: false,
            children: const [
              SmartCondition(SmartField.album, SmartOperator.contains, 'LIVE'),
            ],
          ),
          limit: 1,
          order: SmartOrder.title,
        ),
        now,
      );
      expect(ids(result), ['b']);
      expect(result.matchedCount, 2);
      expect(result.matches.single.reason, contains('Favorite'));
    },
  );
  test('never played distinguishes unknown or invalid history from known unplayed tracks', () {
    const never = SmartCondition(SmartField.played, SmartOperator.never);
    const older = SmartCondition(SmartField.played, SmartOperator.older, '90');
    expect(never.matches(song('unplayed'), now), isTrue);
    expect(older.matches(song('unplayed'), now), isTrue);
    expect(never.matches(song('unknown', count: 4), now), isFalse);
    expect(older.matches(song('unknown', count: 4), now), isFalse);
    expect(older.matches(song('future', played: -1), now), isFalse);
    final invalid = Track.fromJson({'id': 'bad', 'played': 'not-a-date'});
    expect(never.matches(invalid, now), isFalse);
    expect(older.matches(invalid, now), isFalse);
  });
  test(
    '60/40 mix interleaves distinct pools and preserves each pool order',
    () {
      final tracks = [
        for (var i = 0; i < 10; i++) ...[
          song('a$i', artist: 'A'),
          song('b$i', artist: 'B'),
        ],
      ];
      final result = SmartPlaylistResult.evaluate(
        tracks,
        definition(pools: [pool('A', 60), pool('B', 40)], limit: 10),
        now,
      );
      expect(result.contributions, [6, 4]);
      expect(ids(result), [
        'a0',
        'b0',
        'a1',
        'b1',
        'a2',
        'a3',
        'b2',
        'a4',
        'b3',
        'a5',
      ]);
      expect(result.matchedCount, 20);
      expect(result.scarce, isFalse);
    },
  );
  test('overlap emits each song once and charges only the emitting pool', () {
    final common = SmartGroup();
    final result = SmartPlaylistResult.evaluate(
      [song('a'), song('b'), song('c'), song('d')],
      definition(
        pools: [
          SmartPool(
            name: 'First',
            rules: common,
            share: 50,
            order: SmartOrder.title,
          ),
          SmartPool(
            name: 'Second',
            rules: common,
            share: 50,
            order: SmartOrder.title,
          ),
        ],
        limit: 4,
      ),
      now,
    );
    expect(ids(result), ['a', 'b', 'c', 'd']);
    expect(result.contributions, [2, 2]);
    expect(result.matches.map((m) => m.pool), [0, 1, 0, 1]);
  });
  test('shortages either fill from remaining pools or stop; zero share does not block', () {
    final tracks = [
      song('a0', artist: 'A'),
      song('b0', artist: 'B'),
      song('b1', artist: 'B'),
      song('c', artist: 'Disabled'),
    ];
    final pools = [pool('A', 50), pool('B', 50), pool('Disabled', 0)];
    final fill = SmartPlaylistResult.evaluate(
      tracks,
      definition(pools: pools),
      now,
    );
    expect(ids(fill), ['a0', 'b0', 'b1']);
    expect(fill.contributions, [1, 2, 0]);
    expect(fill.scarce, isTrue);
    final stop = SmartPlaylistResult.evaluate(
      tracks,
      definition(pools: pools, fill: false),
      now,
    );
    expect(ids(stop), ['a0']);
    expect(stop.scarce, isTrue);
    expect(
      ids(
        SmartPlaylistResult.evaluate(
          tracks,
          definition(pools: [pool('A', 100), pool('Absent', 0)], fill: false),
          now,
        ),
      ),
      ['a0'],
    );
  });
  test(
    'serialization retains both types, nested rules, limits and mixing policy',
    () {
      final original = definition(
        pools: [pool('A', 25), pool('B', 75)],
        include: SmartGroup(
          children: [
            SmartGroup(
              all: false,
              children: const [
                SmartCondition(SmartField.favorite, SmartOperator.isTrue),
              ],
            ),
          ],
        ),
        limit: 17,
        fill: false,
        order: SmartOrder.leastPlayed,
      );
      final restored = SmartPlaylistDefinition.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
      );
      expect(restored.toJson(), original.toJson());
      expect(
        () => SmartPlaylistDefinition.fromJson({
          ...original.toJson(),
          'schemaVersion': 4,
        }),
        throwsFormatException,
      );
      expect(
        () => SmartPlaylistDefinition.fromJson({
          ...original.toJson(),
          'type': 'score',
        }),
        throwsFormatException,
      );
      expect(
        () => definition(pools: [pool('A', 10)]).validate(),
        throwsFormatException,
      );
      expect(() => definition(limit: 0).validate(), throwsFormatException);
      expect(
        () => const SmartCondition(
          SmartField.added,
          SmartOperator.within,
          '0',
        ).validate(),
        throwsFormatException,
      );
    },
  );
}
