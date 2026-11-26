import 'package:flutter_test/flutter_test.dart';
import 'package:hyperstream_client/models/source_reference.dart';
import 'package:hyperstream_client/services/playback_audio_probe.dart';

void main() {
  const sourceId = 'mornye:ytmusic-spotiflac';

  test('uses the actual audio stream bitrate before the container rate', () {
    final info = PlaybackAudioProbe.parse(
      {
        'streams': [
          {'codec_type': 'video', 'bit_rate': '2200000'},
          {'codec_type': 'audio', 'codec_name': 'aac', 'bit_rate': '128490'},
        ],
        'format': {'bit_rate': '2330000'},
      },
      sourceId,
      format: 'm4a',
    )!;

    expect(info.sourceId, sourceId);
    expect(info.format, 'm4a');
    expect(info.codec, 'aac');
    expect(info.bitRate, 128);
    expect(info.bitRateEstimated, isFalse);
    expect(info.label, 'YouTube · M4A · AAC · 128 kbps');
  });

  test('marks a container bitrate as an estimate', () {
    final info = PlaybackAudioProbe.parse({
      'streams': [
        {'codec_type': 'audio', 'codec_name': 'flac'},
      ],
      'format': {'bit_rate': 948510},
    }, sourceId)!;

    expect(info.bitRate, 949);
    expect(info.bitRateEstimated, isTrue);
    expect(info.label, 'YouTube · ≈949 kbps');
  });

  test('a container bitrate may include cover art but excludes video', () {
    SourcePlaybackInfo? probeWithPicture(int attached) =>
        PlaybackAudioProbe.parse({
          'streams': [
            {'codec_type': 'audio', 'codec_name': 'aac'},
            {
              'codec_type': 'video',
              'disposition': {'attached_pic': attached},
            },
          ],
          'format': {'bit_rate': '256000'},
        }, sourceId);

    expect(probeWithPicture(1)?.bitRate, 256);
    expect(probeWithPicture(1)?.bitRateEstimated, isTrue);
    expect(probeWithPicture(0)?.bitRate, isNull);
    expect(probeWithPicture(0)?.bitRateEstimated, isFalse);
  });

  test(
    'omits invalid bitrate fields while retaining audio format and codec',
    () {
      final info = PlaybackAudioProbe.parse(
        {
          'streams': [
            {'codec_type': 'audio', 'codec_name': 'opus', 'bit_rate': 'N/A'},
          ],
          'format': {'bit_rate': '10000001'},
        },
        sourceId,
        format: 'webm',
      )!;

      expect(info.format, 'webm');
      expect(info.codec, 'opus');
      expect(info.bitRate, isNull);
      expect(info.bitRateEstimated, isFalse);
      expect(info.label, isNot(contains('kbps')));
    },
  );

  test('rejects missing, malformed and ambiguous stream data', () {
    expect(PlaybackAudioProbe.parse(null, sourceId), isNull);
    expect(PlaybackAudioProbe.parse({'streams': 'bad'}, sourceId), isNull);
    expect(
      PlaybackAudioProbe.parse({
        'streams': [
          null,
          {'codec_type': 'video'},
        ],
      }, sourceId),
      isNull,
    );
    expect(
      PlaybackAudioProbe.parse({
        'streams': [
          {'codec_type': 'audio', 'bit_rate': '128000'},
          {'codec_type': 'audio', 'bit_rate': '256000'},
        ],
      }, sourceId),
      isNull,
    );
  });
}
