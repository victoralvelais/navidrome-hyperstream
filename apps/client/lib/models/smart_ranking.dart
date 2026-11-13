import 'library.dart';

/// Bounded, explainable ranking. Weights are points, never pool percentages.
class SmartRanking {
  const SmartRanking({
    this.addedWeight = 60,
    this.addedDays = 30,
    this.playedWeight = 25,
    this.playedDays = 30,
    this.favoriteWeight = 15,
    this.playCountWeight = 20,
    this.playCountCap = 20,
  });

  final int addedWeight, addedDays, playedWeight, playedDays;
  final int favoriteWeight, playCountWeight, playCountCap;

  void validate() {
    if ([
      addedWeight,
      playedWeight,
      favoriteWeight,
      playCountWeight,
    ].any((value) => value < 0 || value > 100)) {
      throw const FormatException(
        'Ranking weights must be from 0 to 100 points.',
      );
    }
    if (addedDays < 1 ||
        addedDays > 3650 ||
        playedDays < 1 ||
        playedDays > 3650) {
      throw const FormatException(
        'Ranking windows must be from 1 to 3650 days.',
      );
    }
    if (playCountCap < 1 || playCountCap > 1000000) {
      throw const FormatException(
        'The full play-count penalty needs 1 to 1000000 plays.',
      );
    }
  }

  SmartScore score(Track track, DateTime now) {
    double recency(DateTime? date, int days) {
      if (date == null || date.isAfter(now)) return 0;
      return (1 -
              now.difference(date).inMilliseconds /
                  Duration(days: days).inMilliseconds)
          .clamp(0.0, 1.0);
    }

    return SmartScore({
      if (addedWeight > 0)
        'Added recency': addedWeight * recency(track.addedAt, addedDays),
      if (playedWeight > 0)
        'Played recency':
            playedWeight * recency(track.lastPlayedAt, playedDays),
      if (favoriteWeight > 0)
        'Favorite': track.starred ? favoriteWeight.toDouble() : 0,
      if (playCountWeight > 0)
        'Play-count penalty':
            -playCountWeight * (track.playCount / playCountCap).clamp(0.0, 1.0),
    });
  }

  Map<String, dynamic> toJson() => {
    'addedWeight': addedWeight,
    'addedDays': addedDays,
    'playedWeight': playedWeight,
    'playedDays': playedDays,
    'favoriteWeight': favoriteWeight,
    'playCountWeight': playCountWeight,
    'playCountCap': playCountCap,
  };

  factory SmartRanking.fromJson(Map<String, dynamic> json) {
    final result = SmartRanking(
      addedWeight: json['addedWeight'] as int,
      addedDays: json['addedDays'] as int,
      playedWeight: json['playedWeight'] as int,
      playedDays: json['playedDays'] as int,
      favoriteWeight: json['favoriteWeight'] as int,
      playCountWeight: json['playCountWeight'] as int,
      playCountCap: json['playCountCap'] as int,
    );
    result.validate();
    return result;
  }
}

class SmartScore {
  SmartScore(Map<String, double> contributions)
    : contributions = Map.unmodifiable(contributions);
  final Map<String, double> contributions;
  double get total =>
      contributions.values.fold(0.0, (sum, value) => sum + value);
  String get explanation => contributions.isEmpty
      ? 'Score 0.0 · All ranking weights are off'
      : 'Score ${total.toStringAsFixed(1)} · ${contributions.entries.map((entry) => '${entry.key} ${entry.value < 0 ? '' : '+'}${entry.value.toStringAsFixed(1)}').join(', ')}';
}
