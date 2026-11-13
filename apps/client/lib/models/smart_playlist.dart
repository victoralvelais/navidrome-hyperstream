import 'dart:collection';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'library.dart';
import 'smart_ranking.dart';
export 'smart_ranking.dart';

enum SmartPlaylistType { rules, mix }

enum SmartField {
  added('Date added'),
  played('Last played'),
  favorite('Favorite'),
  playCount('Play count'),
  duration('Duration in seconds'),
  title('Title'),
  artist('Artist'),
  album('Album'),
  genre('Genre'),
  year('Release year'),
  rating('My rating');

  const SmartField(this.label);
  final String label;
  List<SmartOperator> get operators => switch (this) {
    added => [SmartOperator.within, SmartOperator.older],
    played => [SmartOperator.within, SmartOperator.older, SmartOperator.never],
    favorite => [SmartOperator.isTrue, SmartOperator.isFalse],
    year => [
      SmartOperator.less,
      SmartOperator.greater,
      SmartOperator.equal,
      SmartOperator.isMissing,
      SmartOperator.isPresent,
    ],
    genre => [
      SmartOperator.contains,
      SmartOperator.notContains,
      SmartOperator.equal,
      SmartOperator.isMissing,
      SmartOperator.isPresent,
    ],
    playCount ||
    duration ||
    rating => [SmartOperator.less, SmartOperator.greater, SmartOperator.equal],
    _ => [
      SmartOperator.contains,
      SmartOperator.notContains,
      SmartOperator.equal,
    ],
  };
  bool get isDate => this == added || this == played;
  bool get isNumber =>
      isDate ||
      this == playCount ||
      this == duration ||
      this == year ||
      this == rating;
}

enum SmartOperator {
  within('Within the last'),
  older('Not within the last'),
  never('Never played'),
  isTrue('Yes'),
  isFalse('No'),
  less('Less than'),
  greater('More than'),
  equal('Equals'),
  contains('Contains'),
  notContains('Does not contain'),
  isMissing('Is missing'),
  isPresent('Is present');

  const SmartOperator(this.label);
  final String label;
  bool get needsValue =>
      ![never, isTrue, isFalse, isMissing, isPresent].contains(this);
}

enum SmartOrder {
  activity('Latest activity'),
  added('Newest added'),
  played('Most recently played'),
  title('Title A–Z'),
  artist('Artist A–Z'),
  leastPlayed('Least played'),
  stableShuffle('Stable shuffle'),
  customRanking('Custom ranking');

  const SmartOrder(this.label);
  final String label;
}

T _enum<T extends Enum>(List<T> values, Object? name) => values.firstWhere(
  (value) => value.name == name,
  orElse: () =>
      throw const FormatException('Unsupported smart playlist option.'),
);

DateTime? validSmartDate(DateTime? value, DateTime now) =>
    value == null || value.isAfter(now) ? null : value.toUtc();

sealed class SmartRule {
  const SmartRule();
  bool matches(Track track, DateTime now);
  String get summary;
  Map<String, dynamic> toJson();

  static SmartRule fromJson(Map<String, dynamic> json, [int depth = 0]) {
    if (depth > 4) {
      throw const FormatException('Use at most four nested groups.');
    }
    if (json['kind'] == 'group') {
      final children = json['children'];
      if (json['all'] is! bool || children is! List || children.length > 50) {
        throw const FormatException('Invalid rule group.');
      }
      return SmartGroup(
        all: json['all'] as bool,
        children: children
            .map((value) => fromJson(value as Map<String, dynamic>, depth + 1))
            .toList(),
      );
    }
    if (json['kind'] != 'condition') {
      throw const FormatException('Unsupported rule.');
    }
    final condition = SmartCondition(
      _enum(SmartField.values, json['field']),
      _enum(SmartOperator.values, json['operator']),
      json['value'] as String? ?? '',
    );
    condition.validate();
    return condition;
  }
}

class SmartCondition extends SmartRule {
  const SmartCondition(this.field, this.operator, [this.value = '']);
  final SmartField field;
  final SmartOperator operator;
  final String value;

