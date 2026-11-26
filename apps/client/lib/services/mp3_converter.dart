import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new_audio/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_audio/return_code.dart';

import '../models/library.dart';
import 'audio_file_share.dart';
import 'audio_import_format.dart';
import 'music_provider.dart';
import 'source_artwork.dart';

class Mp3Converter {
  static const _inputFormats =
      'flac,mp3,mov,ogg,matroska,webm,wav,aiff,aac,wv,ape,tta,tak,shn';
  int? _session;
  bool _cancelled = false;

  void cancel() {
    _cancelled = true;
    final session = _session;
    if (session != null) {
      unawaited(FFmpegKit.cancel(session).catchError((Object _) {}));
    }
  }

  void _check() {
    if (_cancelled) throw const AudioShareCancelled();
  }

  static List<String> arguments(
    File input,
    File output,
    Track track, {
    File? artwork,
    AudioImportFormat? preserve,
    bool includeEmbeddedArtwork = true,
  }) => [
    '-hide_banner',
    '-loglevel',
    'error',
    '-nostdin',
    '-n',
    '-protocol_whitelist',
    'file,pipe',
    '-format_whitelist',
    _inputFormats,
    '-i',
    input.path,
    if (artwork != null) ...[
      '-protocol_whitelist',
      'file,pipe',
      '-format_whitelist',
      'image2,jpeg_pipe,png_pipe,webp_pipe',
      '-i',
      artwork.path,
    ],
    '-map',
    '0:a:0',
    if (artwork != null) ...[
      '-map',
      '1:v:0',
      '-c:v',
      'mjpeg',
      '-disposition:v:0',
      'attached_pic',
      '-metadata:s:v',
      'title=Album cover',
    ] else if (includeEmbeddedArtwork) ...[
      '-map',
      '0:v:0?',
      '-c:v',
      'copy',
      '-disposition:v:0',
      'attached_pic',
    ] else ...[
      '-vn',
    ],
    '-map_metadata',
    '0',
    '-c:a',
    preserve == null ? 'libmp3lame' : 'copy',
    if (preserve == null) ...['-b:a', '320k', '-ar', '44100', '-ac', '2'],
    if (preserve == null || preserve.muxer == 'mp3') ...['-id3v2_version', '3'],
    if (preserve?.muxer == 'ipod') ...['-movflags', '+faststart'],
    '-metadata',
    'title=${track.title}',
    '-metadata',
    'artist=${track.artist}',
    if (track.album.isNotEmpty) ...['-metadata', 'album=${track.album}'],
    if (track.number != null) ...['-metadata', 'track=${track.number}'],
    if (track.source != null) ...['-metadata', 'disc=${track.source!.disc}'],
    if (track.source?.isrc != null) ...[
      '-metadata',
      'TSRC=${track.source!.isrc}',
    ],
    '-f',
    preserve?.muxer ?? 'mp3',
    output.path,
  ];

  /// Lossy sources retain their audio packets; only lossless sources use LAME.
  Future<File> prepare(File input, Track track) async {
    _check();
    final probe = await FFprobeKit.getMediaInformationFromCommandArguments([
      '-v',
      'error',
      '-hide_banner',
      '-print_format',
      'json',
      '-show_format',
      '-show_streams',
      '-protocol_whitelist',
      'file,pipe',
      '-format_whitelist',
      _inputFormats,
      '-i',
      input.path,
    ]);
    _check();
    final format = AudioImportFormat.read(
      probe.getMediaInformation()?.getAllProperties(),
      track,
    );
    return convert(input, track, preserve: format.lossless ? null : format);
  }

  Future<bool> _encode(List<String> args) async {
    _check();
    final completed = Completer<FFmpegSession>();
    final session = await FFmpegKit.executeWithArgumentsAsync(
      args,
      completed.complete,
      (_) {},
    );
    _session = session.getSessionId();
    if (_cancelled) cancel();
    final finished = await completed.future;
    _session = null;
    _check();
    return ReturnCode.isSuccess(await finished.getReturnCode());
  }

  Future<File> convert(
    File input,
    Track track, {
    AudioImportFormat? preserve,
  }) async {
    _check();
    final basename = input.uri.pathSegments.last;
    final dot = basename.lastIndexOf('.');
    final stem = dot > 0 ? basename.substring(0, dot) : basename;
    try {
      final directory = await Directory('${input.parent.path}/converted')
          .create();
      final extension = preserve?.extension ?? 'mp3';
      final output = File('${directory.path}/$stem.$extension.part');
      final allowArtwork = preserve?.supportsArtwork ?? true;
      File? artwork;
      final uri = track.source?.artwork;
      if (uri != null && allowArtwork) {
        try {
          final bytes = await SourceArtwork.load(uri);
          artwork = await File('${input.parent.path}/cover')
              .writeAsBytes(bytes);
        } on Object {
          // Embedded source artwork remains available when its cover URL fails.
        }
      }
      _check();
      var success = await _encode(
        arguments(
          input,
          output,
          track,
          artwork: artwork,
          preserve: preserve,
          includeEmbeddedArtwork: allowArtwork,
        ),
      );
      if (!success && allowArtwork) {
        // Artwork is optional. An HTML error page, broken embedded picture or
        // unsupported image must not prevent saving otherwise valid audio.
        if (await output.exists()) await output.delete();
        success = await _encode(
          arguments(
            input,
            output,
            track,
            preserve: preserve,
            includeEmbeddedArtwork: false,
          ),
        );
      }
      if (!success) {
        throw SourceException(
          preserve == null
              ? 'Could not convert this recording to MP3 320, even without artwork.'
              : 'Could not prepare this recording without changing its audio. Try another source.',
        );
      }
      final probe = await FFprobeKit.getMediaInformation(output.path);
      final data = probe.getMediaInformation()?.getAllProperties();
      if (preserve == null) {
        validate(data, track);
      } else {
        preserve.validateCopy(data, track);
      }
      _check();
      return await output.rename('${directory.path}/$stem.$extension');
    } on AudioShareCancelled {
      rethrow;
    } on SourceException {
      rethrow;
    } on Object {
      _check();
      throw const SourceException(
        'Audio conversion failed. Check free storage and try again.',
      );
    } finally {
      _session = null;
    }
  }

  static void validate(Map<dynamic, dynamic>? data, Track track) {
    final streams = data?['streams'] as List? ?? [];
    final audio = streams
        .cast<Map>()
        .where((s) => s['codec_type'] == 'audio')
        .toList();
    final format = data?['format'] as Map?;
    final seconds = double.tryParse(format?['duration']?.toString() ?? '');
    final bitrate = audio.length == 1
        ? int.tryParse(audio.single['bit_rate']?.toString() ?? '')
        : null;
    if (audio.length != 1 ||
        audio.single['codec_name'] != 'mp3' ||
        bitrate != 320000 ||
        seconds == null ||
        !seconds.isFinite ||
        seconds <= 0 ||
        (track.duration > Duration.zero &&
            (seconds - track.duration.inMilliseconds / 1000).abs() > 3)) {
      throw const SourceException(
        'The converted file did not pass audio validation. It was not sent.',
      );
    }
  }
}
