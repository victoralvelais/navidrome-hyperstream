import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'navidrome_client.dart';

/// The whole account is a single protected record; preferences contain no secrets.
class SavedAccount {
  SavedAccount({
    required String serverUrl,
    required String username,
    required this.password,
    this.name = '',
  }) : serverUrl = NavidromeClient.parseServerUrl(serverUrl).toString(),
       username = username.trim() {
    if (this.username.isEmpty || password.isEmpty) {
      throw const FormatException('Incomplete account.');
    }
  }

  final String serverUrl;
  final String username;
  final String password;
  final String name;
  String get id => jsonEncode([serverUrl, username]);
  String get displayName =>
      name.trim().isEmpty ? Uri.parse(serverUrl).host : name.trim();

  String encode() => jsonEncode({
    'schema': 1,
    'serverUrl': serverUrl,
    'username': username,
    'password': password,
    'name': name,
  });

  factory SavedAccount.decode(String value) {
    final record = jsonDecode(value) as Map<String, dynamic>;
    if (record['schema'] != 1) throw const FormatException('Unknown account.');
    return SavedAccount(
      serverUrl: record['serverUrl'] as String,
      username: record['username'] as String,
      password: record['password'] as String,
      name: record['name'] as String? ?? '',
    );
  }

  @override
  String toString() => 'SavedAccount(redacted)';
}

/// One encrypted record makes the selected server and its credentials consistent.
/// The original single-account record is migrated in place on the next write.
class SavedServers {
  SavedServers({List<SavedAccount> accounts = const [], this.activeId})
    : accounts = List.unmodifiable(accounts) {
    if (accounts.map((a) => a.id).toSet().length != accounts.length ||
        (activeId != null && !accounts.any((a) => a.id == activeId))) {
      throw const FormatException('Invalid saved servers.');
    }
  }
  final List<SavedAccount> accounts;
  final String? activeId;
  SavedAccount? get active =>
      accounts.where((a) => a.id == activeId).firstOrNull;
  String encode() => jsonEncode({
    'schema': 2,
    'activeId': activeId,
    'accounts': accounts.map((a) => jsonDecode(a.encode())).toList(),
  });
  factory SavedServers.decode(String value) {
    final record = jsonDecode(value) as Map<String, dynamic>;
    if (record['schema'] == 1) {
      final account = SavedAccount.decode(value);
      return SavedServers(accounts: [account], activeId: account.id);
    }
    if (record['schema'] != 2) throw const FormatException('Unknown servers.');
    return SavedServers(
      accounts: (record['accounts'] as List)
          .map((a) => SavedAccount.decode(jsonEncode(a)))
          .toList(),
      activeId: record['activeId'] as String?,
    );
  }
  @override
  String toString() => 'SavedServers(redacted)';
}

class AccountStorageException implements Exception {
  const AccountStorageException(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract interface class AccountStore {
  Future<SavedAccount?> read();
  Future<void> save(SavedAccount account);
  Future<void> clear();
  Future<SavedServers> readServers();
  Future<void> saveServers(SavedServers servers);
}

class SecureAccountStore implements AccountStore {
  const SecureAccountStore({
    this.storage = defaultStorage,
    this.key = accountKey,
  });

  static const accountKey = 'hyperstream.navidrome.account.v1';
  static const defaultStorage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accountName: 'dev.hyperstream.navidrome',
      accessibility: KeychainAccessibility.first_unlock_this_device,
      synchronizable: false,
    ),
  );
  final FlutterSecureStorage storage;
  final String key;

  @override
  Future<SavedAccount?> read() async => (await readServers()).active;

  @override
  Future<SavedServers> readServers() async {
    try {
      final value = await storage
          .read(key: key)
          .timeout(const Duration(seconds: 10));
      return value == null ? SavedServers() : SavedServers.decode(value);
    } on Object {
      // A locked/unavailable store is not an empty store. Never erase on failure.
      throw const AccountStorageException(
        'Could not read your saved account. Unlock your device and try again.',
      );
    }
  }

  @override
  Future<void> save(SavedAccount account) =>
      saveServers(SavedServers(accounts: [account], activeId: account.id));

  @override
  Future<void> saveServers(SavedServers servers) async {
    if (servers.accounts.isEmpty) return clear();
    try {
      final value = servers.encode();
      // Do not time out mutations: they cannot be cancelled and could finish
      // after a later sign-out. Keep the session busy until completion.
      await storage.write(key: key, value: value);
      if (await storage.read(key: key) != value) {
        throw const AccountStorageException('Verification failed.');
      }
    } on Object {
      throw const AccountStorageException(
        'Connected to Navidrome, but could not securely save your account. '
        'Try again, or turn off Keep me signed in.',
      );
    }
  }

  @override
  Future<void> clear() async {
    try {
      await storage.delete(key: key);
      if (await storage.read(key: key) != null) {
        throw const AccountStorageException('Verification failed.');
      }
    } on Object {
      throw const AccountStorageException(
        'Could not remove your saved account. Please try again before leaving the app.',
      );
    }
  }
}