  void validate() {
    if (!field.operators.contains(operator)) {
      throw const FormatException('Choose a valid condition.');
    }
    if (!operator.needsValue) return;
    if (value.trim().isEmpty || value.length > 200) {
      throw const FormatException('Enter a value of up to 200 characters.');
    }
    if (field.isNumber) {
      final number = int.tryParse(value);
      if (field == SmartField.rating &&
          (number == null || number < 0 || number > 5)) {
        throw const FormatException('Choose a rating from 0 (unrated) to 5.');
      }
      if (field == SmartField.year &&
          (number == null || number < 1 || number > 9999)) {
        throw const FormatException('Choose a release year from 1 to 9999.');
      }
      if (number == null ||
          number < (field.isDate ? 1 : 0) ||
          number > (field.isDate ? 3650 : 1000000)) {
        throw FormatException(
          field.isDate
              ? 'Choose 1 to 3650 days.'
              : 'Enter a whole number from 0 to 1000000.',
        );
      }
    }
  }

  @override
  bool matches(Track track, DateTime now) {
    if (operator == SmartOperator.isMissing ||
        operator == SmartOperator.isPresent) {
      final missing = field == SmartField.year
          ? track.year == null
          : track.genres.isEmpty;
      return operator == SmartOperator.isMissing ? missing : !missing;
    }
    if (field == SmartField.genre) {
      if (track.genres.isEmpty) return false;
      final target = value.trim().toLowerCase();
      bool match(String genre) => operator == SmartOperator.equal
          ? genre.toLowerCase() == target
          : genre.toLowerCase().contains(target);
      return operator == SmartOperator.notContains
          ? !track.genres.any(match)
          : track.genres.any(match);
    }
    if (field.isDate) {
      final date = validSmartDate(
        field == SmartField.added ? track.addedAt : track.lastPlayedAt,
        now,
      );
      final neverPlayed =
          field == SmartField.played &&
          track.lastPlayedAt == null &&
          track.playCount == 0 &&
          !track.invalidActivityDates;
      if (operator == SmartOperator.never) return neverPlayed;
      if (date == null) return operator == SmartOperator.older && neverPlayed;
      final cutoff = now.subtract(Duration(days: int.parse(value)));
      return operator == SmartOperator.within
          ? !date.isBefore(cutoff)
          : date.isBefore(cutoff);
    }
    if (field == SmartField.favorite) {
      return operator == SmartOperator.isTrue ? track.starred : !track.starred;
    }
    if (field.isNumber) {
      final actual = switch (field) {
        SmartField.playCount => track.playCount,
        SmartField.year => track.year,
        SmartField.rating => track.userRating,
        _ => track.duration.inSeconds,
      };
      if (actual == null) return false;
      final target = int.parse(value);
      return switch (operator) {
        SmartOperator.less => actual < target,
        SmartOperator.greater => actual > target,
        _ => actual == target,
      };
    }
    final actual = switch (field) {
      SmartField.title => track.title,
      SmartField.artist => track.artist,
      _ => track.album,
    }.toLowerCase();
    final target = value.trim().toLowerCase();
    return switch (operator) {
      SmartOperator.contains => actual.contains(target),
      SmartOperator.notContains => !actual.contains(target),
      _ => actual == target,
    };
  }

  @override
  String get summary =>
      '${field.label}: ${operator.label.toLowerCase()}${operator.needsValue ? ' $value${field.isDate ? ' days' : ''}' : ''}${field == SmartField.played && operator == SmartOperator.older ? ' (or never played)' : ''}';
  @override
  Map<String, dynamic> toJson() => {
    'kind': 'condition',
    'field': field.name,
    'operator': operator.name,
    'value': value,
  };
}

class SmartGroup extends SmartRule {
  SmartGroup({this.all = true, List<SmartRule> children = const []})
    : children = List.unmodifiable(children);
  final bool all;
  final List<SmartRule> children;
  @override
  bool matches(Track track, DateTime now) => all
      ? children.every((rule) => rule.matches(track, now))
      : children.any((rule) => rule.matches(track, now));
  @override
  String get summary => children.isEmpty
      ? (all ? 'All songs' : 'No conditions')
      : '${all ? 'All' : 'Any'} of ${children.length} conditions';
  @override
  Map<String, dynamic> toJson() => {
    'kind': 'group',
    'all': all,
    'children': children.map((rule) => rule.toJson()).toList(),
  };
}

