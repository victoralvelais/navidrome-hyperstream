import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperstream_client/services/mornye_sources.dart';
import 'package:hyperstream_client/services/music_provider.dart';
import 'package:mornye_host/mornye_host.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.hyperstream/remote_transfer');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory directory;
  late MornyeSources sources;
  late Map<String, String> saved;
  late List<String> operations;
  late bool rejectDirectory;
  late bool rejectEngine;
  late String? providerFailure;
  late bool rejectPending;

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    directory = await Directory.systemTemp.createTemp('mornye-startup-test-');
    saved = {};
    operations = [];
    rejectDirectory = false;
    rejectEngine = false;
    providerFailure = null;
    rejectPending = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'prepareDirectory');
      expect(call.arguments, '${directory.path}/music-extensions');
      if (rejectDirectory) {
        throw PlatformException(code: 'file_protection');
      }
      return null;
    });
    sources = MornyeSources(
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
        if (request['op'] == 'resolve' && providerFailure != null) {
          throw MornyeHostException(providerFailure!);
        }
        if (request['op'] == 'pending' && rejectPending) {
          throw const MornyeHostException('Private pending request failure');
        }
        if (request['op'] == 'list') {
          return [
            if (providerFailure != null)
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
        sources.execute({'op': 'resolve', 'id': 'qobuz-web'}),
        throwsA(
          isA<SourceException>()
              .having((error) => error.message, 'provider', contains('Qobuz'))
              .having((error) => error.message, 'reason', contains(message))
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
    });
  }
}
