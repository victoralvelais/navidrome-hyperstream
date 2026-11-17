import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

@Native<Pointer<Utf8> Function(Pointer<Utf8>)>(
  symbol: 'hyperstream_mornye_call',
  assetId: 'package:mornye_host/mornye_host',
)
external Pointer<Utf8> _call(Pointer<Utf8> request);

@Native<Void Function(Pointer<Utf8>)>(
  symbol: 'hyperstream_mornye_free',
  assetId: 'package:mornye_host/mornye_host',
)
external void _free(Pointer<Utf8> response);

class MornyeHostException implements Exception {
  const MornyeHostException(this.detail);
  final String detail;
  // Native errors may contain URLs. Never log or surface their raw contents.
  @override
  String toString() => 'The music provider could not complete this request.';
}

/// Blocking Rust/QuickJS/network work always stays off Flutter's UI isolate.
Future<dynamic> callMornye(Map<String, dynamic> request) {
  final raw = jsonEncode(request);
  return Isolate.run(() {
    final input = raw.toNativeUtf8();
    Pointer<Utf8>? output;
    try {
      output = _call(input);
      final response =
          jsonDecode(output.toDartString()) as Map<String, dynamic>;
      if (response['ok'] != true) {
        throw MornyeHostException(response['error'] as String);
      }
      return response['value'];
    } finally {
      calloc.free(input);
      if (output != null) _free(output);
    }
  });
}
