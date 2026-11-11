import 'package:flutter_test/flutter_test.dart';
import 'package:hyperstream_client/models/library.dart';
import 'package:hyperstream_client/models/recent_radio.dart';

Track song(String id, {String? added, String? played}) =>
    Track.fromJson({'id': id, 'created': added, 'played': played});

void main() {
  final now = DateTime.utc(2026, 11, 11, 18);
  const definition = RecentRadioDefinition();
  test(
    'script semantics: OR, maximum date, inclusive cutoff and stable ties',
    () {
      final preview = RadioPreview.evaluate(
        [
          song(
            'inactive',
            added: '2026-10-01T00:00:00Z',
            played: '2026-10-02T00:00:00Z',
          ),
          song('boundary', added: '2026-10-12T18:00:00Z'),
          song(
            'both',
            added: '2026-11-09T12:00:00Z',
            played: '2026-11-10T09:00:00Z',
          ),
          song('new', added: '2026-11-10T12:00:00Z'),
          song(
            'favorite',
            added: '2026-08-01T00:00:00Z',
            played: '2026-11-11T17:00:00Z',
          ),
          song('equal-b', added: '2026-11-10T06:00:00-06:00'),
          song('equal-a', played: '2026-11-10T12:00:00Z'),
          song('too-old', added: '2026-10-12T17:59:59.999999Z'),
        ],
        definition,
        now,
      );
      expect(preview.matches.map((m) => m.track.id), [
        'favorite',
        'equal-a',
        'equal-b',
        'new',
        'both',
        'boundary',
      ]);
      expect(preview.matches.first.reason, 'Played recently');
      expect(preview.matches[4].reason, 'Added and played recently');
      expect(preview.matches.last.reason, 'Added recently');
    },
  );

  test('deduplication, missing and anomalous dates are explicit', () {
    final preview = RadioPreview.evaluate(
      [
        song('duplicate', added: '2026-11-10T00:00:00Z'),
        song('duplicate', added: '2026-11-10T00:00:00Z'),
        song('missing'),
        song(
          'future',
          added: '2027-01-01T00:00:00Z',
          played: '2026-11-09T00:00:00Z',
        ),
        song('malformed', added: 'private-invalid-value'),
        song('old', added: '2020-01-01T00:00:00Z'),
      ],
      definition,
      now,
    );
    expect(preview.libraryCount, 5);
    expect(preview.matches.map((m) => m.track.id), ['duplicate', 'future']);
    expect(preview.invalidDates, 2);
    expect(preview.missingDates, 2);
    expect(preview.hasPlayDates, isTrue);
  });

  test('timestamp parser rejects normalized invalid dates and ambiguous local times', () {
    for (final invalid in [
      '2026-02-30T00:00:00Z',
      '2026-01-01T25:00:00Z',
      '2026-01-01T00:00:00+99:00',
      '2026-01-01T00:00:00+00:99',
      '2026-01-01T00:00:00',
      '2026-00-01T00:00:00Z',
      'not-a-date',
    ]) {
      expect(activityDate(invalid), isNull, reason: invalid);
    }
    expect(
      activityDate('2024-02-29T18:00:00.123456789+02:00'),
      DateTime.utc(2024, 2, 29, 16, 0, 0, 123, 456),
    );
  });
}
