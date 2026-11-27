import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperstream_client/services/player_snapshot.dart';
// The interface is bundled with path_provider and only used here for its fake.
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _TestPaths extends PathProviderPlatform {
  _TestPaths(this.cache, this.downloads);

  final Directory cache;
  final Directory downloads;

  @override
  Future<String?> getTemporaryPath() async => cache.path;

  @override
  Future<String?> getDownloadsPath() async => downloads.path;
}

Future<void> _linkDirectory(String path, Directory target) async {
  if (!Platform.isWindows) {
    await Link(path).create(target.path);
    return;
  }
  // Windows junctions are available without administrator privileges.
  final result = await Process.run(
    'powershell.exe',
    [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      'New-Item -ErrorAction Stop -ItemType Junction '
          r'-Path $env:SNAPSHOT_TEST_LINK -Target $env:SNAPSHOT_TEST_TARGET',
    ],
    environment: {
      'SNAPSHOT_TEST_LINK': path.replaceAll('/', '\\'),
      'SNAPSHOT_TEST_TARGET': target.path.replaceAll('/', '\\'),
    },
  );
  expect(result.exitCode, 0, reason: 'Could not create a test junction.');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const share = MethodChannel('dev.hyperstream/share');
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8'
    '/x8AAwMCAO+ip1sAAAAASUVORK5CYII=',
  );
  late Directory root;
  late Directory cache;
  late Directory downloads;
  late PathProviderPlatform originalPaths;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('player-snapshot-test-');
    cache = await Directory('${root.path}/cache').create();
    downloads = await Directory('${root.path}/Downloads').create();
    originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TestPaths(cache, downloads);
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  });

  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(share, null);
    PathProviderPlatform.instance = originalPaths;
    await root.delete(recursive: true);
  });

  test(
    'iOS hands a PNG to the native sheet and preserves recent files',
    () async {
      final attachments = <File>[];
      messenger.setMockMethodCallHandler(share, (call) async {
        expect(call.method, 'shareFile');
        final file = File(call.arguments as String);
        expect(file.parent.parent.uri, cache.uri.resolve('hyperstream-share/'));
        expect(
          file.uri.pathSegments[file.uri.pathSegments.length - 2],
          startsWith('snapshot-'),
        );
        expect(file.uri.pathSegments.last, matches(r'^Hyperstream-\d+\.png$'));
        expect(await file.readAsBytes(), png);
        attachments.add(file);
        return false;
      });

      expect(await PlayerSnapshot.share(png), isFalse);
      expect(await PlayerSnapshot.share(png), isFalse);
      expect(attachments, hasLength(2));
      expect(attachments.last.parent.uri, isNot(attachments.first.parent.uri));
      expect(await attachments.first.readAsBytes(), png);
    },
  );

  test('iOS propagates a missing native share handler', () async {
    await expectLater(
      PlayerSnapshot.share(png),
      throwsA(isA<MissingPluginException>()),
    );
  });

  test(
    'iOS expires snapshot directories while preserving audio and links',
    () async {
      final shareRoot = await Directory('${cache.path}/hyperstream-share')
          .create();
      final expired = await Directory('${shareRoot.path}/snapshot-expired')
          .create();
      final audio = await Directory('${shareRoot.path}/track-audio').create();
      final target = await Directory('${root.path}/outside-share-cache')
          .create();
      final attachment = await File('${audio.path}/song.mp3').writeAsBytes([1]);
      final outsideFile = await File('${target.path}/preserve.txt')
          .writeAsString('preserve');
      final linkedSnapshot = '${shareRoot.path}/snapshot-linked';
      await _linkDirectory(linkedSnapshot, target);
      await _linkDirectory('${expired.path}/nested-link', target);
      await File('${expired.path}/old.png').writeAsBytes(png);
      final future = DateTime.now().add(const Duration(days: 2));
      messenger.setMockMethodCallHandler(share, (_) async => false);

      expect(await PlayerSnapshot.share(png, now: () => future), isFalse);
      expect(await expired.exists(), isFalse);
      expect(await attachment.readAsBytes(), [1]);
      expect(await Directory(linkedSnapshot).exists(), isTrue);
      expect(await outsideFile.readAsString(), 'preserve');
    },
  );

  test('Windows saves the PNG directly to Downloads', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    messenger.setMockMethodCallHandler(share, (_) async {
      fail('Windows must save the file without invoking the share sheet.');
    });

    expect(await PlayerSnapshot.share(png), isTrue);
    final attachment = (await downloads.list().toList()).single as File;
    expect(
      attachment.uri.pathSegments.last,
      matches(r'^Hyperstream-\d+\.png$'),
    );
    expect(await attachment.readAsBytes(), png);
    expect(await cache.list().toList(), isEmpty);
  });
}
