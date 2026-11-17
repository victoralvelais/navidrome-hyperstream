import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyperstream_client/models/library.dart';
import 'package:hyperstream_client/models/source_reference.dart';
import 'package:hyperstream_client/services/music_sources.dart';
import 'package:hyperstream_client/services/navidrome_client.dart';
import 'package:hyperstream_client/services/remote_folder.dart';
import 'package:hyperstream_client/services/remote_transfer.dart';
import 'package:hyperstream_client/services/remote_transfer_background.dart';
import 'package:hyperstream_client/services/source_imports.dart';

import 'remote_folder_test.dart' show MemoryRemoteStore, destination;
import 'remote_send_action_test.dart' show FakeBackground;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MusicSources sources;
  late RemoteFolders remote;
  late NavidromeClient client;
  late List<Track> tracks;
  const success = RemoteTransferResult(success: true, message: 'Sent');
  test(
    'album retains its activity grant and propagates expiration between songs',
    () async {
      final native = FakeBackground(RemoteBackgroundMode.continued);
      final album = AlbumTransferBackground(background: native);
      var expired = false;
      await album.begin(() => expired = true, continued: true);
      await album.finish(success: true);
      expect(native.results, isEmpty);
      native.expire!();
      expect(expired, false);
      await album.begin(() => expired = true, continued: true);
      expect(expired, true);
      expect(native.requests, [true]);
      await album.finishAlbum(success: false);
      expect(native.results, [false]);
    },
  );
  setUp(() async {
    sources = MusicSources()..enabled = true;
    remote = RemoteFolders(
      store: MemoryRemoteStore()
        ..value = RemoteFolderConfig.forDestination(destination()),
    );
    await remote.restore();
    client = NavidromeClient(
      serverUrl: 'https://library.example',
      username: 'user',
      password: 'synthetic',
    );
    tracks = List.generate(
      3,
      (i) => Track(
        id: 'external:$i',
        title: 'Song $i',
        artist: 'Artist',
        album: 'Album',
        duration: const Duration(seconds: 4),
        source: SourceReference(sourceId: sources.sourceId, trackId: '$i'),
      ),
    );
  });
  tearDown(() {
    client.close();
    sources.dispose();
    remote.dispose();
  });
  test(
    'partial album retry retains confirmed progress and opts into activity',
    () async {
      final sent = <String>[];
      final activities = <bool>[];
      var fail = true;
      final imports = SourceImports(
        sources: sources,
        remote: remote,
        transfer: (_, track, _, activity) async {
          sent.add(track.id);
          activities.add(activity);
          if (track == tracks[1] && fail) {
            return const RemoteTransferResult(
              success: false,
              message: 'Expired',
              retryWithActivity: true,
            );
          }
          return success;
        },
      );
      expect((await imports.send(client, tracks)).success, false);
      expect(imports.completed, 1);
      expect(imports.remaining, tracks.skip(1));
      fail = false;
      expect((await imports.retry()).success, true);
      expect(sent, [tracks[0].id, tracks[1].id, tracks[1].id, tracks[2].id]);
      expect(activities, [false, false, true, true]);
      expect(imports.remaining, isEmpty);
      imports.dispose();
    },
  );
  test('uncertain publication stops the batch and disables retry', () async {
    var calls = 0;
    final imports = SourceImports(
      sources: sources,
      remote: remote,
      transfer: (_, _, _, _) async {
        calls++;
        return const RemoteTransferResult(
          success: false,
          message: 'Check destination',
          uncertain: true,
        );
      },
    );
    expect((await imports.send(client, tracks)).uncertain, true);
    expect((await imports.retry()).success, false);
    expect(calls, 1);
    imports.dispose();
  });
  test('concurrent imports cannot replace an active album and account closure stops it', () async {
    final first = Completer<RemoteTransferResult>();
    var calls = 0;
    final imports = SourceImports(
      sources: sources,
      remote: remote,
      transfer: (_, _, _, _) {
        calls++;
        return first.future;
      },
    );
    final running = imports.send(client, tracks);
    expect(imports.active, true);
    expect((await imports.send(client, [tracks.last])).success, false);
    expect(imports.remaining, tracks);
    client.close();
    first.complete(success);
    expect((await running).success, false);
    expect(imports.completed, 1);
    expect(calls, 1);
    imports.dispose();
  });
}
