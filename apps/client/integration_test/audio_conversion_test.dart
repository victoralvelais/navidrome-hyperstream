import 'dart:convert';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_audio/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_audio/return_code.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperstream_client/models/library.dart';
import 'package:hyperstream_client/models/source_reference.dart';
import 'package:hyperstream_client/services/mp3_converter.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native conversion validates MP3 320, metadata and attached artwork',
    (tester) async {
      final directory = await Directory.systemTemp.createTemp(
        'hyperstream-conversion-',
      );
      try {
        final input = File('${directory.path}/Synthetic source.flac');
        final source = await FFmpegKit.executeWithArguments([
          '-f',
          'lavfi',
          '-i',
          'sine=frequency=440:duration=4',
          '-c:a',
          'flac',
          input.path,
        ]);
        expect(ReturnCode.isSuccess(await source.getReturnCode()), true);
        const track = Track(
          id: 'synthetic',
          title: 'Synthetic title',
          artist: 'Synthetic artist',
          album: 'Synthetic album',
          number: 2,
          duration: Duration(seconds: 4),
          source: SourceReference(
            sourceId: 'test',
            trackId: 'test',
            disc: 1,
            isrc: 'USAAA2600001',
          ),
        );
        final file = await Mp3Converter().convert(input, track);
        final probe = await FFprobeKit.getMediaInformation(file.path);
        final data = probe.getMediaInformation()!.getAllProperties()!;
        Mp3Converter.validate(data, track);
        final tags = (data['format'] as Map)['tags'] as Map;
        expect(tags['title'], track.title);
        expect(tags['artist'], track.artist);
        expect(tags['album'], track.album);
        expect(tags['track'], '2');
        expect(await input.exists(), true);

        // A local 1px PNG exercises the same artwork argument path as downloaded covers.
        final cover = await File('${directory.path}/cover.png').writeAsBytes(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
          ),
        );
        final covered = File('${directory.path}/covered.mp3');
        final session = await FFmpegKit.executeWithArguments(
          Mp3Converter.arguments(input, covered, track, artwork: cover),
        );
        expect(
          ReturnCode.isSuccess(await session.getReturnCode()),
          true,
          reason: await session.getOutput(),
        );
        final coverProbe = await FFprobeKit.getMediaInformation(covered.path);
        final coverData = coverProbe.getMediaInformation()!.getAllProperties()!;
        Mp3Converter.validate(coverData, track);
        expect(
          (coverData['streams'] as List).where(
            (s) => s['codec_type'] == 'video',
          ),
          hasLength(1),
        );
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );
}
