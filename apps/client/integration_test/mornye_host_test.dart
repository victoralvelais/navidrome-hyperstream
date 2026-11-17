import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mornye_host/mornye_host.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('packaged native host initializes across Dart isolates', (
    tester,
  ) async {
    final root = await Directory.systemTemp.createTemp(
      'hyperstream-host-integration-',
    );
    await callMornye({
      'op': 'init',
      'root': root.path,
      'key': base64Encode(List.filled(32, 7)),
    });
    final catalog = await callMornye({'op': 'list'}) as List;
    expect(
      catalog.map((e) => e['id']),
      containsAll([
        'spotify-web',
        'tidal-web',
        'qobuz-web',
        'ytmusic-spotiflac',
      ]),
    );
    expect(catalog.every((e) => e['installed'] == false), true);
    await expectLater(
      callMornye({'op': 'enable', 'id': '../escape', 'enabled': true}),
      throwsA(isA<MornyeHostException>()),
    );
    // The process-global Rust environment owns open encrypted-store handles;
    // its synthetic temp directory is left for OS temporary-file cleanup.
  });
}
