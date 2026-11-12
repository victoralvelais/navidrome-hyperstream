import 'library.dart';

enum SmartPlaylistType { rules, mix }

enum SmartField {
  added('Date added'),
  played('Last played'),
  favorite('Favorite'),
  playCount('Play count'),
  duration('Duration in seconds'),
  title('Title'),
  artist('Artist'),
  album('Album');

  const SmartField(this.label);
  final String label;
  List<SmartOperator> get operators => switch (this) {
    added => [SmartOperator.within, SmartOperator.older],
    played => [SmartOperator.within, SmartOperator.older, SmartOperator.never],
    favorite => [SmartOperator.isTrue, SmartOperator.isFalse],
    playCount || duration => [
      SmartOperator.less,
      SmartOperator.greater,
      SmartOperator.equal,
    ],
    _ => [
      SmartOperator.contains,
      SmartOperator.notContains,
      SmartOperator.equal,
    ],
  };
  bool get isDate => this == added || this == played;
  bool get isNumber => isDate || this == playCount || this == duration;
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
  notContains('Does not contain');

  const SmartOperator(this.label);
  final String label;
  bool get needsValue => ![never, isTrue, isFalse].contains(this);
}

enum SmartOrder {
  activity('Latest activity'),
  added('Newest added'),
  played('Most recently played'),
  title('Title A–Z'),
  artist('Artist A–Z'),
  leastPlayed('Least played');

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
      final actual = field == SmartField.playCount
          ? track.playCount
          : track.duration.inSeconds;
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
  });
  final String name;
  final SmartGroup rules;
  final int share;
  final SmartOrder order;
  Map<String, dynamic> toJson() => {
    'name': name,
    'rules': rules.toJson(),
    'share': share,
    'order': order.name,
  };
  factory SmartPool.fromJson(Map<String, dynamic> json) => SmartPool(
    name: json['name'] as String,
    rules:
        SmartRule.fromJson(json['rules'] as Map<String, dynamic>) as SmartGroup,
    share: json['share'] as int,
    order: _enum(SmartOrder.values, json['order']),
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

  factory SmartPlaylistDefinition.initial(String id) => SmartPlaylistDefinition(
    id: id,
    name: 'My smart playlist',
    type: SmartPlaylistType.rules,
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
    'schemaVersion': 1,
    'id': id,
    'name': name,
    'type': type.name,
    'include': include.toJson(),
    'exclude': exclude.toJson(),
    'pools': pools.map((pool) => pool.toJson()).toList(),
    'order': order.name,
    'limit': limit,
    'fillWhenEmpty': fillWhenEmpty,
  };
  factory SmartPlaylistDefinition.fromJson(Map<String, dynamic> json) {
    if (json['schemaVersion'] != 1) {
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
          .map((pool) => SmartPool.fromJson(pool as Map<String, dynamic>))
          .toList(),
      order: _enum(SmartOrder.values, json['order']),
      limit: json['limit'] as int?,
      fillWhenEmpty: json['fillWhenEmpty'] as bool,
    );
    value.validate();
    return value;
  }
}

class SmartMatch {
  const SmartMatch(this.track, this.reason, {this.pool});
  final Track track;
  final String reason;
  final int? pool;
}

class SmartPlaylistResult {
  SmartPlaylistResult({
    required List<SmartMatch> matches,
    required this.matchedCount,
    required List<int> contributions,
    required this.scarce,
    required this.evaluatedAt,
  }) : matches = List.unmodifiable(matches),
       contributions = List.unmodifiable(contributions);
  final List<SmartMatch> matches;
  final int matchedCount;
  final List<int> contributions;
  final bool scarce;
  final DateTime evaluatedAt;

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

    DateTime? dateFor(Track track, SmartOrder order) {
      final added = validSmartDate(track.addedAt, time);
      final played = validSmartDate(track.lastPlayedAt, time);
      if (order == SmartOrder.added) return added;
      if (order == SmartOrder.played) return played;
      if (added == null) return played;
      return played == null || added.isAfter(played) ? added : played;
    }

    List<Track> sorted(Iterable<Track> items, SmartOrder order) {
      final sorted = items.toList();
      sorted.sort((a, b) {
        final int comparison;
        if (order == SmartOrder.title || order == SmartOrder.artist) {
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

    if (definition.type == SmartPlaylistType.rules) {
      final matching = sorted(
        eligible.where((track) => definition.include.matches(track, time)),
        definition.order,
      );
      for (final track in matching.take(limit)) {
        output.add(SmartMatch(track, reason(definition.include, track)));
      }
      return SmartPlaylistResult(
        matches: output,
        matchedCount: matching.length,
        contributions: contributions,
        scarce: false,
        evaluatedAt: time,
      );
    }
    final pools = definition.pools
        .map(
          (pool) => pool.share == 0
              ? <Track>[]
              : sorted(
                  eligible.where((track) => pool.rules.matches(track, time)),
                  pool.order,
                ),
        )
        .toList();
    final matched = pools
        .expand((pool) => pool)
        .map((track) => track.id)
        .toSet()
        .length;
    final used = <String>{};
    final positions = List.filled(pools.length, 0);
    final scores = List.filled(pools.length, 0);
    var scarce = false;
    while (output.length < limit) {
      final active = <int>[];
      var exhausted = false;
      for (var i = 0; i < pools.length; i++) {
        if (definition.pools[i].share == 0) continue;
        while (positions[i] < pools[i].length &&
            used.contains(pools[i][positions[i]].id)) {
          positions[i]++;
        }
        if (positions[i] < pools[i].length) {
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
      var chosen = active.first;
      var total = 0;
      for (final i in active) {
        final share = definition.pools[i].share;
        scores[i] += share;
        total += share;
        if (scores[i] > scores[chosen]) chosen = i;
      }
      scores[chosen] -= total;
      final track = pools[chosen][positions[chosen]++];
      used.add(track.id);
      contributions[chosen]++;
      output.add(
        SmartMatch(
          track,
          '${definition.pools[chosen].name} · ${reason(definition.pools[chosen].rules, track)}',
          pool: chosen,
        ),
      );
    }
    return SmartPlaylistResult(
      matches: output,
      matchedCount: matched,
      contributions: contributions,
      scarce: scarce,
      evaluatedAt: time,
    );
  }
}
