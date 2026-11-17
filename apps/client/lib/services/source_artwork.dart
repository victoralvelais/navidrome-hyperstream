import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/source_reference.dart';

class SourceArtwork {
  static final _cache = <Uri, Future<Uint8List>>{};

  static Future<Uint8List> load(Uri uri) {
    final existing = _cache.remove(uri);
    final result = existing ?? _read(uri);
    _cache[uri] = result;
    while (_cache.length > 32) {
      _cache.remove(_cache.keys.first);
    }
    return result;
  }

  static Future<Uint8List> _read(Uri uri) async {
    if (publicArtwork(uri.toString()) == null) throw const FormatException();
    final client = http.Client();
    final abort = Completer<void>();
    final timer = Timer(const Duration(seconds: 15), abort.complete);
    try {
      final request = http.AbortableRequest(
        'GET',
        uri,
        abortTrigger: abort.future,
      )..followRedirects = false;
      final response = await client.send(request);
      if (response.statusCode != 200) throw const FormatException();
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.stream) {
        bytes.add(chunk);
        if (bytes.length > 8 * 1024 * 1024) throw const FormatException();
      }
      if (bytes.length == 0) throw const FormatException();
      return bytes.takeBytes();
    } on Object {
      _cache.remove(uri);
      throw const FormatException('Artwork could not load.');
    } finally {
      timer.cancel();
      client.close();
    }
  }
}
