import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyperstream_client/services/playback_diagnostics.dart';

List<dynamic> _events(String report) =>
    (jsonDecode(report) as Map<String, dynamic>)['events'] as List<dynamic>;

void main() {
  test('report exports only approved provider error facts', () {
    final diagnostics = PlaybackDiagnostics();
    diagnostics.record(
      stage: PlaybackStage.resolve,
      outcome: PlaybackOutcome.failed,
      sourceId: 'mornye:qobuz-web',
      extensionVersion: '1.2.3',
      elapsedMs: 123,
      privateError:
          'All Qobuz download providers failed: HTTP 503; HTTP 429; HTTP 429 '
          'for https://example.test/private?token=synthetic '
          'with Authorization: Bearer private-token at /tmp/private-file',
    );

    final report = diagnostics.report(appVersion: '1.2.3', platform: 'windows');
    final event = _events(report).single as Map<String, dynamic>;
    expect(event['source'], 'Qobuz');
    expect(event['stage'], 'resolve');
    expect(event['outcome'], 'failed');
    expect(event['extension_version'], '1.2.3');
    expect(event['elapsed_ms'], 123);
    expect(event['http_status'], [429, 503]);
    expect(event['reasons'], [
      'all-audio-providers-failed',
      'rate-limited',
      'upstream-service-error',
    ]);
    for (final privateValue in [
      'example.test',
      'token=synthetic',
      'Authorization',
      'private-token',
      '/tmp/private-file',
    ]) {
      expect(report, isNot(contains(privateValue)));
    }
  });

  test('report bounds the session timeline and rejects unknown metadata', () {
    final diagnostics = PlaybackDiagnostics();
    for (var index = 0; index < 81; index++) {
      diagnostics.record(
        stage: PlaybackStage.player,
        outcome: PlaybackOutcome.failed,
        sourceId: 'private-source',
        extensionVersion: 'private-build',
        privateError: 'private-error',
      );
    }

    final report = diagnostics.report(
      appVersion: 'private-build',
      platform: 'private-platform',
    );
    final events = _events(report);
    expect(events, hasLength(80));
    expect(events.first['event'], 2);
    expect(events.last['event'], 81);
    expect(events.last['reasons'], ['unclassified-error']);
    expect(report, isNot(contains('private-')));
  });

  test(
    'report bounds nested provider failures and strips private metadata',
    () {
      final diagnostics = PlaybackDiagnostics();
      const source = 'mornye:qobuz-web';
      final recording = diagnostics.recording(source, 'private-track-id');
      final otherRecording = diagnostics.recording(source, 'private-other-id');
      expect(diagnostics.recording(source, 'private-track-id'), recording);
      expect(otherRecording, isNot(recording));
      diagnostics.record(
        stage: PlaybackStage.match,
        outcome: PlaybackOutcome.ready,
        sourceId: 'mornye:spotify-web',
        recording: otherRecording,
        matchedRecording: recording,
      );
      diagnostics.record(
        stage: PlaybackStage.resolve,
        outcome: PlaybackOutcome.failed,
        sourceId: source,
        recording: recording,
        method: 'private-method',
        privateProviderFailures: [
          {
            'candidate': 99,
            'quality': 'private-quality',
            'code': 'private-code',
            'retry_mode': 'private-retry',
            'message': 'Ticket expired at https://private-host/?sig=secret',
            'provider_id': 'private-provider',
          },
          for (var i = 2; i <= 14; i++) {'candidate': i, 'message': 'HTTP 429'},
        ],
      );
      final report = diagnostics.report();
      final events = _events(report);
      expect(events.first['matched_recording'], events.last['recording']);
      expect(events.last['method'], isNull);
      final failures = events.last['provider_failures'] as List;
      expect(failures, hasLength(12));
      expect(failures.first, {
        'code': 'UNRECOGNIZED',
        'reasons': ['ticket-rejected'],
      });
      expect(failures.last, {
        'candidate': 12,
        'reasons': ['rate-limited'],
        'http_status': [429],
      });
      expect(report, isNot(contains('private-')));
      expect(report, isNot(contains('sig=secret')));
    },
  );
}
