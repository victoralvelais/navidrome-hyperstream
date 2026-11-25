import 'dart:convert';
import 'dart:io';

import 'package:mornye_host/mornye_host.dart';

Future<void> main() async {
  final root = await Directory.systemTemp.createTemp(
    'hyperstream-native-check-',
  );
  await callMornye({
    'op': 'init',
    'root': root.path,
    'key': base64Encode(List<int>.filled(32, 9)),
  });
  final catalog = await callMornye({'op': 'list'}) as List;
  if (catalog.length != 5 || catalog.any((e) => e['installed'] != false)) {
    throw StateError('Unexpected native provider catalog');
  }
  try {
    await callMornye({'op': 'enable', 'id': '../escape', 'enabled': true});
    throw StateError('Host accepted an invalid provider');
  } on MornyeHostException {
    // Expected: also checks error serialization across isolate boundaries.
  }
  stdout.writeln(
    'Native extension host: ${catalog.length} providers, FFI and isolation checks passed.',
  );
}
