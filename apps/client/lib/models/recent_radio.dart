import 'library.dart';

/// Fixed built-in preset. A future smart-playlist editor owns separate rules.
class RecentRadioDefinition {
  const RecentRadioDefinition();
  final String name = 'Recent Radio';
  final int days = 30;
}

class RadioMatch {
  const RadioMatch(
    this.track,
    this.activityAt, {
    required this.added,
    required this.played,
  });
  final Track track;
  final DateTime activityAt;
  final bool added;
  final bool played;
  String get reason => added && played
      ? 'Added and played recently'
      : added
      ? 'Added recently'
      : 'Played recently';
}

class RadioPreview {
  RadioPreview({
    required this.definition,
    required this.evaluatedAt,
    required List<RadioMatch> matches,
    required this.libraryCount,
    required this.missingDates,
    required this.invalidDates,
    required this.hasPlayDates,
  }) : matches = List.unmodifiable(matches);
  final RecentRadioDefinition definition;
  final DateTime evaluatedAt;
  final List<RadioMatch> matches;
  final int libraryCount;
  final int missingDates;
  final int invalidDates;
  final bool hasPlayDates;

  static RadioPreview evaluate(
    Iterable<Track> tracks,
    RecentRadioDefinition definition,
    DateTime now,
  ) {
    if (definition.days < 1 || definition.days > 3650) {
      throw ArgumentError.value(definition.days, 'days');
    }
    final time = now.toUtc();
    final cutoff = time.subtract(Duration(days: definition.days));
    final unique = <String, Track>{for (final track in tracks) track.id: track};
    final matches = <RadioMatch>[];
    var missing = 0;
    var invalid = 0;
    var hasPlayDates = false;
    for (final track in unique.values) {
      DateTime? valid(DateTime? date) =>
          date == null || date.isAfter(time) ? null : date.toUtc();
      final addedAt = valid(track.addedAt);
      final playedAt = valid(track.lastPlayedAt);
      hasPlayDates = hasPlayDates || playedAt != null;
      if (track.invalidActivityDates ||
          (track.addedAt?.isAfter(time) ?? false) ||
          (track.lastPlayedAt?.isAfter(time) ?? false)) {
        invalid++;
      }
      if (addedAt == null && playedAt == null) {
        missing++;
        continue;
      }
      final added = addedAt != null && !addedAt.isBefore(cutoff);
      final played = playedAt != null && !playedAt.isBefore(cutoff);
      if (!added && !played) continue;
      final activity = addedAt == null
          ? playedAt!
          : playedAt == null
          ? addedAt
          : addedAt.isAfter(playedAt)
          ? addedAt
          : playedAt;
      matches.add(RadioMatch(track, activity, added: added, played: played));
    }
    matches.sort((a, b) {
      final byDate = b.activityAt.compareTo(a.activityAt);
      return byDate == 0 ? a.track.id.compareTo(b.track.id) : byDate;
    });
    return RadioPreview(
      definition: definition,
      evaluatedAt: time,
      matches: matches,
      libraryCount: unique.length,
      missingDates: missing,
      invalidDates: invalid,
      hasPlayDates: hasPlayDates,
    );
  }
}
