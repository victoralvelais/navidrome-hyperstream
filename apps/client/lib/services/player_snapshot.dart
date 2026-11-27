import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Exports only the rendered public artwork/title card, never account metadata.
class PlayerSnapshot {
  static bool get supported =>
      !kIsWeb &&
      [
        TargetPlatform.iOS,
        TargetPlatform.windows,
      ].contains(defaultTargetPlatform);

  /// iOS opens the existing native share sheet. Windows saves a PNG to Downloads.
  /// Returns true only for the Windows save, so cancellation isn't called success.
  static Future<bool> share(Uint8List png, {DateTime Function()? now}) async {
    if (!supported) throw UnsupportedError('Snapshots are unavailable.');
    final timestamp = (now ?? DateTime.now)();
    final name = 'Hyperstream-${timestamp.microsecondsSinceEpoch}.png';
    if (defaultTargetPlatform == TargetPlatform.windows) {
      final downloads = await getDownloadsDirectory();
      if (downloads == null) {
        throw const FileSystemException('Downloads unavailable.');
      }
      await File('${downloads.path}/$name').writeAsBytes(png, flush: true);
      return true;
    }
    final cache = await getTemporaryDirectory();
    final root = await Directory('${cache.path}/hyperstream-share')
        .create(recursive: true);
    // Match the native share channel's sandbox and delayed-reader retention.
    await for (final entry in root.list(followLinks: false)) {
      if (entry is Directory &&
          entry.uri.pathSegments
              .where((s) => s.isNotEmpty)
              .last
              .startsWith('snapshot-') &&
          timestamp.difference((await entry.stat()).modified) >
              const Duration(days: 1)) {
        await entry.delete(recursive: true);
      }
    }
    final directory = await root.createTemp('snapshot-');
    final file = await File('${directory.path}/$name')
        .writeAsBytes(png, flush: true);
    await const MethodChannel('dev.hyperstream/share')
        .invokeMethod<bool>('shareFile', file.path);
    return false;
  }
}