class SmartPool {
  const SmartPool({
    required this.name,
    required this.rules,
    required this.share,
    this.order = SmartOrder.activity,
    this.ranking = const SmartRanking(),
  });
  final String name;
  final SmartGroup rules;
  final int share;
  final SmartOrder order;
  final SmartRanking ranking;
  Map<String, dynamic> toJson() => {
    'name': name,
    'rules': rules.toJson(),
    'share': share,
    'order': order.name,
    'ranking': ranking.toJson(),
  };
  factory SmartPool.fromJson(
    Map<String, dynamic> json, {
    bool rankingRequired = false,
  }) => SmartPool(
    name: json['name'] as String,
    rules:
        SmartRule.fromJson(json['rules'] as Map<String, dynamic>) as SmartGroup,
    share: json['share'] as int,
    order: _enum(SmartOrder.values, json['order']),
    ranking: !rankingRequired && json['ranking'] == null
        ? const SmartRanking()
        : SmartRanking.fromJson(json['ranking'] as Map<String, dynamic>),
  );
}

class SmartPlaylistDefinition {
  SmartPlaylistDefinition({
    required this.id,
    required this.name,
    required this.type,
    required this.include,
    required this.exclude,
    required List<SmartPool> pools,
    this.order = SmartOrder.activity,
    this.limit,
    this.fillWhenEmpty = true,
    this.artistGap = 0,
    this.relaxArtistGap = true,
    this.shuffleSeed = 0,
    this.ranking = const SmartRanking(),
  }) : pools = List.unmodifiable(pools);
  final String id;
  final String name;
  final SmartPlaylistType type;
  final SmartGroup include;
  final SmartGroup exclude;
  final List<SmartPool> pools;
  final SmartOrder order;
  final int? limit;
  final bool fillWhenEmpty;
  final int artistGap;
  final bool relaxArtistGap;
  final int shuffleSeed;
  final SmartRanking ranking;

  bool get usesStableShuffle => type == SmartPlaylistType.rules
      ? order == SmartOrder.stableShuffle
      : pools.any(
          (pool) => pool.share > 0 && pool.order == SmartOrder.stableShuffle,
        );

  SmartPlaylistDefinition reshuffled() => SmartPlaylistDefinition(
    id: id,
    name: name,
    type: type,
    include: include,
    exclude: exclude,
    pools: pools,
    order: order,
    limit: limit,
    fillWhenEmpty: fillWhenEmpty,
    artistGap: artistGap,
    relaxArtistGap: relaxArtistGap,
    shuffleSeed: (shuffleSeed + 1) & 0x7fffffff,
    ranking: ranking,
  );

  factory SmartPlaylistDefinition.initial(String id) => SmartPlaylistDefinition(
    id: id,
    name: 'My smart playlist',
    type: SmartPlaylistType.rules,
    shuffleSeed: Random().nextInt(0x7fffffff),
    include: SmartGroup(
      all: false,
      children: const [
        SmartCondition(SmartField.added, SmartOperator.within, '30'),
        SmartCondition(SmartField.played, SmartOperator.within, '30'),
      ],
    ),
    exclude: SmartGroup(all: false),
    pools: [
      SmartPool(
        name: 'Recently added',
        share: 60,
        order: SmartOrder.added,
        rules: SmartGroup(
          children: const [
            SmartCondition(SmartField.added, SmartOperator.within, '30'),
          ],
        ),
      ),
      SmartPool(
        name: 'Recently played',
        share: 40,
        order: SmartOrder.played,
        rules: SmartGroup(
          children: const [
            SmartCondition(SmartField.played, SmartOperator.within, '30'),
          ],
        ),
      ),
    ],
  );

