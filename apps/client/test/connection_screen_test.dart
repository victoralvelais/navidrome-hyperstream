import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hyperstream_client/features/connect/connection_screen.dart';
import 'package:hyperstream_client/services/navidrome_client.dart';
import 'package:hyperstream_client/services/account_session.dart';

import 'support/account_fakes.dart';

void main() {
  testWidgets(
    'requires a valid address and credentials before contacting server',
    (tester) async {
      final session = AccountSession(store: MemoryAccountStore());
      addTearDown(session.dispose);
      await tester.pumpWidget(
        MaterialApp(home: ConnectionScreen(session: session)),
      );
      await tester.ensureVisible(find.text('Connect'));
      await tester.tap(find.text('Connect'));
      await tester.pump();
      expect(find.text('Enter your username.'), findsOneWidget);
      expect(find.text('Enter your password.'), findsOneWidget);
      expect(session.client, isNull);
    },
  );

  testWidgets('failed authentication can be corrected and retried', (
    tester,
  ) async {
    var attempts = 0;
    final store = MemoryAccountStore();
    final session = AccountSession(
      store: store,
      createClient:
          ({required serverUrl, required username, required password}) =>
              NavidromeClient(
                serverUrl: serverUrl,
                username: username,
                password: password,
                httpClient: MockClient((_) async {
                  attempts++;
                  return http.Response(
                    jsonEncode({
                      'subsonic-response': attempts == 1
                          ? {
                              'status': 'failed',
                              'error': {'code': 40},
                            }
                          : {'status': 'ok'},
                    }),
                    200,
                  );
                }),
              ),
    );
    addTearDown(session.dispose);
    await tester.pumpWidget(
      MaterialApp(home: ConnectionScreen(session: session)),
    );
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'https://music.example.com');
    await tester.enterText(fields.at(1), 'listener');
    await tester.enterText(fields.at(2), 'wrong');
    await tester.ensureVisible(find.text('Connect'));
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(find.text('Check your username and password.'), findsOneWidget);
    expect(session.client, isNull);
    expect(store.saves, 0);
    await tester.enterText(fields.at(2), 'corrected');
    await tester.ensureVisible(find.text('Connect'));
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(session.client, isNotNull);
    expect(store.account?.password, 'corrected');
    expect(attempts, 2);
    expect(find.text('corrected'), findsNothing);
  });

  testWidgets('outage offers retry without asking for the password again', (
    tester,
  ) async {
    final store = MemoryAccountStore()..account = exampleAccount();
    var offline = true;
    final session = AccountSession(
      store: store,
      createClient:
          ({required serverUrl, required username, required password}) =>
              AccountClient(
                  serverUrl: serverUrl,
                  username: username,
                  password: password,
                )
                ..pingError = offline
                    ? const NavidromeException('Could not reach the server.')
                    : null,
    );
    addTearDown(session.dispose);
    await session.restore();
    await tester.pumpWidget(
      MaterialApp(home: ConnectionScreen(session: session)),
    );
    expect(find.text('Retry connection'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.textContaining(exampleAccount().password), findsNothing);
    offline = false;
    await tester.tap(find.text('Retry connection'));
    await tester.pumpAndSettle();
    expect(session.client, isNotNull);
    expect(store.clears, 0);
  });

  testWidgets(
    'rejected saved password is never prefilled and can be forgotten',
    (tester) async {
      final store = MemoryAccountStore()..account = exampleAccount();
      final session = AccountSession(
        store: store,
        createClient:
            ({required serverUrl, required username, required password}) =>
                AccountClient(
                    serverUrl: serverUrl,
                    username: username,
                    password: password,
                  )
                  ..pingError = const NavidromeException(
                    'Rejected',
                    authenticationRejected: true,
                  ),
      );
      addTearDown(session.dispose);
      await session.restore();
      await tester.pumpWidget(
        MaterialApp(home: ConnectionScreen(session: session)),
      );
      final fields = tester
          .widgetList<TextFormField>(find.byType(TextFormField))
          .toList();
      expect(fields[0].controller!.text, exampleAccount().serverUrl);
      expect(fields[1].controller!.text, 'listener');
      expect(fields[2].controller!.text, isEmpty);
      await tester.ensureVisible(find.text('Forget saved account'));
      await tester.tap(find.text('Forget saved account'));
      await tester.pumpAndSettle();
      expect(store.account, isNull);
      expect(find.text('Forget saved account'), findsNothing);
      expect(
        tester
            .widgetList<TextFormField>(find.byType(TextFormField))
            .elementAt(1)
            .controller!
            .text,
        isEmpty,
      );
    },
  );

  testWidgets('turning off keep signed in creates a session without saving', (
    tester,
  ) async {
    final store = MemoryAccountStore();
    final session = AccountSession(
      store: store,
      createClient: AccountClient.new,
    );
    addTearDown(session.dispose);
    await tester.pumpWidget(
      MaterialApp(home: ConnectionScreen(session: session)),
    );
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'https://music.example.com');
    await tester.enterText(fields.at(1), 'listener');
    await tester.enterText(fields.at(2), 'temporary-password');
    await tester.ensureVisible(find.text('Keep me signed in'));
    await tester.tap(find.text('Keep me signed in'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Connect'));
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(session.client, isNotNull);
    expect(store.saves, 0);
    expect(store.account, isNull);
  });
}
