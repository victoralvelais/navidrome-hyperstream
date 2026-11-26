import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperstream_client/models/library.dart';
import 'package:hyperstream_client/models/source_reference.dart';
import 'package:hyperstream_client/services/audio_file_share.dart';
import 'package:hyperstream_client/services/mp3_converter.dart';
import 'package:hyperstream_client/services/music_provider.dart';

import 'external_playback_test.dart' show externalSong;

void main() {
  final messenger =
      TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger;

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

  group('remote audio preparation', () {
    late File input;
    late _ConverterBridge bridge;

    setUp(() async {
      final directory = await Directory.systemTemp.createTemp('mp3-test-');
      addTearDown(() => directory.delete(recursive: true));
      input = await File('${directory.path}/source.m4a').writeAsBytes([1]);
      bridge = _ConverterBridge(messenger);
      addTearDown(bridge.dispose);
    });

    for (final (codec, muxer, extension) in [
      ('aac', 'ipod', 'm4a'),
      ('mp3', 'mp3', 'mp3'),
      ('opus', 'opus', 'opus'),
      ('vorbis', 'ogg', 'ogg'),
    ]) {
      test('copies $codec packets and tags the file', () async {
        bridge.inputProbe = bridge.outputProbe = _audioProbe(codec: codec);
        final conversion = Mp3Converter().prepare(input, _soundCloudSong);
        final session = await bridge.firstAttempt.future;
        final args = bridge.arguments.single;
        final output = File(args.last);
        expect(args, containsAllInOrder(['-c:a', 'copy']));
        expect(args, containsAllInOrder(['-f', muxer, output.path]));
        expect(args, containsAll(['title=Song', 'artist=Artist']));
        for (final encodeOption in ['-b:a', '-ar', '-ac', 'libmp3lame']) {
          expect(args, isNot(contains(encodeOption)));
        }
        if (codec == 'opus' || codec == 'vorbis') {
          expect(args, contains('-vn'));
        }
        await output.writeAsBytes([1]);
        await bridge.complete(session, 0);

        final prepared = await conversion;
        expect(prepared.path, endsWith('source.$extension'));
        expect(bridge.probes, [input.path, output.path]);
      });
    }

    test('encodes lossless ALAC stored in an M4A file as MP3 320', () async {
      bridge.inputProbe = _audioProbe(codec: 'alac');
      final conversion = Mp3Converter().prepare(input, _soundCloudSong);
      final session = await bridge.firstAttempt.future;
      final args = bridge.arguments.single;
      final output = File(args.last);
      expect(args, containsAllInOrder(['-c:a', 'libmp3lame', '-b:a', '320k']));
      await output.writeAsBytes([1]);
      await bridge.complete(session, 0);

      expect((await conversion).path, endsWith('source.mp3'));
      expect(bridge.probes, [input.path, output.path]);
    });

    for (final (change, sourceProbe, outputProbe) in [
      (
        'sample rate',
        _audioProbe(codec: 'aac', sampleRate: '48000'),
        _audioProbe(codec: 'aac'),
      ),
      (
        'duration within catalog tolerance',
        _audioProbe(codec: 'aac', duration: '183'),
        _audioProbe(codec: 'aac', duration: '177'),
      ),
    ]) {
      test('rejects a copy with a changed $change before renaming', () async {
        bridge.inputProbe = sourceProbe;
        bridge.outputProbe = outputProbe;
        final conversion = Mp3Converter().prepare(input, _soundCloudSong);
        final failure = expectLater(
          conversion,
          throwsA(isA<SourceException>()),
        );
        final session = await bridge.firstAttempt.future;
        final output = File(bridge.arguments.single.last);
        await output.writeAsBytes([1]);
        await bridge.complete(session, 0);
        await failure;

        expect(bridge.arguments, hasLength(1));
        expect(bridge.probes, [input.path, output.path]);
        expect(
          await File(output.path.replaceFirst(RegExp(r'\.part$'), '')).exists(),
          isFalse,
        );
      });
    }

    test('retries without artwork and validates before renaming', () async {
      final conversion = Mp3Converter().convert(input, externalSong);
      final first = await bridge.firstAttempt.future;
      final output = File(bridge.arguments.single.last);
      expect(bridge.arguments.single, contains('0:v:0?'));
      await output.writeAsBytes([1]);
      await bridge.complete(first, 1);

      final second = await bridge.secondAttempt.future;
      expect(bridge.arguments.last, contains('-vn'));
      expect(bridge.arguments.last, isNot(contains('0:v:0?')));
      expect(bridge.arguments.last.last, output.path);
      expect(await output.exists(), isFalse);
      await output.writeAsBytes([2]);
      await bridge.complete(second, 0);

      final converted = await conversion;
      expect(bridge.probes, [output.path]);
      expect(converted.path, output.path.replaceFirst(RegExp(r'\.part$'), ''));
      expect(await converted.readAsBytes(), [2]);
      expect(await output.exists(), isFalse);
    });

    test('reports failure after both attempts without publishing', () async {
      final conversion = Mp3Converter().convert(input, externalSong);
      final failure = expectLater(conversion, throwsA(isA<SourceException>()));
      await bridge.complete(await bridge.firstAttempt.future, 1);
      final second = await bridge.secondAttempt.future;
      final output = File(bridge.arguments.last.last);
      await output.writeAsBytes([1]);
      await bridge.complete(second, 1);
      await failure;

      expect(bridge.arguments, hasLength(2));
      expect(bridge.probes, isEmpty);
      expect(
        File(output.path.replaceFirst(RegExp(r'\.part$'), '')).existsSync(),
        isFalse,
      );
    });

    test('cancellation during the first attempt prevents retry', () async {
      final converter = Mp3Converter();
      final conversion = converter.convert(input, externalSong);
      final failure = expectLater(
        conversion,
        throwsA(isA<AudioShareCancelled>()),
      );
      final first = await bridge.firstAttempt.future;
      converter.cancel();
      await bridge.complete(first, 255);
      await failure;

      expect(bridge.arguments, hasLength(1));
      expect(bridge.cancelled, contains(first));
      expect(bridge.probes, isEmpty);
    });
  });
}

