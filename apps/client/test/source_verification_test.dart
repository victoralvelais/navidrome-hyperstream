import 'dart:io';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperstream_client/services/mornye_sources.dart';
import 'package:hyperstream_client/services/music_provider.dart';
import 'package:hyperstream_client/services/source_verification.dart';
import 'package:mornye_host/mornye_host.dart';

Map<String, String> challenge(String id, {String scheme = 'mornye'}) => {
  'extension_id': id,
  'auth_url': 'https://example.test/challenge?id=synthetic',
  'callback_url': '$scheme://session-grant?state=synthetic-$id',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('callbacks and copied grant fields retain state validation', () {
    final pending = SourceVerification(challenge('qobuz-web'));
    for (final text in [
      'grant=gr_synthetic',
      '  grant=gr_synthetic  ',
      '?grant=gr_synthetic',
      'code=gr_synthetic&state=synthetic-qobuz-web',
      'mornye://session-grant?grant=gr_synthetic&state=synthetic-qobuz-web',
    ]) {
      expect(pending.grant(text, manual: true), 'gr_synthetic');
    }
    for (final text in [
      '',
      'grant=',
      'grant=one&grant=two',
      'grant=one&code=two',
      'grant=one&state=wrong',
      'grant=one&state=synthetic-qobuz-web&state=wrong',
      'grant=%00secret',
      'https://example.test/?grant=one',
      'mornye://other?grant=one',
      'mornye://session-grant?grant=one',
    ]) {
      expect(
        () => pending.grant(text, manual: true),
        throwsA(isA<SourceException>()),
      );
    }
    expect(
      () => pending.grant('grant=gr_synthetic', manual: false),
      throwsA(isA<SourceException>()),
    );
    expect(
      () => pending.grant(
        'mornye://session-grant?grant=gr_synthetic',
        manual: false,
      ),
      throwsA(isA<SourceException>()),
    );
  });

  late Directory directory;
  late MornyeSources sources;
  late Map<String, String> saved;
  late Map<String, Map<String, String>> pending;
  late List<Map<String, dynamic>> calls;
  late Future<String> Function(Uri, String) browser;
  late bool rejectGrant;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'hyperstream-verification-',
    );
    saved = {};
    pending = {};
    calls = [];
    rejectGrant = false;
    browser = (_, _) async => throw PlatformException(code: 'CANCELED');
    sources = MornyeSources(
      directory: () async => directory,
      read: (key) async => saved[key],
      write: (key, value) async {
        saved[key] = value;
      },
      authenticate: (url, scheme) => browser(url, scheme),
      native: (request) async {
        calls.add(request);
        final id = request['id'] as String?;
        switch (request['op']) {
          case 'list':
            return [];
          case 'ffmpeg_poll':
            return [];
          case 'pending':
            return pending[id];
          case 'verify':
            return pending[id!] ??= challenge(id);
          case 'grant':
            expect(request['state'], 'synthetic-$id');
            if (rejectGrant) {
              throw const MornyeHostException('private grant detail');
            }
            pending.remove(id);
            return {'success': true};
          default:
            return null;
        }
      },
    );
  });
  tearDown(() async {
    sources.dispose();
    await directory.delete(recursive: true);
  });

  test(
    'concurrent requests share a browser and other providers wait their turn',
    () async {
      final first = Completer<bool>();
      final second = Completer<bool>();
      final shown = <String>[];
      sources.presentVerification = (id) {
        shown.add(id);
        return id == 'tidal-web' ? first.future : second.future;
      };
      final a = sources.requestVerification('tidal-web');
      final b = sources.requestVerification('tidal-web');
      final c = sources.requestVerification('qobuz-web');
      await Future<void>.delayed(Duration.zero);
      expect(shown, ['tidal-web']);
      first.complete(true);
      expect(await a, true);
      expect(await b, true);
      await Future<void>.delayed(Duration.zero);
      expect(shown, ['tidal-web', 'qobuz-web']);
      second.complete(false);
      expect(await c, false);
      sources.presentVerification = (_) async => true;
      expect(await sources.requestVerification('qobuz-web'), true);
    },
  );

  test(
    'catalog recovery retries once and cancellation never reopens the browser',
    () async {
      var prompts = 0, attempts = 0;
      sources.presentVerification = (_) async {
        prompts++;
        return true;
      };
      expect(
        await sources.withVerification(() async {
          if (++attempts == 1) throw ProviderVerificationRequired('tidal-web');
          return 'song';
        }),
        'song',
      );
      expect(attempts, 2);
      expect(prompts, 1);
      await expectLater(
        sources.withVerification(
          () async => throw ProviderVerificationRequired('tidal-web'),
        ),
        throwsA(isA<ProviderVerificationRequired>()),
      );
      expect(
        prompts,
        2,
        reason: 'A second challenge in the same action must not loop.',
      );
      sources.presentVerification = (_) async {
        prompts++;
        return false;
      };
      await expectLater(
        sources.withVerification(
          () async => throw ProviderVerificationRequired('tidal-web'),
        ),
        throwsA(
          isA<SourceException>().having(
            (e) => e.message,
            'message',
            contains('not completed'),
          ),
        ),
      );
      expect(prompts, 3);
    },
  );

  for (final id in ['qobuz-web', 'tidal-web', 'amazon']) {
    test(
      '$id browser cancellation preserves the challenge for bare grant paste',
      () async {
        expect(await sources.verify(id), false);
        expect(sources.verification.value, id);
        final savedBefore = Map.of(saved);
        await sources.pasteVerification(id, 'grant=gr_synthetic');
        expect(calls.where((r) => r['op'] == 'verify'), hasLength(1));
        expect(
          calls.where((r) => r['op'] == 'grant').single['grant'],
          'gr_synthetic',
        );
        expect(sources.verification.value, isNull);
        expect(
          saved,
          savedBefore,
          reason:
              'Grants belong only in the native encrypted session exchange.',
        );
        await expectLater(
          sources.pasteVerification(id, 'grant=gr_synthetic'),
          throwsA(isA<SourceException>()),
        );
      },
    );
  }

  for (final scheme in ['mornye', 'hyperstream']) {
    test('automatic return captures the pending $scheme callback', () async {
      pending['tidal-web'] = challenge('tidal-web', scheme: scheme);
      browser = (url, actualScheme) async {
        expect(actualScheme, scheme);
        expect(url.host, 'example.test');
        return '$scheme://session-grant?state=synthetic-tidal-web&grant=gr_synthetic';
      };
      sources.issue.value = 'Previous playback failure';
      expect(await sources.verify('tidal-web'), true);
      expect(sources.issue.value, isNull);
      expect(pending, isEmpty);
    });
  }

  test(
    'another provider callback and expired attempts never reach grant exchange',
    () async {
      pending['qobuz-web'] = challenge('qobuz-web');
      await expectLater(
        sources.pasteVerification(
          'qobuz-web',
          'grant=gr_synthetic&state=synthetic-tidal-web',
        ),
        throwsA(isA<SourceException>()),
      );
      await expectLater(
        sources.pasteVerification('tidal-web', 'grant=gr_synthetic'),
        throwsA(
          isA<SourceException>().having(
            (e) => e.message,
            'message',
            contains('expired'),
          ),
        ),
      );
      expect(
        calls.where((r) => ['grant', 'verify'].contains(r['op'])),
        isEmpty,
      );
    },
  );

  test(
    'a rejected grant keeps the attempt and never exposes native details',
    () async {
      pending['qobuz-web'] = challenge('qobuz-web');
      rejectGrant = true;
      await expectLater(
        sources.pasteVerification('qobuz-web', 'grant=gr_synthetic'),
        throwsA(
          isA<SourceException>().having(
            (e) => e.message,
            'message',
            isNot(contains('private')),
          ),
        ),
      );
      expect(pending, contains('qobuz-web'));
      expect(sources.verification.value, 'qobuz-web');
    },
  );
}
