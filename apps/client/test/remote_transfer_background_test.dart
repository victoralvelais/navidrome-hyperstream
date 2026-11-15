import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperstream_client/services/remote_transfer_background.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.hyperstream/remote_transfer');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  Future<void> expire(String token) async {
    await messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('expired', token),
      ),
      (_) {},
    );
  }

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  for (final mode in ['continued', 'limited', 'foreground']) {
    test(
      '$mode grant forwards progress, matches expiry and ends exactly once',
      () async {
        final calls = <MethodCall>[];
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return call.method == 'begin' ? mode : null;
        });
        final execution = RemoteTransferBackground(isIOS: true);
        var expired = 0;
        expect((await execution.begin(() => expired++)).name, mode);
        final token = (calls.single.arguments as Map)['token'] as String;
        await execution.prepareDirectory(Directory('/private/cache/test'));
        execution.update(completed: 2, total: 11, stage: 'Downloading audio');
        execution.update(completed: 3, total: 11, stage: 'Downloading audio');
        execution.update(completed: 5, total: 11, stage: 'Sending audio');
        await Future<void>.delayed(Duration.zero);
        final updates = calls.where((call) => call.method == 'update').toList();
        expect(updates, hasLength(2));
        expect(updates.last.arguments, {
          'token': token,
          'completed': 5,
          'total': 11,
          'stage': 'Sending audio',
        });
        await expire('another-transfer');
        expect(expired, 0);
        await expire(token);
        expect(expired, 1);
        await execution.finish(success: false);
        await execution.finish(success: true);
        await expire(token);
        execution.update(completed: 11, total: 11, stage: 'Finished');
        expect(expired, 1);
        expect(calls.where((call) => call.method == 'finish'), hasLength(1));
        expect(calls.last.arguments, {'token': token, 'success': false});
      },
    );
  }

  test(
    'missing bridge falls back to foreground and preserves file preparation',
    () async {
      final execution = RemoteTransferBackground(isIOS: true);
      expect(await execution.begin(() {}), RemoteBackgroundMode.foreground);
      await execution.prepareDirectory(Directory('/private/cache/test'));
      execution.update(completed: 1, total: 3, stage: 'Sending audio');
      await execution.finish(success: true);
    },
  );

  test('native grant errors preserve foreground transfers', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'unavailable');
    });
    final execution = RemoteTransferBackground(isIOS: true);
    expect(await execution.begin(() {}), RemoteBackgroundMode.foreground);
    execution.update(completed: 1, total: 3, stage: 'Sending audio');
    await execution.finish(success: true);
  });

  test('desktop has no iOS platform calls', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => fail('Unexpected native call'),
    );
    final execution = RemoteTransferBackground(isIOS: false);
    expect(await execution.begin(() {}), RemoteBackgroundMode.desktop);
    await execution.prepareDirectory(Directory('cache'));
    execution.update(completed: 1, total: 3, stage: 'Sending audio');
    await execution.finish(success: true);
  });
}
