import 'dart:async';

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
  SavedServers _servers = SavedServers();
  List<SavedAccount> get savedServers => _servers.accounts;
  String? get activeServerId => _client == null ? _servers.activeId : _activeId;
  String? _activeId;
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
  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;
  bool _checkingRecovery = false;
  bool _canAutoReconnect = false;
  bool get canEditConnection => _storageReadable;
  bool get busy =>
      _forgetting ||
      _checkingRecovery ||
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

  Future<void> restore({bool automatic = false}) async {
    if (busy || _disposed || _client != null) return;
    _reconnectTimer?.cancel();
    if (!automatic) _reconnectAttempt = 0;
    _canAutoReconnect = false;
    _checkingRecovery = automatic;
    if (!automatic) {
      phase = AccountPhase.restoring;
      error = null;
    }
    _changed();
    NavidromeClient? candidate;
    try {
      _servers = await store.readServers();
      final account = _servers.active;
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
      _activeId = account.id;
      candidate = null;
      phase = AccountPhase.connected;
    } on NavidromeException catch (failure) {
      if (_disposed) return;
      _canAutoReconnect = !failure.authenticationRejected;
      phase = failure.authenticationRejected
          ? AccountPhase.signedOut
          : AccountPhase.recovery;
      error = failure.authenticationRejected
          ? 'Your saved sign-in was rejected. Enter your password again.'
          : '${failure.message} Retrying automatically. Your saved account is still on this device.';
    } on Object {
      _storageReadable = false;
      phase = AccountPhase.recovery;
      error = 'Could not read your saved account. Unlock your device and try again.';
    } finally {
      candidate?.close();
      _checkingRecovery = false;
      if (!_disposed && _canAutoReconnect && phase == AccountPhase.recovery) {
        final seconds = [2, 5, 10, 20, 30][_reconnectAttempt.clamp(0, 4)];
        _reconnectAttempt++;
        _reconnectTimer = Timer(Duration(seconds: seconds), retryConnectionNow);
      }
      _changed();
    }
  }

  /// Also called on foreground return, since iOS may suspend retry timers.
  void retryConnectionNow() {
    if (_canAutoReconnect &&
        phase == AccountPhase.recovery &&
        !busy &&
        !_disposed) {
      unawaited(restore(automatic: true));
    }
  }

  void _cancelReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempt = 0;
    _canAutoReconnect = false;
  }

  void editConnection() {
    if (busy || !_storageReadable || _disposed) return;
    _cancelReconnect();
    phase = AccountPhase.signedOut;
    error = null;
    _changed();
  }

  Future<void> connect(
    SavedAccount account, {
    required bool remember,
    Future<void> Function()? beforeSwitch,
  }) async {
    if (busy || _disposed) return;
    _cancelReconnect();
    phase = AccountPhase.connecting;
    error = null;
    _changed();
    NavidromeClient? candidate;
    try {
      candidate = _open(account);
      await candidate.ping();
      if (_disposed) return;
      // Read first even for a fresh sign-in so an unreadable vault cannot be
      // overwritten, and adding a server never loses other saved connections.
      final previous = await store.readServers();
      final next = SavedServers(
        accounts: [
          ...previous.accounts.where((a) => a.id != account.id),
          if (remember) account,
        ],
        activeId: remember ? account.id : null,
      );
      if (_disposed) return;
      if (_client != null) await beforeSwitch?.call();
      if (_disposed) return;
      await store.saveServers(next);
      if (_disposed) return;
      final old = _client;
      _client = candidate;
      candidate = null;
      _servers = next;
      _activeId = account.id;
      old?.close();
      serverUrl = account.serverUrl;
      username = account.username;
      hasSavedAccount = remember;
      _storageReadable = true;
      phase = AccountPhase.connected;
    } on NavidromeException catch (failure) {
      error = failure.message;
      phase = _client == null ? AccountPhase.signedOut : AccountPhase.connected;
    } on AccountStorageException catch (failure) {
      error = failure.message;
      phase = _client == null ? AccountPhase.signedOut : AccountPhase.connected;
    } on Object {
      error = 'Could not finish signing in. Please try again.';
      phase = _client == null ? AccountPhase.signedOut : AccountPhase.connected;
    } finally {
      candidate?.close();
      _changed();
    }
  }

  Future<void> switchServer(
    String id, {
    Future<void> Function()? beforeSwitch,
  }) async {
    if (id == _activeId && _client != null) return;
    final account = _servers.accounts.where((a) => a.id == id).firstOrNull;
    if (account != null) {
      await connect(account, remember: true, beforeSwitch: beforeSwitch);
    }
  }

  Future<void> removeServer(String id) async {
    if (busy || _disposed || (id == activeServerId && _client != null)) return;
    _cancelReconnect();
    _forgetting = true;
    _changed();
    try {
      final next = SavedServers(
        accounts: _servers.accounts.where((a) => a.id != id).toList(),
        activeId: _servers.activeId == id ? null : _servers.activeId,
      );
      await store.saveServers(next);
      _servers = next;
    } finally {
      _forgetting = false;
      _changed();
    }
  }

  Future<void> disconnect() async {
    if (busy || _disposed) return;
    _cancelReconnect();
    _forgetting = true;
    _changed();
    try {
      final current = await store.readServers();
      final id = activeServerId;
      final next = SavedServers(
        accounts: current.accounts.where((a) => a.id != id).toList(),
      );
      await store.saveServers(next);
      _servers = next;
      _client?.close();
      _client = null;
      _activeId = null;
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
    _cancelReconnect();
    _client?.close();
    _client = null;
    super.dispose();
  }
}
