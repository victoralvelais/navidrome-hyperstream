import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyperstream_client/services/mp3_converter.dart';
import 'package:hyperstream_client/services/music_provider.dart';

import 'external_playback_test.dart' show externalSong;

void main() {
  test(
    'conversion uses separate local arguments and the selected MP3 profile',
    () {
      final args = Mp3Converter.arguments(
        File('input with spaces.flac'),
        File('output.mp3.part'),
        externalSong,
      );
      expect(
        args,
        containsAllInOrder([
          '-i',
          'input with spaces.flac',
          '-c:a',
          'libmp3lame',
          '-b:a',
          '320k',
        ]),
      );
      expect(args, contains('title=Song'));
      expect(args, contains('artist=Artist'));
      expect(args, contains('album=Album'));
      expect(args, containsAllInOrder(['-f', 'mp3', 'output.mp3.part']));
      expect(args, containsAllInOrder(['-protocol_whitelist', 'file,pipe']));
    },
  );

  test('validation rejects wrong codec, bitrate, and truncated duration', () {
    Map<String, dynamic> probe({
      String codec = 'mp3',
      String rate = '320000',
      String duration = '180.12',
    }) => {
      'streams': [
        {'codec_type': 'audio', 'codec_name': codec, 'bit_rate': rate},
      ],
      'format': {'duration': duration},
    };
    Mp3Converter.validate(probe(), externalSong);
    for (final invalid in [
      probe(codec: 'aac'),
      probe(rate: '128000'),
      probe(duration: '30'),
      probe(duration: 'NaN'),
    ]) {
      expect(
        () => Mp3Converter.validate(invalid, externalSong),
        throwsA(isA<SourceException>()),
      );
    }
  });
}
