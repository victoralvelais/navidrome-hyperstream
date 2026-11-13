import 'package:flutter/material.dart';

import '../../models/smart_ranking.dart';

class SmartRankingEditor extends StatelessWidget {
  const SmartRankingEditor({
    super.key,
    required this.ranking,
    required this.onChanged,
  });
  final SmartRanking ranking;
  final ValueChanged<SmartRanking> onChanged;

  void _change(String field, int value) {
    // Keep incomplete numeric input visible until validation on Preview/Save.
    final values = ranking.toJson()..[field] = value;
    onChanged(
      SmartRanking(
        addedWeight: values['addedWeight'],
        addedDays: values['addedDays'],
        playedWeight: values['playedWeight'],
        playedDays: values['playedDays'],
        favoriteWeight: values['favoriteWeight'],
        playCountWeight: values['playCountWeight'],
        playCountCap: values['playCountCap'],
      ),
    );
  }

  Widget _weight(String title, String field, int value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('$title · $value points'),
      Slider(
        key: ValueKey(field),
        value: value.toDouble(),
        min: 0,
        max: 100,
        divisions: 100,
        label: '$value points',
        semanticFormatterCallback: (value) => '${value.round()} points',
        onChanged: (value) => _change(field, value.round()),
      ),
    ],
  );

  Widget _number(String label, String field, int value) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      key: ValueKey(field),
      initialValue: '$value',
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label),
      onChanged: (text) => _change(field, int.tryParse(text.trim()) ?? -1),
    ),
  );

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Higher scores come first. Weights are points, not mix percentages. Set a weight to 0 to ignore it.',
        ),
        const SizedBox(height: 16),
        _weight('Added recency boost', 'addedWeight', ranking.addedWeight),
        _number(
          'Added boost fades to zero after (days)',
          'addedDays',
          ranking.addedDays,
        ),
        _weight('Played recency boost', 'playedWeight', ranking.playedWeight),
        _number(
          'Played boost fades to zero after (days)',
          'playedDays',
          ranking.playedDays,
        ),
        _weight('Favorite bonus', 'favoriteWeight', ranking.favoriteWeight),
        _weight(
          'Play-count penalty',
          'playCountWeight',
          ranking.playCountWeight,
        ),
        _number(
          'Full penalty at this many plays',
          'playCountCap',
          ranking.playCountCap,
        ),
        const Text(
          'Recency boosts fade evenly over their windows. Missing or future dates earn no boost. The play-count penalty grows up to its maximum. Equal scores use track ID; artist spacing can move a lower score forward.',
        ),
      ],
    ),
  );
}
