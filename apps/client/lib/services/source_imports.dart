import 'package:flutter/foundation.dart';

import '../models/library.dart';
import 'audio_file_share.dart';
import 'mp3_converter.dart';
import 'music_provider.dart';
import 'music_sources.dart';
import 'navidrome_client.dart';
import 'remote_folder.dart';
import 'remote_transfer.dart';
import 'remote_transfer_background.dart';

/// Serial album delivery retains confirmed progress for an explicit retry.
/// A failed or uncertain publication stops the batch before the next recording.
class SourceImports extends ChangeNotifier {
  SourceImports({MusicSources? sources, RemoteFolders? remote, this.transfer})
    : sources = sources ?? MusicSources.instance,
      remote = remote ?? RemoteFolders.instance;
  static final instance = SourceImports();
  final MusicSources sources;
  final RemoteFolders remote;
  final Future<RemoteTransferResult> Function(
    NavidromeClient,
    Track,
    MusicProvider,
    bool,
  )?
  transfer;
  bool active = false;
  List<Track> remaining = const [];
  int completed = 0;
  RemoteTransferResult? issue;
  NavidromeClient? _client;

  Future<RemoteTransferResult> send(
    NavidromeClient client,
    List<Track> tracks,
  ) async {
    if (active) {
      return const RemoteTransferResult(
        success: false,
        message: 'An import is already running. Try again when it finishes.',
      );
    }
    if (tracks.isEmpty || tracks.any((track) => track.source == null)) {
      return const RemoteTransferResult(
        success: false,
        message: 'Choose songs from an external source.',
      );
    }
    if (tracks.any((track) => !track.source!.available)) {
      return const RemoteTransferResult(
        success: false,
        message: 'Some songs are unavailable from this source. Select the available songs individually.',
      );
    }
    if (tracks.any(
      (track) => track.source!.sourceId != tracks.first.source!.sourceId,
    )) {
      return const RemoteTransferResult(
        success: false,
        message: 'Import songs from one source at a time.',
      );
    }
    if (remote.destination == null) {
      return const RemoteTransferResult(
        success: false,
        message:
            'Choose a destination in Home > Remote folder before importing.',
      );
    }
    // Playback retains repeats; importing a playlist needs one file per song.
    remaining = List.unmodifiable(
      {for (final track in tracks) track.id: track}.values,
    );
    completed = 0;
    _client = client;
    return _run();
  }

  Future<RemoteTransferResult> retry() {
    if (active ||
        remaining.isEmpty ||
        issue?.uncertain == true ||
        _client?.isClosed != false) {
      return Future.value(
        const RemoteTransferResult(
          success: false,
          message:
              'Check the destination and choose the remaining songs again.',
        ),
      );
    }
    return _run(useActivity: issue?.retryWithActivity ?? false);
  }

  Future<RemoteTransferResult> _run({bool useActivity = false}) async {
    active = true;
    issue = null;
    notifyListeners();
    MusicProvider? provider;
    var background = AlbumTransferBackground();
    final verificationRetried = <String>{};
    var notified = false;
    final destination = remote.destination;
    final connection = remote.connection;
    try {
      if (destination == null) {
        throw const SourceException(
          'Choose a remote destination before retrying.',
        );
      }
      provider = sources.provider(remaining.first.source);
      while (remaining.isNotEmpty) {
        if (_client!.isClosed) {
          throw const SourceException(
            'Your library connection changed. Select the remaining songs again.',
          );
        }
        if (!identical(remote.connection, connection) ||
            remote.destination?.address != destination.address) {
          throw const SourceException(
            'The destination changed. Retry to send the remaining songs to the selected folder.',
          );
        }
        final track = remaining.first;
        final result = transfer != null
            ? await transfer!(_client!, track, provider, useActivity)
            : await _sendTrack(
                _client!,
                track,
                provider,
                useActivity,
                background,
              );
        if (!result.success) {
          if (result.verificationProviderId case final String providerId) {
            if (!result.uncertain &&
                verificationRetried.add(track.id) &&
                sources.extensions != null) {
              // The failed download has been cleaned up before any SMB publish.
              // Release its execution grant while the user is in the browser.
              await background.finishAlbum(success: false);
              background = AlbumTransferBackground();
              final verified = await sources.extensions!.requestVerification(
                providerId,
              );
              if (verified) continue;
            }
          }
          issue = RemoteTransferResult(
            success: false,
            message:
                '$completed sent. ${remaining.length} remaining. ${result.verificationProviderId != null ? 'Verification was not completed. Tap Retry to continue.' : result.message}',
            retryWithActivity: result.retryWithActivity,
            uncertain: result.uncertain,
            notified: result.notified,
          );
          return issue!;
        }
        completed++;
        notified = result.notified;
        remaining = List.unmodifiable(remaining.skip(1));
        notifyListeners();
      }
      return RemoteTransferResult(
        success: true,
        message:
            'Sent $completed ${completed == 1 ? 'song' : 'songs'} to your remote folder as MP3 320.',
        notified: notified,
      );
    } on Object catch (error) {
      final notified = await background.notifyResult(success: false);
      issue = RemoteTransferResult(
        success: false,
        notified: notified,
        message: error is SourceException ? error.message : 'The import could not finish. Check your source and remote folder, then retry.',
      );
      return issue!;
    } finally {
      await background.finishAlbum(success: remaining.isEmpty && issue == null);
      provider?.close();
      active = false;
      notifyListeners();
    }
  }

  Future<RemoteTransferResult> _sendTrack(
    NavidromeClient client,
    Track track,
    MusicProvider source,
    bool useActivity,
    RemoteTransferBackground background,
  ) async {
    var metadata = track;
    final converter = Mp3Converter();
    return RemoteTransfer(
      remote: remote,
      client: client,
      track: track,
      background: background,
      notifySuccess: remaining.length == 1,
      useActivity: useActivity,
      export: AudioFileShare(
        client: client,
        track: track,
        prepareDirectory: background.prepareDirectory,
        download: (abort) async {
          if (track.album.isEmpty && track.source!.albumId != null) {
            final album = await source.album(
              SourceAlbum(
                id: track.source!.albumId!,
                sourceId: source.id,
                title: '',
                artist: track.artist,
              ),
            );
            metadata = album.firstWhere(
              (item) => item.id == track.id,
              orElse: () => throw const SourceException(
                'This recording is missing from its source album.',
              ),
            );
          }
          return source.download(track.source!, abort);
        },
        processFile: (file) {
          background.update(
            completed: 0,
            total: -1,
            stage: 'Converting to MP3',
          );
          return converter.convert(file, metadata);
        },
        cancelProcessing: converter.cancel,
      ),
    ).run();
  }
}
