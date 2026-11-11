import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperstream_client/services/account_store.dart';

import 'support/account_fakes.dart';

class ObservedStorage extends FlutterSecureStorage {
  String? value;
  Object? failure;
  bool dropWrites = false;
  bool dropDeletes = false;
  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (failure != null) throw failure!;
    return value;
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (failure != null) throw failure!;
    if (!dropWrites) this.value = value;
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (failure != null) throw failure!;
    if (!dropDeletes) value = null;
  }
}

void main() {
  test(
    'legacy login migrates in place and multiple credentials roundtrip',
    () async {
      final legacy = exampleAccount();
      final storage = ObservedStorage()..value = legacy.encode();
      final store = SecureAccountStore(storage: storage);
      final restored = await store.readServers();
      expect(restored.active!.password, legacy.password);
      expect(storage.value, legacy.encode());
      final second = SavedAccount(
        serverUrl: 'https://second.example.com',
        username: 'test',
        password: 'private',
        name: 'Second',
      );
      await store.saveServers(
        SavedServers(accounts: [legacy, second], activeId: second.id),
      );
      final all = await store.readServers();
      expect(all.accounts, hasLength(2));
      expect(all.active!.name, 'Second');
      expect(all.accounts.first.password, legacy.password);
      expect(all.toString(), isNot(contains('private')));
    },
  );
  test(
    'roundtrip normalizes address and username without changing password',
    () async {
      final storage = ObservedStorage();
      final store = SecureAccountStore(storage: storage);
      expect(await store.read(), isNull);
      final account = SavedAccount(
        serverUrl: ' https://music.example.com/sub ',
        username: ' listener ',
        password: ' p@ss ',
      );
      await store.save(account);
      final restored = await store.read();
      expect(restored?.serverUrl, 'https://music.example.com/sub/');
      expect(restored?.username, 'listener');
      expect(restored?.password, ' p@ss ');
      expect(account.toString(), isNot(contains('p@ss')));
      await store.clear();
      expect(await store.read(), isNull);
    },
  );

  test(
    'corrupt records and platform errors are sanitized and not erased',
    () async {
      final storage = ObservedStorage()..value = '{private-invalid-json';
      final store = SecureAccountStore(storage: storage);
      await expectLater(
        store.read(),
        throwsA(
          isA<AccountStorageException>().having(
            (e) => e.toString(),
            'sanitized',
            isNot(contains('private-invalid-json')),
          ),
        ),
      );
      expect(storage.value, isNotNull);
      storage.failure = PlatformException(
        code: 'native',
        message: 'private-native-details',
      );
      await expectLater(
        store.read(),
        throwsA(
          isA<AccountStorageException>().having(
            (e) => e.toString(),
            'sanitized',
            isNot(contains('private-native-details')),
          ),
        ),
      );
    },
  );

  test(
    'detects writes and deletes silently ignored by native storage',
    () async {
      final storage = ObservedStorage()..dropWrites = true;
      final store = SecureAccountStore(storage: storage);
      await expectLater(
        store.save(exampleAccount()),
        throwsA(isA<AccountStorageException>()),
      );
      storage.dropWrites = false;
      await store.save(exampleAccount());
      storage.dropDeletes = true;
      await expectLater(store.clear(), throwsA(isA<AccountStorageException>()));
    },
  );

  test('Apple records stay on device and remain usable after first unlock', () {
    final options = SecureAccountStore.defaultStorage.iOptions;
    expect(options.synchronizable, isFalse);
    expect(
      options.accessibility,
      KeychainAccessibility.first_unlock_this_device,
    );
    expect(options.groupId, isNull);
  });
}
