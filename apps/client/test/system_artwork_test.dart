import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hyperstream_client/services/navidrome_client.dart';
import 'package:hyperstream_client/services/system_artwork.dart';

import 'support/preview_artwork.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'iOS artwork publishes a local file while paused without Flutter decoding',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final binding = TestWidgetsFlutterBinding.instance;
      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      const channel = MethodChannel('dev.hyperstream/system_artwork');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      addTearDown(() {
        messenger.setMockMethodCallHandler(channel, null);
        binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        debugDefaultTargetPlatformOverride = null;
      });
      final root = await Directory.systemTemp.createTemp(
        'hyperstream-native-art-',
      );
      addTearDown(() async {
        expect(
          root.absolute.path.startsWith(Directory.systemTemp.absolute.path),
          isTrue,
        );
        await root.delete(recursive: true);
      });
      final input = Uint8List.fromList([1, 2, 3]);
      final output = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j5ioAAAAASUVORK5CYII=',
      );
      var conversions = 0;
      var valid = true;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'decodePNG');
        expect(call.arguments, input);
        expect(binding.lifecycleState, AppLifecycleState.paused);
        conversions++;
        return valid ? output : null;
      });
      final client = NavidromeClient(
        serverUrl: 'https://music.example.com',
        username: 'test',
        password: 'secret',
        httpClient: MockClient((_) async => http.Response.bytes(input, 200)),
      );
      addTearDown(client.close);
      final cache = SystemArtwork(directory: () async => root);
      final simultaneous = await Future.wait([
        cache.load(client, 'cover'),
        cache.load(client, 'cover'),
      ]);
      expect(simultaneous[0], simultaneous[1]);
      expect(simultaneous.first?.scheme, 'file');
      expect(await File.fromUri(simultaneous.first!).readAsBytes(), output);
      expect(await cache.load(client, 'cover'), simultaneous.first);
      expect(conversions, 1);
      valid = false;
      expect(await cache.load(client, 'invalid'), isNull);
      final files = await Directory('${root.path}/hyperstream-system-artwork')
          .list()
          .toList();
      expect(files, hasLength(1));
      expect(files.single.path.endsWith('.png'), isTrue);
    },
  );
  test(
    'system artwork is decoded into a local PNG and isolated by server account',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'hyperstream-art-test-',
      );
      addTearDown(() async {
        expect(
          root.absolute.path.startsWith(Directory.systemTemp.absolute.path),
          isTrue,
        );
        await root.delete(recursive: true);
      });
      final bytes = await previewArtwork(0);
      var requests = 0;
      var valid = true;
      NavidromeClient client(String user) {
        final client = NavidromeClient(
          serverUrl: 'https://music.example.com',
          username: user,
          password: 'secret',
          httpClient: MockClient((_) async {
            requests++;
            return valid
                ? http.Response.bytes(bytes, 200)
                : http.Response('not an image', 200);
          }),
        );
        addTearDown(client.close);
        return client;
      }

      final cache = SystemArtwork(directory: () async => root);
      final firstClient = client('first');
      final first = await cache.load(firstClient, 'cover');
      expect(first?.scheme, 'file');
      expect(first.toString(), isNot(contains('secret')));
      expect(await File.fromUri(first!).exists(), isTrue);
      expect(await cache.load(firstClient, 'cover'), first);
      expect(requests, 1);
      final second = await cache.load(client('second'), 'cover');
      expect(second, isNot(first));
      valid = false;
      expect(await cache.load(firstClient, 'invalid'), isNull);
    },
  );
}
