import 'dart:async';
import 'dart:io';

import 'package:dart_smb2/dart_smb2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperstream_client/services/remote_folder.dart';

class MemoryRemoteStore implements RemoteFolderStore {
  RemoteFolderConfig? value;
  bool failWrite = false;
  @override
  Future<RemoteFolderConfig?> read() async => value;
  @override
  Future<void> write(RemoteFolderConfig? destination) async {
    if (failWrite) {
      throw const RemoteFolderException('Secure storage unavailable.');
    }
    value = destination;
  }
}

class MemoryRemoteFs implements RemoteFileSystem {
  final files = <String, List<int>>{};
  final folders = <String, List<String>>{
    '': ['Test'],
    'Test': ['Deep'],
    'Test/Deep': [],
  };
  final listed = <String>[];
  final renames = <(String, String)>[];
  bool closed = false;
  bool truncateWrite = false;
  bool loseRenameReply = false;
  Object? statError;
  Object? writeError;
  Object? listError;
  void Function()? afterWrite;
  void Function()? afterClose;
  @override
  Future<List<String>> listFolders(String path) async {
    listed.add(path);
    if (listError != null) throw listError!;
    return folders[path] ?? [];
  }

  @override
  Future<({bool directory, int size})> stat(String path) async {
    if (statError != null) throw statError!;
    return folders.containsKey(path)
        ? (directory: true, size: 0)
        : (directory: false, size: files[path]?.length ?? 0);
  }