  void validate() {
    ranking.validate();
    if (artistGap < 0 ||
        artistGap > 10 ||
        shuffleSeed < 0 ||
        shuffleSeed > 0x7fffffff) {
      throw const FormatException(
        'Choose artist spacing from 0 to 10 and a valid shuffle.',
      );
    }
    if (id.isEmpty ||
        id.length > 100 ||
        name.trim().isEmpty ||
        name.length > 120) {
      throw const FormatException(
        'Enter a playlist name of up to 120 characters.',
      );
    }
    if (limit != null && (limit! < 1 || limit! > 10000)) {
      throw const FormatException(
        'Choose 1 to 10000 tracks, or leave the limit empty.',
      );
    }
    var nodes = 0;
    void check(SmartRule rule, int depth) {
      if (++nodes > 200 || depth > 4) {
        throw const FormatException(
          'Use at most 200 rules and four nested groups.',
        );
      }
      if (rule is SmartCondition) rule.validate();
      if (rule is SmartGroup) {
        if (rule.children.length > 50) {
          throw const FormatException('Use at most 50 conditions per group.');
        }
        for (final child in rule.children) {
          check(child, depth + 1);
        }
      }
    }

    check(include, 0);
    check(exclude, 0);
    if (pools.isEmpty || pools.length > 8) {
      throw const FormatException('Use 1 to 8 mix pools.');
    }
    for (final pool in pools) {
      pool.ranking.validate();
      if (pool.name.trim().isEmpty ||
          pool.name.length > 80 ||
          pool.share < 0 ||
          pool.share > 100) {
        throw const FormatException(
          'Name each pool and give it a share from 0 to 100.',
        );
      }
      check(pool.rules, 0);
    }
    if (type == SmartPlaylistType.mix &&
        pools.fold(0, (sum, pool) => sum + pool.share) != 100) {
      throw const FormatException('Mix shares must add up to 100%.');
    }
  }

  Map<String, dynamic> toJson() => {
    'schemaVersion': 4,
    'id': id,
    'name': name,
    'type': type.name,
    'include': include.toJson(),
    'exclude': exclude.toJson(),
    'pools': pools.map((pool) => pool.toJson()).toList(),
    'order': order.name,
    'limit': limit,
    'fillWhenEmpty': fillWhenEmpty,
    'artistGap': artistGap,
    'relaxArtistGap': relaxArtistGap,
    'shuffleSeed': shuffleSeed,
    'ranking': ranking.toJson(),
  };
  factory SmartPlaylistDefinition.fromJson(Map<String, dynamic> json) {
    final version = json['schemaVersion'];
    if (version != 1 && version != 2 && version != 3 && version != 4) {
      throw const FormatException('Unsupported smart playlist version.');
    }
    final value = SmartPlaylistDefinition(
      id: json['id'] as String,
      name: json['name'] as String,
      type: _enum(SmartPlaylistType.values, json['type']),
      include: SmartRule.fromJson(
        json['include'] as Map<String, dynamic>,
      ) as SmartGroup,
      exclude: SmartRule.fromJson(
        json['exclude'] as Map<String, dynamic>,
      ) as SmartGroup,
      pools: (json['pools'] as List)
          .map(
            (pool) => SmartPool.fromJson(
              pool as Map<String, dynamic>,
              rankingRequired: version == 3 || version == 4,
            ),
          )
          .toList(),
      order: _enum(SmartOrder.values, json['order']),
      limit: json['limit'] as int?,
      fillWhenEmpty: json['fillWhenEmpty'] as bool,
      artistGap: version == 1 ? 0 : json['artistGap'] as int,
      relaxArtistGap: version == 1 ? true : json['relaxArtistGap'] as bool,
      shuffleSeed: version == 1 ? 0 : json['shuffleSeed'] as int,
      ranking: version == 3 || version == 4
          ? SmartRanking.fromJson(json['ranking'] as Map<String, dynamic>)
          : const SmartRanking(),
    );
    value.validate();
    return value;
  }
}

class SmartMatch {
  const SmartMatch(this.track, this.reason, {this.pool, this.score});
  final Track track;
  final String reason;
  final int? pool;
  final SmartScore? score;
}

class SmartPlaylistResult {
  SmartPlaylistResult({
    required List<SmartMatch> matches,
    required this.matchedCount,
    required List<int> contributions,
    required this.scarce,
    required this.evaluatedAt,
    this.spacingRelaxations = 0,
    this.spacingLimited = false,
  }) : matches = List.unmodifiable(matches),
       contributions = List.unmodifiable(contributions);
  final List<SmartMatch> matches;
  final int matchedCount;
  final List<int> contributions;
  final bool scarce;
  final DateTime evaluatedAt;
  final int spacingRelaxations;
  final bool spacingLimited;

