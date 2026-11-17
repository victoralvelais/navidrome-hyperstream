import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new_audio/return_code.dart';

import 'music_provider.dart';

/// Ogg/Opus is not consistently playable by both native audio backends. Keep
/// imports in their original format and convert only the temporary playback copy.
class SourceAudioPreparation {
  static Future<File> prepare(File input, Future<void> abort) async {
    final extension = input.path.toLowerCase().split('.').last;
    if (!['opus', 'ogg', 'webm'].contains(extension)) return input;
    final output = File('${input.parent.path}/playback.m4a');
    var cancelled = false;
    var finished = false;
    int? sessionId;
    final completed = Completer<FFmpegSession>();
    unawaited(
      abort
          .then((_) async {
            if (finished) return;
            cancelled = true;
            if (sessionId != null) await FFmpegKit.cancel(sessionId);
          })
          .catchError((Object _) {}),
    );
    try {
      final session = await FFmpegKit.executeWithArgumentsAsync(
        [
          '-hide_banner',
          '-loglevel',
          'error',
          '-nostdin',
          '-n',
          '-protocol_whitelist',
          'file,pipe',
          '-format_whitelist',
          'ogg,matroska,webm',
          '-i',
          input.path,
          '-map',
          '0:a:0',
          '-vn',
          '-c:a',
          'aac',
          '-b:a',
          '256k',
          '-movflags',
          '+faststart',
          output.path,
        ],
        completed.complete,
        (_) {},
      );
      sessionId = session.getSessionId();
      if (cancelled) await FFmpegKit.cancel(sessionId);
      final result = await completed.future.timeout(const Duration(minutes: 5));
      if (cancelled ||
          !ReturnCode.isSuccess(await result.getReturnCode()) ||
          !await output.exists() ||
          await output.length() == 0) {
        throw const SourceException(
          'This audio could not be prepared for playback.',
        );
      }
      return output;
    } on TimeoutException {
      // Wait for FFmpeg to release the staging files before the caller cleans up.
      if (sessionId != null) {
        await FFmpegKit.cancel(sessionId);
        await completed.future;
      }
      throw const SourceException('Audio preparation timed out. Try again.');
    } finally {
      finished = true;
    }
  }
}
