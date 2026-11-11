import 'package:flutter/foundation.dart';

import 'account_store.dart';
import 'navidrome_client.dart';

typedef ClientFactory = NavidromeClient Function({
  required String serverUrl,
  required String username,
  required String password,
});

enum AccountPhase { signedOut, restoring, connecting, recovery, connected }

/// Owns the authenticated client. Network failures never remove saved accounts.
class AccountSession extends ChangeNotifier {
  AccountSession({
    this.store = const SecureAccountStore(),
    this.createClient = NavidromeClient.new,
  });

  final AccountStore store;
  final ClientFactory createClient;
  AccountPhase phase = AccountPhase.signedOut;
  NavidromeClient? _client;
  NavidromeClient? get client => _client;
  String? serverUrl;
  String? username;
  String? error;
  bool _storageReadable = false;
  bool hasSavedAccount = false;
  bool _disposed = false;
  bool _forgetting = false;
  bool get canEditConnection => _storageReadable;
  bool get busy =>
      _forgetting ||
      phase == AccountPhase.restoring ||
      phase == AccountPhase.connecting;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  NavidromeClient _open(SavedAccount account) => createClient(
    serverUrl: account.serverUrl,
    username: account.username,
    password: account.password,
  );

  Future<void> restore() async {
    if (busy || _disposed || _client != null) return;
    phase = AccountPhase.restoring;
    error = null;
    _changed();
    NavidromeClient? candidate;
    try {
      final account = await store.read();
      if (_disposed) return;
      _storageReadable = true;
      hasSavedAccount = account != null;
      if (account == null) {
        phase = AccountPhase.signedOut;
        return;
      }
      serverUrl = account.serverUrl;
      username = account.username;
      candidate = _open(account);
      await candidate.ping();
      if (_disposed) return;
      _client = candidate;
      candidate = null;
      phase = AccountPhase.connected;
    } on NavidromeException catch (failure) {
      phase = failure.authenticationRejected
          ? AccountPhase.signedOut
          : AccountPhase.recovery;
      error = failure.authenticationRejected
          ? 'Your saved sign-in was rejected. Enter your password again.'
          : '${failure.message} Your saved account is still on this device.';
    } on Object {
      _storageReadable = false;
      phase = AccountPhase.recovery;
      error = 'Could not read your saved account. Unlock your device and try again.';
    } finally {
      candidate?.close();
      _changed();
    }
  }

  void editConnection() {
    if (busy || !_storageReadable || _disposed) return;
    phase = AccountPhase.signedOut;
    error = null;
    _changed();
  }

  Future<void> connect(SavedAccount account, {required bool remember}) async {
    if (busy || _disposed || _client != null) return;
    phase = AccountPhase.connecting;
    error = null;
    _changed();
    NavidromeClient? candidate;
    try {
      candidate = _open(account);
      await candidate.ping();
      if (_disposed) return;
      if (remember) {
        await store.save(account);
      } else {
        // A temporary sign-in must not leave an older account set to restore.
        await store.clear();
      }
      if (_disposed) return;
      _client = candidate;
      candidate = null;
      serverUrl = account.serverUrl;
      username = account.username;
      hasSavedAccount = remember;
      _storageReadable = true;
      phase = AccountPhase.connected;
    } on NavidromeException catch (failure) {
      error = failure.message;
      phase = AccountPhase.signedOut;
    } on AccountStorageException catch (failure) {
      error = failure.message;
      phase = AccountPhase.signedOut;
    } on Object {
      error = 'Could not finish signing in. Please try again.';
      phase = AccountPhase.signedOut;
    } finally {
      candidate?.close();
      _changed();
    }
  }

  Future<void> disconnect() async {
    if (busy || _disposed) return;
    _forgetting = true;
    _changed();
    try {
      await store.clear();
      _client?.close();
      _client = null;
      serverUrl = null;
      username = null;
      hasSavedAccount = false;
      error = null;
      _storageReadable = true;
      phase = AccountPhase.signedOut;
    } finally {
      _forgetting = false;
      _changed();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _client?.close();
    _client = null;
    super.dispose();
  }
}