  static SmartPlaylistResult evaluate(
    Iterable<Track> tracks,
    SmartPlaylistDefinition definition,
    DateTime now,
  ) {
    definition.validate();
    final time = now.toUtc();
    final unique = <String, Track>{for (final track in tracks) track.id: track};
    final eligible = unique.values
        .where(
          (track) =>
              definition.exclude.children.isEmpty ||
              !definition.exclude.matches(track, time),
        )
        .toList();
    final output = <SmartMatch>[];
    final contributions = List.filled(definition.pools.length, 0);
    final limit = definition.limit ?? unique.length;
    final shuffleRanks = <String, String>{};
    String shuffleRank(Track track) => shuffleRanks.putIfAbsent(
      track.id,
      () => sha256
          .convert(
            utf8.encode(
              jsonEncode([definition.id, definition.shuffleSeed, track.id]),
            ),
          )
          .toString(),
    );

    DateTime? dateFor(Track track, SmartOrder order) {
      final added = validSmartDate(track.addedAt, time);
      final played = validSmartDate(track.lastPlayedAt, time);
      if (order == SmartOrder.added) return added;
      if (order == SmartOrder.played) return played;
      if (added == null) return played;
      return played == null || added.isAfter(played) ? added : played;
    }

    final rankScores = <SmartRanking, Map<String, SmartScore>>{};
    SmartScore score(Track track, SmartRanking ranking) => rankScores
        .putIfAbsent(ranking, () => {})
        .putIfAbsent(track.id, () => ranking.score(track, time));

    List<Track> sorted(
      Iterable<Track> items,
      SmartOrder order,
      SmartRanking ranking,
    ) {
      final sorted = items.toList();
      sorted.sort((a, b) {
        final int comparison;
        if (order == SmartOrder.customRanking) {
          comparison = score(
            b,
            ranking,
          ).total.compareTo(score(a, ranking).total);
        } else if (order == SmartOrder.stableShuffle) {
          comparison = shuffleRank(a).compareTo(shuffleRank(b));
        } else if (order == SmartOrder.title || order == SmartOrder.artist) {
          comparison = (order == SmartOrder.title ? a.title : a.artist)
              .toLowerCase()
              .compareTo(
                (order == SmartOrder.title ? b.title : b.artist).toLowerCase(),
              );
        } else if (order == SmartOrder.leastPlayed) {
          comparison = a.playCount.compareTo(b.playCount);
        } else {
          final ad = dateFor(a, order), bd = dateFor(b, order);
          comparison = ad == null
              ? (bd == null ? 0 : 1)
              : bd == null
              ? -1
              : bd.compareTo(ad);
        }
        return comparison == 0 ? a.id.compareTo(b.id) : comparison;
      });
      return sorted;
    }

    String reason(SmartRule rule, Track track) {
      if (rule is SmartCondition) return rule.summary;
      final group = rule as SmartGroup;
      if (group.children.isEmpty) return 'All songs';
      return group.children
          .where((child) => child.matches(track, time))
          .map((child) => reason(child, track))
          .join(' · ');
    }

    final isMix = definition.type == SmartPlaylistType.mix;
    final poolDefinitions = isMix
        ? definition.pools
        : [
            SmartPool(
              name: 'Rules',
              rules: definition.include,
              share: 100,
              order: definition.order,
              ranking: definition.ranking,
            ),
          ];
    final pools = poolDefinitions
        .map(
          (pool) => pool.share == 0
              ? <Track>[]
              : sorted(
                  eligible.where((track) => pool.rules.matches(track, time)),
                  pool.order,
                  pool.ranking,
                ),
        )
        .toList();
    final matched = pools
        .expand((pool) => pool)
        .map((track) => track.id)
        .toSet()
        .length;
    final artists = <String, String>{};
    String artistFor(Track track) => artists.putIfAbsent(track.id, () {
      final id = track.artistId?.trim();
      if (id != null && id.isNotEmpty) return 'id:$id';
      final name = track.artist.trim().toLowerCase().replaceAll(
        RegExp(r'\s+'),
        ' ',
      );
      // Unknown artists must not all become one artificial artist.
      return name.isEmpty || name == 'unknown artist'
          ? 'track:${track.id}'
          : 'name:$name';
    });
    final candidates = pools
        .map((tracks) => _ArtistCandidates(tracks, artistFor))
        .toList();
    final used = <String>{};
    final recentArtists = ListQueue<String>();
    final scores = List.filled(pools.length, 0);
    var scarce = false;
    var spacingLimited = false;
    var spacingRelaxations = 0;
    while (output.length < limit) {
      final active = <int>[];
      var exhausted = false;
      for (var i = 0; i < pools.length; i++) {
        if (poolDefinitions[i].share == 0) continue;
        if (candidates[i].first(used, const {}) != null) {
          active.add(i);
        } else {
          exhausted = true;
        }
      }
      if (active.isEmpty) break;
      if (exhausted) {
        scarce = true;
        if (!definition.fillWhenEmpty) break;
      }
      // Blocked songs remain candidates for later. Relax only if no pool can
      // contribute, and only as far as needed to continue.
      final feasible = <int, Track>{};
      var gap = definition.artistGap;
      while (true) {
        final blocked = recentArtists
            .skip(max(0, recentArtists.length - gap))
            .toSet();
        for (final i in active) {
          final track = candidates[i].first(used, blocked);
          if (track != null) feasible[i] = track;
        }
        if (feasible.isNotEmpty || !definition.relaxArtistGap || gap == 0) {
          break;
        }
        gap--;
      }
      if (feasible.isEmpty) {
        spacingLimited = true;
        break;
      }
      final relaxed = gap < definition.artistGap;
      if (relaxed) spacingRelaxations++;
      var chosen = feasible.keys.first;
      var total = 0;
      for (final i in active) {
        final share = poolDefinitions[i].share;
        scores[i] += share;
        total += share;
        if (feasible.containsKey(i) && scores[i] > scores[chosen]) chosen = i;
      }
      scores[chosen] -= total;
      final track = feasible[chosen]!;
      used.add(track.id);
      if (isMix) contributions[chosen]++;
      if (definition.artistGap > 0) {
        recentArtists.addLast(artistFor(track));
        if (recentArtists.length > definition.artistGap) {
          recentArtists.removeFirst();
        }
      }
      output.add(
        SmartMatch(
          track,
          '${isMix ? '${poolDefinitions[chosen].name} · ' : ''}${reason(poolDefinitions[chosen].rules, track)}${relaxed ? ' · Artist spacing relaxed' : ''}',
          pool: isMix ? chosen : null,
          score: poolDefinitions[chosen].order == SmartOrder.customRanking
              ? score(track, poolDefinitions[chosen].ranking)
              : null,
        ),
      );
    }
    return SmartPlaylistResult(
      matches: output,
      matchedCount: matched,
      contributions: contributions,
      scarce: scarce,
      evaluatedAt: time,
      spacingRelaxations: spacingRelaxations,
      spacingLimited: spacingLimited,
    );
  }
}

