import 'dart:io';

import 'package:dart_smb2/dart_smb2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperstream_client/services/remote_folder.dart';

class _TransientStore implements RemoteDestinationStore {
  RemoteDestination? value;
  @override
  Future<RemoteDestination?> read() async => value;
  @override
  Future<void> write(RemoteDestination? next) async {
    value = next;
  }
}

void main() {
  final address = Platform.environment['HYPERSTREAM_SMB_TEST_ADDRESS'];
  test(
    'encrypted native SMB writes, verifies, handles collisions and rejects bad login',
    () async {
      final destination = RemoteDestination(
        address: address!,
        username: Platform.environment['HYPERSTREAM_SMB_TEST_USER']!,
        password: Platform.environment['HYPERSTREAM_SMB_TEST_PASSWORD']!,
      );
      final remote = RemoteFolders(store: _TransientStore());
      await remote.restore();
      await remote.testAndSave(destination);
      final fs = await connectRemoteFolder(destination);
      final temp = await Directory.systemTemp.createTemp(
        'hyperstream-smb-live-',
      );
      final bytes = List<int>.generate(300000, (i) => i % 251);
      final file = await File('${temp.path}/Test audio.mp3')
          .writeAsBytes(bytes);
      try {
        Future<String> send() => sendRemoteFile(
          fs: fs,
          destination: destination,
          file: file,
          cancelled: () => false,
          onProgress: (_, _) {},
          onFinishing: () {},
        );
        expect(await send(), 'Test audio.mp3');
        expect(await send(), 'Test audio (1).mp3');
        final reader = await Smb2Pool.connect(
          host: destination.host,
          share: destination.share,
          user: destination.user,
          domain: destination.domain,
          password: destination.password,
          seal: true,
          signing: true,
          workers: 1,
          version: Smb2Version.any3,
        );
        try {
          expect(
            await reader.readFile(destination.path('Test audio.mp3')),
            bytes,
          );
          expect(
            await reader.readFile(destination.path('Test audio (1).mp3')),
            bytes,
          );
          expect(
            (await reader.listDirectory(destination.folder))
                .map((e) => e.name)
                .where((n) => n.endsWith('.part')),
            isEmpty,
          );
        } finally {
          await reader.disconnect();
        }
        final bad = RemoteDestination(
          address: address,
          username: destination.username,
          password: '${destination.password}-wrong',
        );
        await expectLater(
          connectRemoteFolder(bad),
          throwsA(
            isA<Smb2Exception>().having(
              (e) => e.type,
              'auth classification',
              Smb2ErrorType.auth,
            ),
          ),
        );
      } finally {
        await fs.close();
        expect(
          temp.absolute.path.startsWith(Directory.systemTemp.absolute.path),
          isTrue,
        );
        await temp.delete(recursive: true);
      }
    },
    skip: address == null
        ? 'Runs only against the disposable CI SMB share.'
        : false,
  );
}
