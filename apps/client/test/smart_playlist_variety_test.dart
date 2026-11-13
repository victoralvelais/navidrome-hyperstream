import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperstream_client/models/library.dart';
import 'package:hyperstream_client/models/smart_playlist.dart';

final _now = DateTime.utc(2026, 11, 13);
Track _track(String id, String artist, {String? artistId, int plays = 0}) =>
    Track(
      id: id,
      title: id,
      artist: artist,
      artistId: artistId,
      album: 'Album',
      duration: const Duration(minutes: 3),
      playCount: plays,
      lastPlayedAt: plays > 0 ? _now : null,
    );
SmartPlaylistDefinition _definition({
  int gap = 0,
  bool relax = true,
  int seed = 42,
  SmartOrder order = SmartOrder.title,
  int? limit,
  List<SmartPool>? pools,
}) => SmartPlaylistDefinition(
  id: 'variety',
  name: 'Variety',
  type: pools == null ? SmartPlaylistType.rules : SmartPlaylistType.mix,
  include: SmartGroup(),
  exclude: SmartGroup(all: false),
  pools: pools ?? [SmartPool(name: 'All', rules: SmartGroup(), share: 100)],
  order: order,
  artistGap: gap,
  relaxArtistGap: relax,
  shuffleSeed: seed,
  limit: limit,
);
SmartPlaylistResult _run(
  List<Track> tracks,
  SmartPlaylistDefinition definition,
) => SmartPlaylistResult.evaluate(tracks, definition, _now);
List<String> _ids(SmartPlaylistResult result) =>
    result.matches.map((m) => m.track.id).toList();

