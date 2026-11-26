import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperstream_client/services/mornye_sources.dart';
import 'package:hyperstream_client/services/music_provider.dart';
import 'package:hyperstream_client/services/playback_diagnostics.dart';
import 'package:mornye_host/mornye_host.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.hyperstream/remote_transfer');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory directory;
  late MornyeSources sources;
  late PlaybackDiagnostics diagnostics;
  late Map<String, String> saved;
  late List<String> operations;
  late bool rejectDirectory;
  late bool rejectEngine;
  late String? providerFailure;
  late Map<String, Object>? structuredFailure;
  late bool rejectPending;

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    directory = await Directory.systemTemp.createTemp('mornye-startup-test-');
    saved = {};
    operations = [];
    rejectDirectory = false;
    rejectEngine = false;
    providerFailure = null;
    structuredFailure = null;
    rejectPending = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'prepareDirectory');
      expect(call.arguments, '${directory.path}/music-extensions');
      if (rejectDirectory) {
        throw PlatformException(code: 'file_protection');
      }
      return null;
    });
    diagnostics = PlaybackDiagnostics();
    sources = MornyeSources(
      diagnostics: diagnostics,
      directory: () async => directory,
      read: (key) async => saved[key],
      write: (key, value) async {
        saved[key] = value;
      },
      native: (request) async {
        operations.add(request['op'] as String);
        if (rejectEngine) {
          throw const MornyeHostException(
            'Synthetic failure with private/path and secret=session',
          );
        }
        if (request['method'] == 'hyperstreamResolve' &&
            providerFailure != null) {
          throw MornyeHostException(providerFailure!);
        }
        if (const {
          'hyperstreamResolve',
          'hyperstreamDownload',
        }.contains(request['method'])) {
          return structuredFailure;
        }
        if (request['op'] == 'pending' && rejectPending) {
          throw const MornyeHostException('Private pending request failure');
        }
        if (request['op'] == 'list') {
          return [
            if (providerFailure != null || structuredFailure != null)
              {
                'id': 'qobuz-web',
                'display_name': 'Qobuz',
                'version': '1.0.0',
                'download_url': 'https://example.test/qobuz.sflx',
                'sha256': '0' * 64,
                'installed': true,
                'enabled': true,
              },
            {
              'id': 'spotify-web',
              'display_name': 'Spotify Web',
              'version': '1.0.0',
              'download_url': 'https://example.test/provider.sflx',
              'sha256': '0' * 64,
              'installed': false,
            },
          ];
        }
        return null;
      },
    );
  });

  tearDown(() async {
    sources.dispose();
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
    await directory.delete(recursive: true);
  });

  test(
    'iOS storage rejection explains the stage and retry loads providers',
    () async {
      rejectDirectory = true;
      await sources.restore();
      expect(sources.error, contains('storage could not be prepared'));
      expect(sources.error, isNot(contains('Unlock')));
      expect(operations, isEmpty);
      expect(saved, isEmpty);

      rejectDirectory = false;
      await sources.restore();
      expect(sources.error, isNull);
      expect(sources.extensions.single.id, 'spotify-web');
      expect(operations, ['init', 'list']);
    },
  );

  test(
    'engine failures hide private details and retry preserves the key',
    () async {
      rejectEngine = true;
      await sources.restore();
      expect(sources.error, contains('extension engine could not start'));
      expect(sources.error, isNot(contains('private/path')));
      expect(sources.error, isNot(contains('secret=session')));
      final original = Map<String, String>.from(saved);
      expect(original, isNotEmpty);

      rejectEngine = false;
      await sources.restore();
      expect(sources.error, isNull);
      expect(saved, original);
      expect(sources.extensions.single.id, 'spotify-web');
    },
  );

  for (final (detail, message) in [
    ('request timed out', 'took too long'),
    ('HTTP 429', 'limiting requests'),
    ('HTTP 503', 'temporarily unavailable'),
    ('HTTP 403', 'rejected access'),
    ('HTTP 404', 'could not provide this recording'),
    ('unexpected response', 'could not complete this request'),
  ]) {
    test('Qobuz reports a safe message for $detail', () async {
      providerFailure = '$detail https://example.test/audio?token=synthetic';
      rejectPending = true;
      await expectLater(
        sources.execute({
          'op': 'resolve',
          'id': 'qobuz-web',
          'method': 'hyperstreamResolve',
        }),
        throwsA(
          isA<SourceException>()
              .having((error) => error.message, 'provider', contains('Qobuz'))
              .having((error) => error.message, 'reason', contains(message))
              .having(
                (error) => error.retryable,
                'automatic retry',
                !['HTTP 429', 'HTTP 403', 'HTTP 404'].contains(detail),
              )
              .having(
                (error) => error.message,
                'sanitized text',
                allOf(
                  isNot(contains('example.test')),
                  isNot(contains('token=synthetic')),
                  isNot(contains('pending request failure')),
                ),
              ),
        ),
      );
      final report = diagnostics.report();
      final events =
          (jsonDecode(report) as Map<String, dynamic>)['events']
              as List<dynamic>;
      expect(events.last, containsPair('stage', 'resolve'));
      expect(events.last, containsPair('outcome', 'failed'));
      expect(events.last, containsPair('source', 'Qobuz'));
      expect(report, isNot(contains('example.test')));
    });
  }

  test('exhausted Qobuz audio providers stop automatic retries', () async {
    providerFailure =
        'All Qobuz download providers failed: HTTP 503; '
        'HTTP 429 https://example.test/audio?token=synthetic';
    await expectLater(
      sources.execute({
        'op': 'call',
        'id': 'qobuz-web',
        'method': 'hyperstreamResolve',
      }),
      throwsA(
        isA<SourceException>()
            .having((error) => error.retryable, 'automatic retry', isFalse)
            .having(
              (error) => error.facts?.reasons,
              'facts',
              contains('all-audio-providers-failed'),
            )
            .having((error) => error.facts?.httpStatuses, 'HTTP statuses', [
              429,
              503,
            ]),
      ),
    );
    expect(diagnostics.report(), isNot(contains('token=synthetic')));
  });

  test(
    'native Qobuz response correlates and classifies provider attempts',
    () async {
      const trackId = 'synthetic-private-track-id';
      structuredFailure = {
        'success': false,
        'error_message': 'All Qobuz download providers failed',
        'provider_failures': [
          {
            'candidate': 1,
            'quality': '6',
            'message': 'HTTP 503 for https://example.test/?token=synthetic',
            'code': 'PROVIDER_UNAVAILABLE',
            'retry_mode': 'new_ticket',
          },
        ],
      };
      await expectLater(
        sources.execute({
          'op': 'call',
          'id': 'qobuz-web',
          'method': 'hyperstreamResolve',
          'args': [trackId, 'LOSSLESS'],
        }),
        throwsA(
          isA<SourceException>()
              .having((error) => error.retryable, 'automatic retry', isFalse)
              .having(
                (error) => error.facts?.reasons,
                'facts',
                contains('provider-unavailable'),
              ),
        ),
      );
      final report = diagnostics.report();
      final events =
          (jsonDecode(report) as Map<String, dynamic>)['events'] as List;
      final started = events.first as Map;
      final failed = events.last as Map;
      expect(started['outcome'], 'started');
      expect(failed['outcome'], 'failed');
      expect(failed['recording'], isA<int>());
      expect(failed['operation'], isA<int>());
      expect(started['recording'], failed['recording']);
      expect(started['operation'], failed['operation']);
      expect(failed['method'], 'hyperstreamResolve');
      expect(failed['provider_failures'], [
        {
          'candidate': 1,
          'quality': '6',
          'code': 'PROVIDER_UNAVAILABLE',
          'retry_mode': 'new_ticket',
          'reasons': ['upstream-service-error', 'provider-unavailable'],
          'http_status': [503],
        },
      ]);
      for (final value in [trackId, 'example.test', 'token=synthetic']) {
        expect(report, isNot(contains(value)));
      }
    },
  );

  test(
    'structured download failure supplies safe facts to diagnostics',
    () async {
      structuredFailure = {
        'success': false,
        'error_message': 'HTTP 503 for https://example.test/?token=synthetic',
      };
      await expectLater(
        sources.execute({
          'op': 'download',
          'id': 'qobuz-web',
          'method': 'hyperstreamDownload',
        }),
        throwsA(
          isA<SourceException>().having(
            (error) => error.message,
            'message',
            contains('temporarily unavailable'),
          ),
        ),
      );
      final report = diagnostics.report();
      final events =
          (jsonDecode(report) as Map<String, dynamic>)['events']
              as List<dynamic>;
      expect(events.last, containsPair('stage', 'download'));
      expect(events.last, containsPair('outcome', 'failed'));
      expect(events.last, containsPair('http_status', [503]));
      expect(report, isNot(contains('example.test')));
    },
  );
}
