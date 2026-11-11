import 'dart:async';

import 'package:hyperstream_client/models/library.dart';
import 'package:hyperstream_client/services/account_store.dart';
import 'package:hyperstream_client/services/navidrome_client.dart';

SavedAccount exampleAccount() => SavedAccount(
  serverUrl: 'https://music.example.com/navidrome',
  username: 'listener',
  password: 'synthetic-test-password',
);

class MemoryAccountStore implements AccountStore {
  SavedAccount? account;
  SavedServers? servers;
  Object? readError;
  Object? saveError;
  Object? clearError;
  int saves = 0;
  int clears = 0;
  Completer<void>? saveGate;

  @override
  Future<SavedServers> readServers() async {
    final active = await read();
    return servers ??
        SavedServers(
          accounts: active == null ? [] : [active],
          activeId: active?.id,
        );
  }

  @override
  Future<void> saveServers(SavedServers value) async {
    if (value.accounts.isEmpty) {
      await clear();
    } else {
      await save(value.active ?? value.accounts.first);
      account = value.active;
    }
    servers = value;
  }

  @override
  Future<SavedAccount?> read() async {
    if (readError != null) throw readError!;
    return account;
  }

  @override
  Future<void> save(SavedAccount value) async {
    saves++;
    if (saveGate != null) await saveGate!.future;
    if (saveError != null) throw saveError!;
    account = value;
  }

  @override
  Future<void> clear() async {
    clears++;
    if (clearError != null) throw clearError!;
    account = null;
  }
}

class AccountClient extends NavidromeClient {
  AccountClient({
    required super.serverUrl,
    required super.username,
    required super.password,
  });
  Object? pingError;
  Completer<void>? pingGate;
  bool closed = false;
  int pings = 0;
  @override
  Future<void> ping() async {
    pings++;
    if (pingGate != null) await pingGate!.future;
    if (pingError != null) throw pingError!;
  }

  @override
  Future<List<Album>> albums({
    int offset = 0,
    int size = 40,
    bool recent = false,
  }) async => [];
  @override
  void close() {
    closed = true;
    super.close();
  }
}
