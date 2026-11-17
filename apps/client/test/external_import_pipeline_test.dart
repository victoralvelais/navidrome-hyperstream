import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:hyperstream_client/services/audio_file_share.dart';
import 'package:hyperstream_client/services/music_provider.dart';
import 'package:hyperstream_client/services/navidrome_client.dart';
import 'package:hyperstream_client/services/remote_folder.dart';
import 'package:hyperstream_client/services/remote_transfer.dart';
import 'package:hyperstream_client/services/remote_transfer_background.dart';

import 'external_playback_test.dart' show externalSong;
import 'remote_folder_test.dart'
    show MemoryRemoteFs, MemoryRemoteStore, destination;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final valid in [true, false]) {
    test(
      'external processing publishes only validated output ($valid)',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'hyperstream-import-test-',
        );
        final fs = MemoryRemoteFs();
        final remote = RemoteFolders(
          store: MemoryRemoteStore()
            ..value = RemoteFolderConfig.forDestination(destination()),
          connect: (_) async => fs,
        );
        await remote.restore();
        final client = NavidromeClient(
          serverUrl: 'https://library.example',
          username: 'user',
          password: 'synthetic',
        );
        final events = <String>[];
        final export = AudioFileShare(
          client: client,
          track: externalSong,
          temporaryDirectory: () async => root,
          download: (_) async {
            events.add('download');
            return http.StreamedResponse(
              Stream.value([102, 76, 97, 67]),
              200,
              contentLength: 4,
            );
          },
          processFile: (file) async {
            events.add('convert');
            expect(await file.readAsBytes(), [102, 76, 97, 67]);
            if (!valid) throw const SourceException('Validation failed');
            return File('${file.parent.path}/Converted.mp3')
                .writeAsBytes([73, 68, 51]);
          },
        );
        try {
          final result = await RemoteTransfer(
            remote: remote,
            client: client,
            track: externalSong,
            export: export,
            background: RemoteTransferBackground(isIOS: false),
          ).run();
          expect(events, ['download', 'convert']);
          expect(result.success, valid);
          expect(fs.renames.length, valid ? 1 : 0);
          expect(
            fs.files.values.toList(),
            valid
                ? [
                    [73, 68, 51],
                  ]
                : isEmpty,
          );
          expect(
            await root
                .list(recursive: true)
                .where((entry) => entry is File)
                .toList(),
            isEmpty,
          );
          expect(remote.busy, false);
        } finally {
          client.close();
          remote.dispose();
          await root.delete(recursive: true);
        }
      },
    );
  }
}