/// A sorted head per artist skips entire blocked runs, without scanning the
/// remaining library for each selection. Used IDs are removed lazily across
/// overlapping pools. At most the blocked artists plus one head are examined.
class _ArtistCandidates {
  _ArtistCandidates(List<Track> tracks, String Function(Track) artistFor) {
    final groups = <String, _ArtistRun>{};
    for (final (rank, track) in tracks.indexed) {
      final artist = artistFor(track);
      (groups[artist] ??= _ArtistRun(artist)).tracks.addLast((rank, track));
    }
    for (final group in groups.values) {
      _heads[group.tracks.first.$1] = group;
    }
  }
  final _heads = SplayTreeMap<int, _ArtistRun>();

  Track? first(Set<String> used, Set<String> blocked) {
    final held = <int, _ArtistRun>{};
    try {
      while (_heads.isNotEmpty) {
        final rank = _heads.firstKey()!;
        final group = _heads.remove(rank)!;
        while (group.tracks.isNotEmpty &&
            used.contains(group.tracks.first.$2.id)) {
          group.tracks.removeFirst();
        }
        if (group.tracks.isEmpty) continue;
        final next = group.tracks.first;
        if (next.$1 != rank) {
          _heads[next.$1] = group;
          continue;
        }
        if (blocked.contains(group.artist)) {
          held[rank] = group;
          continue;
        }
        _heads[rank] = group;
        return next.$2;
      }
      return null;
    } finally {
      _heads.addAll(held);
    }
  }
}

class _ArtistRun {
  _ArtistRun(this.artist);
  final String artist;
  final tracks = ListQueue<(int, Track)>();
}
