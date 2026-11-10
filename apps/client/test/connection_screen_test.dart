import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hyperstream_client/features/connect/connection_screen.dart';
import 'package:hyperstream_client/services/navidrome_client.dart';

void main() {
  testWidgets(
    'requires a valid address and credentials before contacting server',
    (tester) async {
      var contacted = false;
      await tester.pumpWidget(
        MaterialApp(
          home: ConnectionScreen(onConnected: (_) => contacted = true),
        ),
      );
      await tester.tap(find.text('Connect'));
      await tester.pump();
      expect(find.text('Enter your username.'), findsOneWidget);
      expect(find.text('Enter your password.'), findsOneWidget);
      expect(contacted, isFalse);
    },
  );

  testWidgets('failed authentication can be corrected and retried', (
    tester,
  ) async {
    NavidromeClient? connected;
    var attempts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ConnectionScreen(
          onConnected: (client) => connected = client,
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
        ),
      ),
    );
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'https://music.example.com');
    await tester.enterText(fields.at(1), 'listener');
    await tester.enterText(fields.at(2), 'wrong');
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(find.text('Check your username and password.'), findsOneWidget);
    expect(connected, isNull);
    await tester.enterText(fields.at(2), 'corrected');
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(connected, isNotNull);
    expect(attempts, 2);
    expect(find.text('corrected'), findsNothing);
    connected?.close();
  });
}
