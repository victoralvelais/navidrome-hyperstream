import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new_audio/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_audio/return_code.dart';

import '../models/library.dart';
import 'audio_file_share.dart';
import 'music_provider.dart';
import 'source_artwork.dart';

class Mp3Converter {
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
  }) => [
    '-hide_banner',
    '-loglevel',
    'error',
    '-nostdin',
    '-n',
    '-protocol_whitelist',
    'file,pipe',
    '-format_whitelist',
    'flac,mp3,mov,ogg,wav,aiff,aac',
    '-i',
    input.path,
    if (artwork != null) ...['-i', artwork.path],
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
    ] else ...[
      '-map',
      '0:v:0?',
      '-c:v',
      'copy',
      '-disposition:v:0',
      'attached_pic',
    ],
    '-map_metadata',
    '0',
    '-c:a',
    'libmp3lame',
    '-b:a',
    '320k',
    '-ar',
    '44100',
    '-ac',
    '2',
    '-id3v2_version',
    '3',
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
    'mp3',
    output.path,
  ];

  Future<File> convert(File input, Track track) async {
    _check();
    final basename = input.uri.pathSegments.last;
    final dot = basename.lastIndexOf('.');
    final stem = dot > 0 ? basename.substring(0, dot) : basename;
    try {
      final directory = await Directory('${input.parent.path}/converted')
          .create();
      final output = File('${directory.path}/$stem.mp3.part');
      File? artwork;
      final uri = track.source?.artwork;
      if (uri != null) {
        try {
          final bytes = await SourceArtwork.load(uri);
          artwork = await File('${input.parent.path}/cover')
              .writeAsBytes(bytes);
        } on Object {
          // Embedded source artwork remains available when its cover URL fails.
        }
      }
      _check();
      final completed = Completer<FFmpegSession>();
      final session = await FFmpegKit.executeWithArgumentsAsync(
        arguments(input, output, track, artwork: artwork),
        completed.complete,
        (_) {},
      );
      _session = session.getSessionId();
      if (_cancelled) cancel();
      final finished = await completed.future;
      _session = null;
      _check();
      if (!ReturnCode.isSuccess(await finished.getReturnCode())) {
        throw const SourceException(
          'Could not convert this recording to MP3 320.',
        );
      }
      final probe = await FFprobeKit.getMediaInformation(output.path);
      final data = probe.getMediaInformation()?.getAllProperties();
      validate(data, track);
      _check();
      return await output.rename('${directory.path}/$stem.mp3');
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
