import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import 'navidrome_client.dart';

/// Media controls receive a private local file, never an authenticated URL.
class SystemArtwork {
  SystemArtwork({Future<Directory> Function()? directory})
    : _directory = directory ?? getTemporaryDirectory;
  final Future<Directory> Function() _directory;
  final Map<String, Future<Uri?>> _pending = {};

  Future<Uri?> load(NavidromeClient client, String id) {
    final key = sha256
        .convert(
          utf8.encode(
            jsonEncode([client.baseUri.toString(), client.username, id]),
          ),
        )
        .toString();
    return _pending.putIfAbsent(
      key,
      () => _load(client, id, key).whenComplete(() {
        _pending.remove(key);
      }),
    );
  }

  Future<Uri?> _load(NavidromeClient client, String id, String key) async {
    try {
      final root = await _directory();
      final cache = Directory('${root.path}/hyperstream-system-artwork');
      await cache.create(recursive: true);
      final file = File('${cache.path}/$key.png');
      if (await file.exists()) return file.uri;
      final bytes = await client.coverArt(id);
      if (bytes.isEmpty || bytes.length > 8 * 1024 * 1024) return null;
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 512);
      try {
        final frame = await codec.getNextFrame();
        try {
          final png = await frame.image.toByteData(
            format: ui.ImageByteFormat.png,
          );
          if (png == null) return null;
          await file.writeAsBytes(png.buffer.asUint8List(), flush: true);
        } finally {
          frame.image.dispose();
        }
      } finally {
        codec.dispose();
      }
      // A small artwork cache, separate from downloads or library files.
      final entries = await cache
          .list()
          .where((e) => e is File)
          .cast<File>()
          .toList();
      if (entries.length > 48) {
        final dated = await Future.wait(
          entries.map((f) async => (f, await f.lastModified())),
        );
        dated.sort((a, b) => a.$2.compareTo(b.$2));
        for (final entry in dated.take(entries.length - 48)) {
          if (entry.$1.path != file.path) await entry.$1.delete();
        }
      }
      return file.uri;
    } on Object {
      // Missing art must never interrupt audio or expose request details.
      return null;
    }
  }
}