const _soundCloudSong = Track(
  id: 'external:mornye:soundcloud:one',
  title: 'Song',
  artist: 'Artist',
  album: 'Album',
  duration: Duration(minutes: 3),
  source: SourceReference(sourceId: 'mornye:soundcloud', trackId: 'one'),
);

Map<String, Object> _audioProbe({
  String codec = 'mp3',
  String sampleRate = '44100',
  String duration = '180.12',
}) => {
  'streams': [
    {
      'codec_type': 'audio',
      'codec_name': codec,
      'bit_rate': '320000',
      'sample_rate': sampleRate,
      'channels': 2,
    },
  ],
  'format': {'duration': duration},
};

class _ConverterBridge {
  _ConverterBridge(this.messenger) {
    messenger.setMockMethodCallHandler(_channel, _handle);
    messenger.setMockMethodCallHandler(_eventChannel, (_) async => null);
  }

  static const _channel = MethodChannel('flutter.arthenica.com/ffmpeg_kit');
  static const _eventChannel = MethodChannel(
    'flutter.arthenica.com/ffmpeg_kit_event',
  );
  static int _lastSessionId = 0;

  final TestDefaultBinaryMessenger messenger;
  final arguments = <List<String>>[];
  final probes = <String>[];
  final cancelled = <int>[];
  final firstAttempt = Completer<int>();
  final secondAttempt = Completer<int>();
  final _returnCodes = <int, int>{};
  Map<String, Object> inputProbe = _audioProbe();
  Map<String, Object> outputProbe = _audioProbe();

  void dispose() {
    messenger.setMockMethodCallHandler(_channel, null);
    messenger.setMockMethodCallHandler(_eventChannel, null);
  }

  Future<void> complete(int sessionId, int returnCode) async {
    _returnCodes[sessionId] = returnCode;
    await messenger.handlePlatformMessage(
      _eventChannel.name,
      const StandardMethodCodec().encodeSuccessEnvelope({
        'FFmpegKitCompleteCallbackEvent': {'sessionId': sessionId},
      }),
      null,
    );
  }

  Future<Object?> _handle(MethodCall call) async {
    switch (call.method) {
      case 'getLogLevel':
        return null;
      case 'getPlatform':
      case 'getArch':
      case 'getPackageName':
        return 'test';
      case 'enableRedirection':
      case 'mediaInformationSessionExecute':
        return null;
      case 'isLTSBuild':
        return false;
      case 'ffmpegSession':
        arguments.add(List<String>.from(call.arguments['arguments'] as List));
        return {'sessionId': ++_lastSessionId};
      case 'asyncFFmpegSessionExecute':
        final sessionId = call.arguments['sessionId'] as int;
        final attempt = arguments.length == 1 ? firstAttempt : secondAttempt;
        attempt.complete(sessionId);
        return null;
      case 'getSession':
        return {'sessionId': call.arguments['sessionId'], 'command': ''};
      case 'abstractSessionGetReturnCode':
        return _returnCodes[call.arguments['sessionId']];
      case 'cancelSession':
        cancelled.add(call.arguments['sessionId'] as int);
        return null;
      case 'mediaInformationSession':
        probes.add((call.arguments['arguments'] as List).last as String);
        return {'sessionId': ++_lastSessionId};
      case 'getMediaInformation':
        return probes.last.endsWith('.part') ? outputProbe : inputProbe;
      default:
        throw StateError('Unexpected FFmpegKit call ${call.method}');
    }
  }
}
