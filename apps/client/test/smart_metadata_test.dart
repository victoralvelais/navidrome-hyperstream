import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:hyperstream_client/app_theme.dart';
import 'package:hyperstream_client/features/playlists/smart_rule_editor.dart';
import 'package:hyperstream_client/models/library.dart';
import 'package:hyperstream_client/models/smart_playlist.dart';
import 'package:hyperstream_client/services/library_catalog.dart';
import 'package:hyperstream_client/services/smart_playlist_preview.dart';

import 'recent_radio_service_test.dart' show api, envelope;
import 'catalog_cache_test.dart' show MemoryCatalogCache;
import 'smart_playlist_screen_test.dart' show tapVisible, field;

void main() {
  test('song genres prefer complete list; legacy fallback remains one literal genre', () {
    final track = Track.fromJson({
      'id': 'a',
      'genres': [
        {'name': ' Rock '},
        {'name': 'rock'},
        {'name': 'Alternative'},
      ],
      'genre': 'Old',
      'year': 2001,
      'userRating': 4,
    });
    expect(track.genres, ['Rock', 'Alternative']);
    expect(track.year, 2001);
    expect(
      track.withActivity(playedAt: DateTime.utc(2026), rating: 5).genres,
      track.genres,
    );
    expect(track.withActivity(favorite: true).year, 2001);
    expect(
      Track.fromJson({'id': 'a', 'genres': [], 'genre': 'R&B, Soul'}).genres,
      ['R&B, Soul'],
    );
    for (final invalid in [0, -1, 10000, 2020.5, '2020', null]) {
      expect(Track.fromJson({'id': 'a', 'year': invalid}).year, isNull);
    }
    expect(
      Track.fromJson({
        'id': 'a',
        'genres': [
          null,
          {'name': 3},
        ],
        'userRating': 8,
      }).genres,
      isEmpty,
    );
  });

  test(
    'genre all-member negation, year boundaries, ratings and missing semantics',
    () {
      final now = DateTime.utc(2026);
      final known = Track.fromJson({
        'id': 'a',
        'genres': [
          {'name': 'Rock'},
          {'name': 'Pop'},
        ],
        'year': 2000,
        'userRating': 4,
      });
      final missing = Track.fromJson({'id': 'b'});
      bool match(
        SmartField field,
        SmartOperator op,
        String value,
        Track track,
      ) => SmartCondition(field, op, value).matches(track, now);
      expect(
        match(SmartField.genre, SmartOperator.equal, ' rOcK ', known),
        isTrue,
      );
      expect(
        match(SmartField.genre, SmartOperator.notContains, 'rock', known),
        isFalse,
      );
      expect(
        match(SmartField.genre, SmartOperator.notContains, 'jazz', known),
        isTrue,
      );
      expect(
        match(SmartField.genre, SmartOperator.notContains, 'jazz', missing),
        isFalse,
      );
      expect(
        match(SmartField.genre, SmartOperator.isMissing, '', missing),
        isTrue,
      );
      expect(
        match(SmartField.genre, SmartOperator.isPresent, '', known),
        isTrue,
      );
      expect(
        match(SmartField.year, SmartOperator.less, '2000', known),
        isFalse,
      );
      expect(
        match(SmartField.year, SmartOperator.equal, '2000', known),
        isTrue,
      );
      expect(
        match(SmartField.year, SmartOperator.less, '2000', missing),
        isFalse,
      );
      expect(
        match(SmartField.year, SmartOperator.isMissing, '', missing),
        isTrue,
      );
      expect(
        match(SmartField.rating, SmartOperator.greater, '3', known),
        isTrue,
      );
      expect(
        match(SmartField.rating, SmartOperator.equal, '0', missing),
        isTrue,
      );
      for (final condition in [
        const SmartCondition(SmartField.year, SmartOperator.equal, '0'),
        const SmartCondition(SmartField.rating, SmartOperator.greater, '6'),
      ]) {
        expect(condition.validate, throwsFormatException);
      }
      final initial = SmartPlaylistDefinition.initial('a').toJson();
      initial['include'] = SmartGroup(
        children: const [
          SmartCondition(SmartField.genre, SmartOperator.contains, 'rock'),
          SmartCondition(SmartField.year, SmartOperator.greater, '1999'),
          SmartCondition(SmartField.rating, SmartOperator.greater, '3'),
        ],
      ).toJson();
      final definition = SmartPlaylistDefinition.fromJson(initial);
      expect(
        SmartPlaylistResult.evaluate(
          [known, missing],
          definition,
          now,
        ).matches.single.track.id,
        'a',
      );
      expect(
        SmartPlaylistDefinition.fromJson(definition.toJson()).toJson(),
        definition.toJson(),
      );
    },
  );

  test('acknowledged ratings update previews, survive restart and reconcile without scans', () async {
    final now = DateTime.utc(2026, 11, 13);
    var remoteRating = 0, scans = 0;
    var failRating = false;
    final client = api((request) {
      if (request.url.path.contains('setRating')) {
        return failRating ? http.Response('', 500) : envelope({});
      }
      final first = request.url.queryParameters['songOffset'] == '0';
      if (first) scans++;
      return envelope({
        'searchResult3': {
          'song': first
              ? [
                  {
                    'id': 'a',
                    'created': '2026-11-01T00:00:00Z',
                    'year': 2001,
                    'genre': 'Rock',
                    'userRating': remoteRating,
                  },
                ]
              : [],
        },
      });
    });
    final cache = MemoryCatalogCache();
    final catalog = LibraryCatalog(client, now: () => now, cache: cache);
    final preview = SmartPlaylistPreview(catalog);
    addTearDown(() {
      preview.dispose();
      catalog.dispose();
      client.close();
    });
    final json = SmartPlaylistDefinition.initial('a').toJson();
    json['include'] = SmartGroup(
      children: const [
        SmartCondition(SmartField.rating, SmartOperator.greater, '3'),
      ],
    ).toJson();
    await preview.update(SmartPlaylistDefinition.fromJson(json));
    await catalog.ensureLoaded();
    expect(preview.result!.matches, isEmpty);
    await client.setRating('a', 5);
    await Future<void>.delayed(Duration.zero);
    expect(preview.result!.matches.single.track.userRating, 5);
    expect(scans, 1);
    failRating = true;
    await expectLater(client.setRating('a', 0), throwsException);
    expect(catalog.tracks.single.userRating, 5);
    await catalog.flushCache();
    final restored = LibraryCatalog(client, now: () => now, cache: cache);
    await restored.ensureLoaded();
    expect(restored.tracks.single.userRating, 5);
    expect(restored.tracks.single.genres, ['Rock']);
    expect(restored.tracks.single.year, 2001);
    expect(scans, 1);
    restored.dispose();
    await catalog.refresh(); // stale server response cannot undo the local acknowledgement
    expect(catalog.tracks.single.userRating, 5);
    remoteRating = 5;
    await catalog.refresh();
    await catalog.flushCache();
    expect(cache.saved!.ratings, isEmpty);
    remoteRating = 2;
    await catalog.refresh();
    expect(preview.result!.matches, isEmpty);
    failRating = false;
    await client.setRating('a', 0);
    await Future<void>.delayed(Duration.zero);
    expect(catalog.tracks.single.userRating, 0);
  });

  for (final width in [320.0, 1280.0]) {
    testWidgets(
      'metadata conditions edit at $width with missing and numeric controls',
      (tester) async {
        tester.view.physicalSize = Size(width, 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var group = SmartGroup();
        await tester.pumpWidget(
          MaterialApp(
            theme: hyperstreamTheme(Brightness.dark),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(1.4)),
              child: child!,
            ),
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) => ListView(
                  children: [
                    SmartRuleEditor(
                      title: 'Include',
                      group: group,
                      onChanged: (value) => setState(() => group = value),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        for (final name in ['Genre', 'Release year', 'My rating']) {
          await tapVisible(tester, find.text('Add condition'));
          await tapVisible(tester, find.byTooltip('Field'));
          await tapVisible(tester, find.text(name));
          if (name == 'Genre') {
            await tester.enterText(field('Value'), 'Rock');
          } else if (name == 'Release year') {
            await tapVisible(tester, find.byTooltip('Condition'));
            await tapVisible(tester, find.text('Is missing'));
            expect(field('Value'), findsNothing);
          } else {
            await tester.enterText(field('Value'), '4');
          }
          await tapVisible(tester, find.text('Apply'));
        }
        expect(group.children.map((c) => (c as SmartCondition).field), [
          SmartField.genre,
          SmartField.year,
          SmartField.rating,
        ]);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
