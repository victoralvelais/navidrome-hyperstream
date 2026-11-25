import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyperstream_client/models/library.dart';
import 'package:hyperstream_client/models/source_reference.dart';
import 'package:hyperstream_client/services/music_sources.dart';
import 'package:hyperstream_client/services/mornye_sources.dart';
import 'package:hyperstream_client/services/mornye_provider.dart';
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

  for (final outcome in [
    'verified',
    'cancelled',
    'account closed',
    'challenge again',
  ]) {
    test(
      'import $outcome resumes only unconfirmed songs and never loops verification',
      () async {
        sources.dispose();
        final extensions = MornyeSources();
        sources = MusicSources(extensions: extensions)..enabled = true;
        final gate = Completer<bool>();
        var prompts = 0, failed = false;
        final sent = <String>[];
        extensions.presentVerification = (_) {
          prompts++;
          return gate.future;
        };
        final imports = SourceImports(
          sources: sources,
          remote: remote,
          transfer: (_, track, _, _) async {
            sent.add(track.id);
            if (track == tracks[1] &&
                (!failed || outcome == 'challenge again')) {
              failed = true;
              return const RemoteTransferResult(
                success: false,
                message: 'Verification needed',
                verificationProviderId: 'tidal-web',
              );
            }
            return success;
          },
        );
        final pending = imports.send(client, tracks);
        await Future<void>.delayed(Duration.zero);
        expect(prompts, 1);
        expect(imports.active, true);
        expect(imports.completed, 1);
        expect(imports.remaining, tracks.skip(1));
        if (outcome == 'account closed') client.close();
        gate.complete(outcome != 'cancelled');
        final result = await pending;
        expect(result.success, outcome == 'verified');
        expect(prompts, 1);
        expect(
          sent,
          outcome == 'verified'
              ? [tracks[0].id, tracks[1].id, tracks[1].id, tracks[2].id]
              : outcome == 'challenge again'
              ? [tracks[0].id, tracks[1].id, tracks[1].id]
              : [tracks[0].id, tracks[1].id],
        );
        imports.dispose();
        extensions.dispose();
      },
    );
  }
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
  test('playlist imports send repeated songs only once', () async {
    final sent = <String>[];
    final imports = SourceImports(
      sources: sources,
      remote: remote,
      transfer: (_, track, _, _) async {
        sent.add(track.id);
        return success;
      },
    );
    expect(
      (await imports.send(client, [tracks[0], tracks[1], tracks[0]])).success,
      true,
    );
    expect(sent, [tracks[0].id, tracks[1].id]);
    expect(imports.completed, 2);
    imports.dispose();
  });
  test(
    'SoundCloud folder imports use the upload provider and clean staging',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'soundcloud-import-test-',
      );
      await Directory('${root.path}/downloads').create();
      final extensions = _SoundCloudImports(root);
      sources.dispose();
      sources = MusicSources(extensions: extensions);
      final uploads = [
        for (final id in ['123', '456', '123'])
          MornyeProvider.parseTrack('soundcloud', {
            'id': id,
            'name': 'Remix $id',
            'artists': 'Uploader',
            'duration_ms': 120000,
            'is_playable': true,
          }),
      ];
      final imports = SourceImports(
        sources: sources,
        remote: remote,
        transfer: (_, track, provider, activity) async {
          expect(provider.id, 'mornye:soundcloud');
          expect(activity, false);
          final audio = await provider.download(
            track.source!,
            Completer<void>().future,
          );
          expect(audio.headers['content-type'], 'audio/mp4');
          expect(await audio.stream.toBytes(), [1, 2, 3]);
          return success;
        },
      );
      try {
        final result = await imports.send(client, uploads);
        expect(result.success, true);
        expect(imports.completed, 2);
        expect(extensions.downloads, ['123', '456']);
        expect(await Directory('${root.path}/downloads').list().isEmpty, true);
        expect(extensions.verification.value, isNull);
        final blocked = MornyeProvider.parseTrack('soundcloud', {
          'id': '789',
          'name': 'Preview',
          'is_playable': false,
        });
        expect((await imports.send(client, [blocked])).success, false);
        expect(extensions.downloads, ['123', '456']);
      } finally {
        imports.dispose();
        sources.dispose();
        sources = MusicSources();
        extensions.dispose();
        await root.delete(recursive: true);
      }
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

class _SoundCloudImports extends MornyeSources {
  _SoundCloudImports(Directory directory) {
    root = directory;
    extensions = [
      MornyeExtension({
        'id': 'soundcloud',
        'display_name': 'SoundCloud',
        'version': '1.0.15',
        'download_url': 'https://example.test/package',
        'sha256': 'synthetic',
        'audio': true,
        'installed': true,
        'enabled': true,
      }),
    ];
  }
  final downloads = <String>[];
  @override
  Future<dynamic> execute(
    Map<String, dynamic> request, {
    Future<void>? abort,
  }) async {
    expect(request['op'], 'download');
    expect(request['id'], 'soundcloud');
    expect(request['method'], 'hyperstreamDownload');
    expect(request['args'][1], 'aac_160');
    downloads.add(request['args'][0] as String);
    final path = request['args'][2] as String;
    await File(path).writeAsBytes([1, 2, 3]);
    return {'success': true, 'file_path': path};
  }
}
