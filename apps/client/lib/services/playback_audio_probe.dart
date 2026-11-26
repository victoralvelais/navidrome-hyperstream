import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_audio/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_audio/media_information_session.dart';

import '../models/source_reference.dart';

/// Read the actual prepared local audio; never open a provider URL or a remote
/// manifest to discover quality. Failure is optional metadata, not playback failure.
class PlaybackAudioProbe {
  static Future<SourcePlaybackInfo?> read(File file, String sourceId) async {
    final completed = Completer<MediaInformationSession>();
    MediaInformationSession? running;
    var expired = false;
    Future<void> cancel(MediaInformationSession session) async {
      try {
        await session.cancel().timeout(const Duration(seconds: 2));
      } on Object {
        // Metadata is optional; cancellation must not hold the player open.
      }
    }

    try {
      final starting =
          FFprobeKit.getMediaInformationFromCommandArgumentsAsync(
            [
              '-v',
              'error',
              '-hide_banner',
              '-print_format',
              'json',
              '-show_format',
              '-show_streams',
              '-analyzeduration',
              '5000000',
              '-probesize',
              '1048576',
              '-protocol_whitelist',
              'file,pipe',
              '-format_whitelist',
              'flac,mp3,mov,ogg,matroska,webm,wav,aiff,aac,caf',
              '-i',
              file.path,
            ],
            completed.complete,
            (_) {},
          ).then((session) {
            running = session;
            if (expired) unawaited(cancel(session));
            return session;
          });
      await starting.timeout(const Duration(seconds: 10));
      final probe = await completed.future.timeout(const Duration(seconds: 10));
      return parse(
        probe.getMediaInformation()?.getAllProperties(),
        sourceId,
        format: file.path.split('.').last,
      );
    } on TimeoutException {
      expired = true;
      if (running != null) unawaited(cancel(running!));
      return null;
    } on Object {
      return null;
    }
  }

  static SourcePlaybackInfo? parse(
    Map<dynamic, dynamic>? data,
    String sourceId, {
    String? format,
  }) {
    final streams = data?['streams'];
    if (streams is! List) return null;
    final audio = streams
        .whereType<Map>()
        .where((s) => s['codec_type'] == 'audio')
        .toList();
    if (audio.length != 1) return null;
    int? rate(Object? value) {
      final bps = int.tryParse('$value');
      if (bps == null || bps <= 0 || bps > 10000000) return null;
      return (bps / 1000).round().clamp(1, 10000);
    }

    final streamRate = rate(audio.single['bit_rate']);
    final container = data?['format'];
    final hasVideo = streams.whereType<Map>().any(
      (stream) =>
          stream['codec_type'] == 'video' &&
          (stream['disposition'] is! Map ||
              stream['disposition']['attached_pic'] != 1),
    );
    final containerRate = !hasVideo && container is Map
        ? rate(container['bit_rate'])
        : null;
    final codec = audio.single['codec_name'];
    return SourcePlaybackInfo(
      sourceId: sourceId,
      format: format,
      codec: codec is String ? codec : null,
      bitRate: streamRate ?? containerRate,
      bitRateEstimated: streamRate == null && containerRate != null,
    );
  }
}
