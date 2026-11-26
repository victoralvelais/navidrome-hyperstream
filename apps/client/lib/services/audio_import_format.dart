import '../models/library.dart';
import 'music_provider.dart';

/// The downloaded audio codec, not the filename or requested provider quality,
/// decides whether import needs a lossy encode. M4A can contain AAC or ALAC.
class AudioImportFormat {
  const AudioImportFormat({
    required this.codec,
    required this.lossless,
    required this.extension,
    required this.muxer,
    required this.sampleRate,
    required this.channels,
    required this.durationSeconds,
    this.bitRate,
  });
  final String codec, extension, muxer;
  final bool lossless;
  final int sampleRate, channels;
  final double durationSeconds;
  final int? bitRate;
  bool get supportsArtwork => muxer == 'mp3' || muxer == 'ipod';

  static AudioImportFormat read(Map<dynamic, dynamic>? data, Track track) {
    final audio = _audio(data, track);
    final codec = audio['codec_name'] as String? ?? '';
    final lossless =
        codec.startsWith('pcm_') ||
        const {
          'flac',
          'alac',
          'wavpack',
          'ape',
          'tta',
          'tak',
          'shorten',
        }.contains(codec);
    final (extension, muxer) = switch (codec) {
      'aac' => ('m4a', 'ipod'),
      'mp3' => ('mp3', 'mp3'),
      'opus' => ('opus', 'opus'),
      'vorbis' => ('ogg', 'ogg'),
      _ when lossless => ('mp3', 'mp3'),
      _ => throw const SourceException(
        'This audio format cannot be saved yet. Try another source.',
      ),
    };
    final sampleRate = int.tryParse('${audio['sample_rate']}');
    final channels = int.tryParse('${audio['channels']}');
    if (sampleRate == null ||
        sampleRate <= 0 ||
        channels == null ||
        channels <= 0) {
      throw const SourceException(
        'The downloaded audio could not be validated. It was not sent.',
      );
    }
    return AudioImportFormat(
      codec: codec,
      lossless: lossless,
      extension: extension,
      muxer: muxer,
      sampleRate: sampleRate,
      channels: channels,
      durationSeconds: double.parse('${(data!['format'] as Map)['duration']}'),
      bitRate: int.tryParse('${audio['bit_rate']}'),
    );
  }

  void validateCopy(Map<dynamic, dynamic>? data, Track track) {
    final audio = _audio(data, track);
    final duration = double.parse('${(data!['format'] as Map)['duration']}');
    if (audio['codec_name'] != codec ||
        (duration - durationSeconds).abs() > 1 ||
        int.tryParse('${audio['sample_rate']}') != sampleRate ||
        int.tryParse('${audio['channels']}') != channels) {
      throw const SourceException(
        'The prepared file did not preserve its source audio. It was not sent.',
      );
    }
  }

  static Map _audio(Map<dynamic, dynamic>? data, Track track) {
    final streams = data?['streams'] as List? ?? [];
    final audio = streams
        .whereType<Map>()
        .where((stream) => stream['codec_type'] == 'audio')
        .toList();
    final format = data?['format'] as Map?;
    final duration = double.tryParse('${format?['duration']}');
    if (audio.length != 1 ||
        duration == null ||
        !duration.isFinite ||
        duration <= 0 ||
        (track.duration > Duration.zero &&
            (duration - track.duration.inMilliseconds / 1000).abs() > 3)) {
      throw const SourceException(
        'The downloaded audio is incomplete or unreadable. It was not sent.',
      );
    }
    return audio.single;
  }
}
