import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'navidrome_client.dart';

/// The whole account is a single protected record; preferences contain no secrets.
class SavedAccount {
  SavedAccount({
    required String serverUrl,
    required String username,
    required this.password,
  }) : serverUrl = NavidromeClient.parseServerUrl(serverUrl).toString(),
       username = username.trim() {
    if (this.username.isEmpty || password.isEmpty) {
      throw const FormatException('Incomplete account.');
    }
  }

  final String serverUrl;
  final String username;
  final String password;

  String encode() => jsonEncode({
    'schema': 1,
    'serverUrl': serverUrl,
    'username': username,
    'password': password,
  });

  factory SavedAccount.decode(String value) {
    final record = jsonDecode(value) as Map<String, dynamic>;
    if (record['schema'] != 1) throw const FormatException('Unknown account.');
    return SavedAccount(
      serverUrl: record['serverUrl'] as String,
      username: record['username'] as String,
      password: record['password'] as String,
    );
  }

  @override
  String toString() => 'SavedAccount(redacted)';
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
  Future<SavedAccount?> read() async {
    try {
      final value = await storage
          .read(key: key)
          .timeout(const Duration(seconds: 10));
      return value == null ? null : SavedAccount.decode(value);
    } on Object {
      // A locked/unavailable store is not an empty store. Never erase on failure.
      throw const AccountStorageException(
        'Could not read your saved account. Unlock your device and try again.',
      );
    }
  }

  @override
  Future<void> save(SavedAccount account) async {
    try {
      final value = account.encode();
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
