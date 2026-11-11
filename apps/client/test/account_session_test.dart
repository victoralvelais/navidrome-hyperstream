import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyperstream_client/services/account_session.dart';
import 'package:hyperstream_client/services/account_store.dart';
import 'package:hyperstream_client/services/navidrome_client.dart';

import 'support/account_fakes.dart';

void main() {
  late MemoryAccountStore store;
  late AccountSession session;
  late List<AccountClient> clients;
  Object? pingError;
  Completer<void>? pingGate;
  setUp(() {
    store = MemoryAccountStore();
    clients = [];
    pingError = null;
    pingGate = null;
    session = AccountSession(
      store: store,
      createClient:
          ({required serverUrl, required username, required password}) {
            final client =
                AccountClient(
                    serverUrl: serverUrl,
                    username: username,
                    password: password,
                  )
                  ..pingError = pingError
                  ..pingGate = pingGate;
            clients.add(client);
            return client;
          },
    );
  });
  tearDown(() => session.dispose());

  SavedAccount otherAccount() => SavedAccount(
    serverUrl: 'https://second.example.com',
    username: 'other',
    password: 'synthetic-other-password',
    name: 'Second library',
  );

  test(
    'adding and switching preserve both accounts and remember the selection',
    () async {
      await session.connect(exampleAccount(), remember: true);
      final original = session.client;
      var stops = 0;
      await session.connect(
        otherAccount(),
        remember: true,
        beforeSwitch: () async {
          stops++;
        },
      );
      expect(stops, 1);
      expect(session.savedServers, hasLength(2));
      expect((original as AccountClient).closed, isTrue);
      expect(store.servers!.active!.name, 'Second library');
      await session.switchServer(
        exampleAccount().id,
        beforeSwitch: () async {
          stops++;
        },
      );
      expect(stops, 2);
      expect(session.client!.username, 'listener');
      final restored = AccountSession(
        store: store,
        createClient: AccountClient.new,
      );
      await restored.restore();
      expect(restored.savedServers, hasLength(2));
      expect(restored.client!.username, 'listener');
      restored.dispose();
    },
  );

  test('failed switch keeps the current client and saved selection', () async {
    await session.connect(exampleAccount(), remember: true);
    final original = session.client;
    pingError = const NavidromeException('Could not reach the server.');
    var stopped = false;
    await session.connect(
      otherAccount(),
      remember: true,
      beforeSwitch: () async {
        stopped = true;
      },
    );
    expect(stopped, isFalse);
    expect(session.client, same(original));
    expect(session.phase, AccountPhase.connected);
    expect(store.servers!.activeId, exampleAccount().id);
    pingError = null;
    store.saveError = const AccountStorageException('Could not save.');
    await session.connect(
      otherAccount(),
      remember: true,
      beforeSwitch: () async {},
    );
    expect(session.client, same(original));
    expect(session.savedServers, hasLength(1));
    expect((original as AccountClient).closed, isFalse);
  });

  test('disconnect removes only the active server and retained servers remain usable', () async {
    await session.connect(exampleAccount(), remember: true);
    await session.connect(otherAccount(), remember: true);
    await session.disconnect();
    expect(session.client, isNull);
    expect(session.savedServers.single.id, exampleAccount().id);
    expect(store.servers!.activeId, isNull);
    await session.switchServer(exampleAccount().id);
    expect(session.client!.username, 'listener');
  });

  test('temporary sign-in does not erase unrelated servers', () async {
    await session.connect(exampleAccount(), remember: true);
    await session.connect(otherAccount(), remember: false);
    expect(session.savedServers.single.id, exampleAccount().id);
    expect(store.servers!.activeId, isNull);
    expect(session.hasSavedAccount, isFalse);
  });

  test('unreadable vault cannot be overwritten by a new account', () async {
    store.readError = StateError('private detail');
    await session.connect(exampleAccount(), remember: true);
    expect(store.saves, 0);
    expect(session.client, isNull);
    expect(session.error, isNot(contains('private detail')));
  });

  test(
    'save only after valid authentication and restore without rewriting',
    () async {
      await session.connect(exampleAccount(), remember: true);
      expect(store.saves, 1);
      expect(session.phase, AccountPhase.connected);
      final next = AccountSession(
        store: store,
        createClient: AccountClient.new,
      );
      await next.restore();
      expect(next.client?.username, 'listener');
      expect(next.phase, AccountPhase.connected);
      expect(store.saves, 1);
      next.dispose();
    },
  );

  test('rejected sign-in does not overwrite saved credentials', () async {
    store.account = exampleAccount();
    pingError = const NavidromeException(
      'Check your username and password.',
      authenticationRejected: true,
    );
    await session.connect(
      SavedAccount(
        serverUrl: 'https://other.example.com',
        username: 'other',
        password: 'bad',
      ),
      remember: true,
    );
    expect(store.account?.username, 'listener');
    expect(store.saves, 0);
    expect(session.client, isNull);
    expect(clients.single.closed, isTrue);
  });

  test('outage keeps account and retry restores connection', () async {
    store.account = exampleAccount();
    pingError = const NavidromeException('Could not reach the server.');
    await session.restore();
    expect(session.phase, AccountPhase.recovery);
    expect(store.account, isNotNull);
    expect(store.clears, 0);
    expect(clients.single.closed, isTrue);
    pingError = null;
    await session.restore();
    expect(session.phase, AccountPhase.connected);
    expect(store.saves, 0);
  });

  test('rejected saved account requests password but preserves address and username', () async {
    store.account = exampleAccount();
    pingError = const NavidromeException(
      'Check your username and password.',
      authenticationRejected: true,
    );
    await session.restore();
    expect(session.phase, AccountPhase.signedOut);
    expect(session.username, 'listener');
    expect(session.serverUrl, exampleAccount().serverUrl);
    expect(store.account, isNotNull);
    expect(session.error, isNot(contains(exampleAccount().password)));
  });

  test(
    'unavailable storage shows recovery without erasing or exposing errors',
    () async {
      store.readError = StateError('secret-value');
      await session.restore();
      expect(session.phase, AccountPhase.recovery);
      expect(session.canEditConnection, isFalse);
      expect(session.error, isNot(contains('secret-value')));
      expect(store.clears, 0);
      store.readError = null;
      await session.restore();
      expect(session.phase, AccountPhase.signedOut);
    },
  );

  test('failed persistence never reports successful sign-in', () async {
    store.saveError = const AccountStorageException(
      'Could not securely save your account.',
    );
    await session.connect(exampleAccount(), remember: true);
    expect(session.client, isNull);
    expect(session.phase, AccountPhase.signedOut);
    expect(session.error, contains('save'));
    expect(clients.single.closed, isTrue);
  });

  test('temporary session clears older saved account', () async {
    store.account = exampleAccount();
    await session.connect(exampleAccount(), remember: false);
    expect(store.account, isNull);
    expect(store.saves, 0);
    expect(session.phase, AccountPhase.connected);
  });

  test('failed delete keeps session available for retry', () async {
    await session.connect(exampleAccount(), remember: true);
    store.clearError = const AccountStorageException(
      'Could not remove saved account.',
    );
    await expectLater(
      session.disconnect(),
      throwsA(isA<AccountStorageException>()),
    );
    expect(session.phase, AccountPhase.connected);
    expect(session.busy, isFalse);
    expect(session.client, isNotNull);
    expect(store.account, isNotNull);
    store.clearError = null;
    await session.disconnect();
    expect(store.account, isNull);
    expect(session.client, isNull);
    expect(clients.single.closed, isTrue);
  });

  test('serializes sign-in until storage write completes', () async {
    store.saveGate = Completer<void>();
    final pending = session.connect(exampleAccount(), remember: true);
    await Future<void>.delayed(Duration.zero);
    expect(session.busy, isTrue);
    await session.connect(exampleAccount(), remember: false);
    await session.disconnect();
    expect(store.clears, 0);
    expect(clients, hasLength(1));
    store.saveGate!.complete();
    await pending;
    expect(session.phase, AccountPhase.connected);
  });

  test('dispose during ping closes candidate and never saves', () async {
    pingGate = Completer<void>();
    final pending = session.connect(exampleAccount(), remember: true);
    session.dispose();
    // Replace the test-owned session so tearDown does not dispose twice.
    session = AccountSession(store: store);
    pingGate!.complete();
    await pending;
    expect(store.saves, 0);
    expect(clients.single.closed, isTrue);
  });
}
