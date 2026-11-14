import 'dart:io';

import 'package:dart_smb2/dart_smb2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperstream_client/services/remote_folder.dart';

class MemoryRemoteStore implements RemoteDestinationStore {
  RemoteDestination? value;
  bool failWrite = false;
  @override
  Future<RemoteDestination?> read() async => value;
  @override
  Future<void> write(RemoteDestination? destination) async {
    if (failWrite) {
      throw const RemoteFolderException('Secure storage unavailable.');
    }
    value = destination;
  }
}

class MemoryRemoteFs implements RemoteFileSystem {
  final files = <String, List<int>>{};
  final renames = <(String, String)>[];
  bool closed = false;
  bool truncateWrite = false;
  bool loseRenameReply = false;
  void Function()? afterWrite;
  @override
  Future<({bool directory, int size})> stat(String path) async => path == 'Test'
      ? (directory: true, size: 0)
      : (directory: false, size: files[path]?.length ?? 0);
  @override
  Future<void> write(
    String path,
    Stream<List<int>> chunks,
    int length,
    void Function(int) progress,
    bool Function() cancelled,
  ) async {
    files[path] = [];
    await for (final chunk in chunks) {
      if (cancelled()) throw const RemoteSendCancelled();
      files[path]!.addAll(chunk);
      progress(files[path]!.length);
    }
    if (truncateWrite) files[path]!.removeLast();
    afterWrite?.call();
  }

  @override
  Future<void> rename(String from, String to) async {
    renames.add((from, to));
    if (files.containsKey(to)) {
      throw const Smb2Exception('Exists', type: Smb2ErrorType.alreadyExists);
    }
    files[to] = files.remove(from)!;
    if (loseRenameReply) {
      throw const Smb2Exception(
        'Lost response',
        type: Smb2ErrorType.connection,
      );
    }
  }

  @override
  Future<void> delete(String path) async {
    files.remove(path);
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}

RemoteDestination destination({
  String address = 'smb://server/share/Test',
  String password = 'secret',
}) => RemoteDestination(
  address: address,
  username: r'KIRA\Listener',
  password: password,
  name: 'Test folder',
);

void main() {
  test(
    'SMB and UNC addresses retain folders, domain, and protected roundtrip',
    () {
      final d = destination(address: r'\\server\share\Test');
      expect(d.host, 'server');
      expect(d.share, 'share');
      expect(d.folder, 'Test');
      expect(d.domain, 'KIRA');
      expect(d.user, 'Listener');
      expect(RemoteDestination.decode(d.encode()).password, 'secret');
      expect(d.toString(), isNot(contains('secret')));
      expect(
        destination(address: 'smb://server/share/My%20Music').folder,
        'My Music',
      );
    },
  );
  test(
    'reject credentials in URLs, non-SMB endpoints, traversal, and ADS paths',
    () {
      for (final address in [
        'https://server/share',
        'smb://user:secret@server/share',
        'smb://server',
        'smb://server/share/a%2fb',
        'smb://server/share/file:stream',
        'smb://server/share/..',
        'smb://server/share/%2e%2e/escape',
        'smb://server/share/NUL.mp3',
        'smb://server/share?password=secret',
      ]) {
        expect(
          () => destination(address: address),
          throwsFormatException,
          reason: address,
        );
      }
    },
  );
  test('connection probe is removed before the credential is saved', () async {
    final fs = MemoryRemoteFs()..files['Test/existing.mp3'] = [7];
    final store = MemoryRemoteStore();
    final remote = RemoteFolders(store: store, connect: (_) async => fs);
    await remote.restore();
    await remote.testAndSave(destination());
    expect(fs.files, {
      'Test/existing.mp3': [7],
    });
    expect(fs.renames, hasLength(1));
    expect(fs.closed, isTrue);
    expect(store.value?.password, 'secret');
    expect(remote.busy, isFalse);
  });
  test(
    'failed credential save keeps the previous destination and cleans probe',
    () async {
      final fs = MemoryRemoteFs();
      final store = MemoryRemoteStore()
        ..value = destination(password: 'old')
        ..failWrite = true;
      final remote = RemoteFolders(store: store, connect: (_) async => fs);
      await remote.restore();
      await expectLater(
        remote.testAndSave(destination()),
        throwsA(isA<RemoteFolderException>()),
      );
      expect(remote.destination?.password, 'old');
      expect(fs.files, isEmpty);
      expect(fs.closed, isTrue);
      expect(remote.busy, isFalse);
    },
  );

  group('staged uploads', () {
    late Directory temp;
    late File file;
    late MemoryRemoteFs fs;
    var cancelled = false;
    var finishing = false;
    setUp(() async {
      temp = await Directory.systemTemp.createTemp('hyperstream-remote-test-');
      file = await File('${temp.path}/Artist - Song.mp3')
          .writeAsBytes([73, 68, 51, 7, 9]);
      fs = MemoryRemoteFs();
      cancelled = false;
      finishing = false;
    });
    tearDown(() async {
      expect(
        temp.absolute.path.startsWith(Directory.systemTemp.absolute.path),
        isTrue,
      );
      await temp.delete(recursive: true);
    });
    Future<String> send() => sendRemoteFile(
      fs: fs,
      destination: destination(),
      file: file,
      cancelled: () => cancelled,
      onProgress: (_, _) {},
      onFinishing: () => finishing = true,
    );

    test(
      'publishes complete bytes and adds a suffix without overwriting',
      () async {
        fs.files['Test/Artist - Song.mp3'] = [99];
        final name = await send();
        expect(name, 'Artist - Song (1).mp3');
        expect(fs.files['Test/Artist - Song.mp3'], [99]);
        expect(fs.files['Test/$name'], await file.readAsBytes());
        expect(fs.files.length, 2);
        expect(finishing, isTrue);
      },
    );
    test('incomplete remote write is never published', () async {
      fs.truncateWrite = true;
      await expectLater(send(), throwsA(isA<RemoteFolderException>()));
      expect(fs.renames, isEmpty);
      expect(fs.files, isEmpty);
    });
    test(
      'cancellation after upload still removes partial without publishing',
      () async {
        fs.afterWrite = () => cancelled = true;
        await expectLater(send(), throwsA(isA<RemoteSendCancelled>()));
        expect(fs.renames, isEmpty);
        expect(fs.files, isEmpty);
      },
    );
    test(
      'lost final acknowledgement does not retry or remove the completed file',
      () async {
        fs.loseRenameReply = true;
        await expectLater(
          send(),
          throwsA(
            isA<RemoteFolderException>().having(
              (e) => e.message,
              'uncertainty',
              contains('may already have arrived'),
            ),
          ),
        );
        expect(fs.renames, hasLength(1));
        expect(fs.files['Test/Artist - Song.mp3'], await file.readAsBytes());
      },
    );
  });
  test('native failures cannot leak passwords or server responses', () {
    const error = Smb2Exception(
      'password=secret; authenticated URL',
      type: Smb2ErrorType.auth,
    );
    expect(remoteFolderError(error), isNot(contains('secret')));
    expect(remoteFolderError(error), contains('Windows username'));
  });
}
