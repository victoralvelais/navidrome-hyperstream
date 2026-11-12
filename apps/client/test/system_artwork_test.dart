import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hyperstream_client/services/navidrome_client.dart';
import 'package:hyperstream_client/services/system_artwork.dart';

import 'support/preview_artwork.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