void main() {
  test('spacing never pulls excluded tracks back into the selection', () {
    final definition = SmartPlaylistDefinition.fromJson({
      ..._definition(gap: 1, relax: false).toJson(),
      'exclude': SmartGroup(
        all: false,
        children: [
          const SmartCondition(
            SmartField.artist,
            SmartOperator.equal,
            'Excluded',
          ),
        ],
      ).toJson(),
    });
    final result = _run([
      _track('1', 'A'),
      _track('2', 'A'),
      _track('3', 'Excluded'),
    ], definition);
    expect(_ids(result), ['1']);
    expect(result.matchedCount, 2);
    expect(result.spacingLimited, isTrue);
  });

  test('saved shuffle survives roundtrip, input order, time and local activity updates', () {
    final tracks = List.generate(30, (i) => _track('song-$i', 'Artist $i'));
    final definition = _definition(order: SmartOrder.stableShuffle);
    final initial = _ids(_run(tracks, definition));
    final reopened = SmartPlaylistDefinition.fromJson(
      jsonDecode(jsonEncode(definition.toJson())) as Map<String, dynamic>,
    );
    expect(_ids(_run(tracks.reversed.toList(), reopened)), initial);
    expect(
      _ids(
        SmartPlaylistResult.evaluate(
          tracks,
          reopened,
          _now.add(const Duration(days: 3)),
        ),
      ),
      initial,
    );
    expect(
      _ids(
        _run(
          tracks.map((t) => _track(t.id, t.artist, plays: 12)).toList(),
          reopened,
        ),
      ),
      initial,
    );
    final withNew = _ids(
      _run([...tracks, _track('new-song', 'New artist')], reopened),
    );
    expect(withNew.where((id) => id != 'new-song'), initial);
    expect(_ids(_run(tracks, reopened.reshuffled())), isNot(initial));
    expect(
      _ids(
        _run(tracks, _definition(order: SmartOrder.stableShuffle, limit: 8)),
      ),
      initial.take(8),
    );
  });

  test('spacing skips blocked songs and returns to them in ranking order', () {
    final tracks = [
      for (final artist in ['A', 'B', 'C', 'D'])
        for (var i = 0; i < 2; i++) _track('$artist$i', artist),
    ];
    final result = _run(tracks, _definition(gap: 3, relax: false));
    expect(_ids(result), ['A0', 'B0', 'C0', 'D0', 'A1', 'B1', 'C1', 'D1']);
    expect(result.spacingLimited, isFalse);
    expect(result.spacingRelaxations, 0);
  });

  test(
    'strict shortage stops; relaxed shortage uses the largest possible gap',
    () {
      final tracks = [
        for (final artist in ['A', 'B'])
          for (var i = 0; i < 3; i++) _track('$artist$i', artist),
      ];
      final strict = _run(tracks, _definition(gap: 3, relax: false));
      expect(_ids(strict), ['A0', 'B0']);
      expect(strict.matchedCount, 6);
      expect(strict.spacingLimited, isTrue);
      expect(
        _run(
          tracks,
          _definition(gap: 3, relax: false, limit: 2),
        ).spacingLimited,
        isFalse,
      );
      final relaxed = _run(tracks, _definition(gap: 3));
      expect(_ids(relaxed), ['A0', 'B0', 'A1', 'B1', 'A2', 'B2']);
      expect(relaxed.spacingRelaxations, 4);
      expect(relaxed.spacingLimited, isFalse);
      expect(
        relaxed.matches.where((m) => m.reason.contains('spacing relaxed')),
        hasLength(4),
      );
    },
  );

  test('primary artist IDs, normalized fallback names and unknown artists are handled explicitly', () {
    expect(
      _ids(
        _run([
          _track('1', 'Old name', artistId: 'same'),
          _track('2', 'New name', artistId: 'same'),
          _track('3', 'Other', artistId: 'other'),
        ], _definition(gap: 1, relax: false)),
      ),
      ['1', '3', '2'],
    );
    expect(
      _ids(
        _run([
          _track('1', ' DJ  Name '),
          _track('2', 'dj name'),
          _track('3', 'Other'),
        ], _definition(gap: 1, relax: false)),
      ),
      ['1', '3', '2'],
    );
    expect(
      _run([
        _track('1', 'Same display', artistId: 'one'),
        _track('2', 'Same display', artistId: 'two'),
        _track('3', 'Unknown artist'),
        _track('4', 'Unknown artist'),
        _track('5', ''),
      ], _definition(gap: 10, relax: false)).matches,
      hasLength(5),
    );
  });

  test('mix spacing spans pool boundaries and reports actual rather than promised shares', () {
    SmartPool pool(String artist, int share) => SmartPool(
      name: artist,
      share: share,
      order: SmartOrder.title,
      rules: SmartGroup(
        children: [
          SmartCondition(SmartField.artist, SmartOperator.equal, artist),
        ],
      ),
    );
    final tracks = [
      for (final artist in ['A', 'B'])
        for (var i = 0; i < 10; i++) _track('$artist$i', artist),
    ];
    final result = _run(
      tracks,
      _definition(
        gap: 1,
        relax: false,
        limit: 10,
        pools: [pool('A', 60), pool('B', 40)],
      ),
    );
    expect(result.matches.map((m) => m.track.artist), [
      'A',
      'B',
      'A',
      'B',
      'A',
      'B',
      'A',
      'B',
      'A',
      'B',
    ]);
    expect(result.contributions, [5, 5]);
    expect(result.spacingRelaxations, 0);
    expect(result.scarce, isFalse);
  });

  test(
    'overlapping shuffled pools remain unique, deterministic and artist-spaced',
    () {
      final tracks = [
        for (var i = 0; i < 80; i++) _track('song-$i', 'Artist ${i % 8}'),
      ];
      final definition = _definition(
        gap: 3,
        relax: false,
        limit: 50,
        pools: [
          SmartPool(
            name: 'One',
            share: 60,
            rules: SmartGroup(),
            order: SmartOrder.stableShuffle,
          ),
          SmartPool(
            name: 'Two',
            share: 40,
            rules: SmartGroup(),
            order: SmartOrder.stableShuffle,
          ),
        ],
      );
      final result = _run(tracks, definition);
      expect(result.matches, hasLength(50));
      expect(_ids(result).toSet(), hasLength(50));
      expect(result.contributions, [30, 20]);
      for (var i = 0; i < result.matches.length; i++) {
        final previous = result.matches
            .take(i)
            .skip(i > 3 ? i - 3 : 0)
            .map((m) => m.track.artist);
        expect(previous, isNot(contains(result.matches[i].track.artist)));
      }
      expect(_ids(_run(tracks.reversed.toList(), definition)), _ids(result));
    },
  );

  test(
    'version 1 keeps its old behavior and version 2 validates new fields',
    () {
      final json = _definition().toJson()..['schemaVersion'] = 1;
      json.remove('artistGap');
      json.remove('relaxArtistGap');
      json.remove('shuffleSeed');
      final legacy = SmartPlaylistDefinition.fromJson(json);
      expect(legacy.artistGap, 0);
      expect(legacy.shuffleSeed, 0);
      expect(legacy.order, SmartOrder.title);
      expect(legacy.toJson()['schemaVersion'], 2);
      for (final bad in [
        {'artistGap': 11},
        {'artistGap': -1},
        {'shuffleSeed': -1},
        {'shuffleSeed': 0x80000000},
        {'schemaVersion': 3},
      ]) {
        expect(
          () => SmartPlaylistDefinition.fromJson({
            ..._definition().toJson(),
            ...bad,
          }),
          throwsFormatException,
        );
      }
    },
  );

  test('large same-artist libraries finish without repeated whole-list scans', () {
    final tracks = [
      for (var i = 0; i < 20000; i++) _track('song-$i', 'One artist'),
    ];
    final watch = Stopwatch()..start();
    final result = _run(
      tracks,
      _definition(gap: 10, order: SmartOrder.stableShuffle),
    );
    expect(result.matches, hasLength(tracks.length));
    expect(result.spacingRelaxations, tracks.length - 1);
    expect(_ids(result).toSet(), hasLength(tracks.length));
    // Diagnostic timing, not a brittle machine-dependent pass threshold.
    debugPrint(
      '20,000-track stable shuffle + spacing: ${watch.elapsedMilliseconds} ms',
    );
  }, timeout: const Timeout(Duration(seconds: 20)));
}