  @override
  Future<void> write(
    String path,
    Stream<List<int>> chunks,
    int length,
    void Function(int) progress,
    bool Function() cancelled,
  ) async {
    if (writeError != null) throw writeError!;
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
    afterClose?.call();
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
    expect(store.value?.connection.password, 'secret');
    expect(remote.busy, isFalse);
  });
  test(
    'failed credential save keeps the previous destination and cleans probe',
    () async {
      final fs = MemoryRemoteFs();
      final store = MemoryRemoteStore()
        ..value = RemoteFolderConfig.forDestination(
          destination(password: 'old'),
        )
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

  group('separate server login', () {
    test('accepts bare hosts, UNC hosts and either domain separator', () {
      for (final address in [
        'server',
        'smb://server/',
        r'\\server',
        '192.0.2.1',
      ]) {
        final connection = RemoteConnection(
          address: address,
          username: 'COMPUTER/Listener',
          password: 'synthetic',
        );
        expect(connection.domain, 'COMPUTER');
        expect(connection.user, 'Listener');
        expect(connection.username, r'COMPUTER\Listener');
        expect(connection.toString(), isNot(contains('synthetic')));
        expect(connection.destination(share: 'Music').folder, isEmpty);
        expect(
          connection.destination(share: 'Music', folder: r'Albums\New').folder,
          'Albums/New',
        );
      }
      for (final address in [
        'smb://server/share',
        'smb://user:synthetic@server',
        'server:444',
        'smb://server/%zz',
        'server name',
      ]) {
        expect(
          () => RemoteConnection(
            address: address,
            username: 'Listener',
            password: 'synthetic',
          ),
          throwsFormatException,
          reason: address,
        );
      }
    });

    test(
      'restores legacy destinations and roundtrips a login without a folder',
      () {
        final migrated = RemoteFolderConfig.decode(destination().encode());
        expect(migrated.connection.address, 'smb://server');
        expect(migrated.destination?.address, destination().address);
        expect(
          RemoteFolderConfig.decode(migrated.encode()).destination?.password,
          'secret',
        );
        final loginOnly = RemoteFolderConfig(migrated.connection);
        final decoded = RemoteFolderConfig.decode(loginOnly.encode());
        expect(decoded.connection.username, migrated.connection.username);
        expect(decoded.destination, isNull);
        expect(decoded.toString(), isNot(contains('secret')));
      },
    );

    test(
      'saves a checked login without opening or writing to a disk share',
      () async {
        final store = MemoryRemoteStore();
        final remote = RemoteFolders(
          store: store,
          checkLogin: (connection) async => expect(connection.host, 'server'),
          connect: (_) async =>
              throw StateError('Disk share must not be opened'),
        );
        await remote.restore();
        await remote.checkAndSaveConnection(destination().connection);
        expect(store.value?.connection.password, 'secret');
        expect(remote.destination, isNull);
        final restored = RemoteFolders(store: store);
        await restored.restore();
        expect(restored.connection?.host, 'server');
        expect(restored.destination, isNull);
        expect(remote.busy, isFalse);
        expect(remote.checking, isNull);
        await remote.forget();
        expect(store.value, isNull);
        expect(remote.connection, isNull);
      },
    );

    test(
      'failed login and failed save preserve the previous secure record',
      () async {
        for (final failSave in [false, true]) {
          final store = MemoryRemoteStore()
            ..value = RemoteFolderConfig.forDestination(
              destination(password: 'old'),
            )
            ..failWrite = failSave;
          final remote = RemoteFolders(
            store: store,
            checkLogin: (_) async {
              if (!failSave) {
                throw const Smb2Exception(
                  'private response',
                  type: Smb2ErrorType.auth,
                );
              }
            },
          );
          await remote.restore();
          await expectLater(
            remote.checkAndSaveConnection(destination().connection),
            throwsA(
              isA<RemoteCheckException>().having(
                (e) => e.stage,
                'stage',
                failSave ? RemoteCheckStage.save : RemoteCheckStage.login,
              ),
            ),
          );
          expect(remote.connection?.password, 'old');
          expect(remote.destination?.folder, 'Test');
          expect(store.value?.connection.password, 'old');
          expect(remote.busy, isFalse);
        }
      },
    );

    test(
      'same-account reconnect keeps the folder, another server clears it',
      () async {
        final store = MemoryRemoteStore()
          ..value = RemoteFolderConfig.forDestination(
            destination(password: 'old'),
          );
        final remote = RemoteFolders(store: store, checkLogin: (_) async {});
        await remote.restore();
        await remote.checkAndSaveConnection(destination().connection);
        expect(remote.destination?.password, 'secret');
        expect(remote.destination?.folder, 'Test');
        await remote.checkAndSaveConnection(
          RemoteConnection(
            address: 'other-server',
            username: 'Listener',
            password: 'synthetic',
          ),
        );
        expect(remote.destination, isNull);
        expect(store.value?.destination, isNull);
      },
    );

    test('share, folder and write errors identify the failing stage', () async {
      for (final stage in [
        RemoteCheckStage.share,
        RemoteCheckStage.folder,
        RemoteCheckStage.write,
      ]) {
        const failure = Smb2Exception(
          'private response',
          type: Smb2ErrorType.accessDenied,
        );
        final fs = MemoryRemoteFs();
        if (stage == RemoteCheckStage.folder) fs.statError = failure;
        if (stage == RemoteCheckStage.write) fs.writeError = failure;
        final remote = RemoteFolders(
          store: MemoryRemoteStore(),
          checkLogin: (_) async {},
          connect: (_) async {
            if (stage == RemoteCheckStage.share) throw failure;
            return fs;
          },
        );
        await remote.restore();
        await remote.checkAndSaveConnection(destination().connection);
        await expectLater(
          remote.testAndSave(destination()),
          throwsA(
            isA<RemoteCheckException>()
                .having((e) => e.stage, 'stage', stage)
                .having(
                  (e) => e.message,
                  'redacted',
                  isNot(contains('private response')),
                ),
          ),
        );
        expect(remote.connection?.host, 'server');
        expect(remote.destination, isNull);
        expect(fs.files, isEmpty);
        expect(remote.busy, isFalse);
      }
    });

    test(
      'concurrent checks cannot report a skipped operation as successful',
      () async {
        final pending = Completer<void>();
        final remote = RemoteFolders(
          store: MemoryRemoteStore(),
          checkLogin: (_) => pending.future,
        );
        final first = remote.checkAndSaveConnection(destination().connection);
        await expectLater(
          remote.testAndSave(destination()),
          throwsA(isA<RemoteFolderException>()),
        );
        pending.complete();
        await first;
        expect(remote.destination, isNull);
      },
    );
  });

  group('remote folder browser', () {
    test(
      'discovery skips hidden shares and verifies ordinary share access',
      () async {
        final connection = RemoteConnection(
          address: 'server',
          username: 'Listener',
          password: 'synthetic',
        );
        final store = MemoryRemoteStore();
        final checked = <String>[];
        final sessions = <MemoryRemoteFs>[];
        final remote = RemoteFolders(
          store: store,
          checkLogin: (_) async {},
          connect: (location) async {
            checked.add(location.share);
            if (location.share == 'Denied') {
              throw const Smb2Exception(
                'Denied',
                type: Smb2ErrorType.accessDenied,
              );
            }
            if (location.share == 'Missing') {
              throw const Smb2Exception(
                'Missing',
                type: Smb2ErrorType.notFound,
              );
            }
            final fs = MemoryRemoteFs();
            if (location.share == 'RootDenied') {
              fs.listError = const Smb2Exception(
                'Denied',
                type: Smb2ErrorType.accessDenied,
              );
            }
            sessions.add(fs);
            return fs;
          },
          listShares: (login) async {
            expect(login.username, 'Listener');
            expect(login.domain, isEmpty);
            return const [
              Smb2ShareInfo(name: 'Music', type: 0),
              Smb2ShareInfo(name: 'docs', type: 0),
              Smb2ShareInfo(name: r'C$', type: Smb2ShareType.hidden),
              Smb2ShareInfo(name: r'ADMIN$', type: 0),
              Smb2ShareInfo(name: 'HiddenFlag', type: Smb2ShareType.hidden),
              Smb2ShareInfo(name: 'Denied', type: 0),
              Smb2ShareInfo(name: 'RootDenied', type: 0),
              Smb2ShareInfo(name: 'Missing', type: 0),
              Smb2ShareInfo(name: r'IPC$', type: 3),
              Smb2ShareInfo(name: 'Printer', type: 1),
              Smb2ShareInfo(name: '..', type: 0),
              Smb2ShareInfo(name: 'Music', type: 0),
            ];
          },
        );
        await remote.checkAndSaveConnection(connection);
        expect(await remote.browseShares(connection), ['docs', 'Music']);
        expect(checked, ['Denied', 'docs', 'Missing', 'Music', 'RootDenied']);
        expect(
          sessions.every(
            (fs) => fs.closed && fs.listed.single.isEmpty && fs.files.isEmpty,
          ),
          isTrue,
        );
        final restored = RemoteFolders(store: store);
        await restored.restore();
        expect(restored.connection?.username, 'Listener');
        expect(remote.destination, isNull);
        expect(remote.busy, isFalse);
      },
    );

    test(
      'connection or login failures stay visible and preserve saved settings',
      () async {
        for (final type in [
          Smb2ErrorType.connection,
          Smb2ErrorType.timeout,
          Smb2ErrorType.auth,
        ]) {
          final fs = MemoryRemoteFs()
            ..listError = Smb2Exception('private response', type: type);
          final store = MemoryRemoteStore()
            ..value = RemoteFolderConfig.forDestination(destination());
          final remote = RemoteFolders(
            store: store,
            connect: (_) async => fs,
            listShares: (_) async => const [
              Smb2ShareInfo(name: 'Music', type: 0),
            ],
          );
          await remote.restore();
          await expectLater(
            remote.browseShares(remote.connection!),
            throwsA(
              isA<RemoteCheckException>()
                  .having((e) => e.stage, 'stage', RemoteCheckStage.shares)
                  .having(
                    (e) => e.message,
                    'redacted',
                    isNot(contains('private response')),
                  ),
            ),
          );
          expect(fs.closed, isTrue);
          expect(remote.destination?.address, destination().address);
          expect(remote.busy, isFalse);
        }
      },
    );

    test(
      'share access checks use at most three sessions at once and close all',
      () async {
        final gate = Completer<void>();
        var active = 0;
        var peak = 0;
        var opened = 0;
        final remote = RemoteFolders(
          store: MemoryRemoteStore(),
          listShares: (_) async => List.generate(
            8,
            (index) => Smb2ShareInfo(name: 'Share$index', type: 0),
          ),
          connect: (_) async {
            opened++;
            active++;
            if (active > peak) peak = active;
            await gate.future;
            return MemoryRemoteFs()..afterClose = () => active--;
          },
        );
        final pending = remote.browseShares(destination().connection);
        await Future<void>.delayed(Duration.zero);
        expect(opened, 3);
        expect(remote.busy, isTrue);
        gate.complete();
        expect(await pending, hasLength(8));
        expect(opened, 8);
        expect(peak, 3);
        expect(active, 0);
        expect(remote.busy, isFalse);
      },
    );

    test(
      'browsing closes its session and leaves selection and files untouched',
      () async {
        final fs = MemoryRemoteFs()
          ..folders['Test'] = ['Zoo', '..', '.', 'alpha', r'a\b'];
        final store = MemoryRemoteStore()
          ..value = RemoteFolderConfig.forDestination(destination());
        final remote = RemoteFolders(store: store, connect: (_) async => fs);
        await remote.restore();
        expect(await remote.browseFolders(destination()), ['alpha', 'Zoo']);
        expect(fs.closed, isTrue);
        expect(fs.listed, ['Test']);
        expect(fs.files, isEmpty);
        expect(fs.renames, isEmpty);
        expect(remote.destination?.address, destination().address);
      },
    );

    test('listing failures preserve the login, sanitize errors, and close sessions', () async {
      const failure = Smb2Exception(
        'private server response',
        type: Smb2ErrorType.accessDenied,
      );
      final fs = MemoryRemoteFs()..listError = failure;
      final store = MemoryRemoteStore()
        ..value = RemoteFolderConfig(destination().connection);
      final remote = RemoteFolders(
        store: store,
        connect: (_) async => fs,
        listShares: (_) async => throw failure,
      );
      await remote.restore();
      await expectLater(
        remote.browseShares(remote.connection!),
        throwsA(
          isA<RemoteCheckException>()
              .having((e) => e.stage, 'stage', RemoteCheckStage.shares)
              .having((e) => e.message, 'fallback', contains('manually')),
        ),
      );
      await expectLater(
        remote.browseFolders(destination()),
        throwsA(
          isA<RemoteCheckException>()
              .having((e) => e.stage, 'stage', RemoteCheckStage.folder)
              .having(
                (e) => e.message,
                'redacted',
                isNot(contains('private server response')),
              ),
        ),
      );
      expect(fs.closed, isTrue);
      expect(remote.connection, isNotNull);
      expect(remote.destination, isNull);
      expect(remote.busy, isFalse);
    });
  });

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
