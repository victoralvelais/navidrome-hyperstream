import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperstream_client/features/connect/connection_screen.dart';
import 'package:hyperstream_client/main.dart';
import 'package:hyperstream_client/services/account_session.dart';
import 'package:hyperstream_client/services/account_store.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('real app startup reaches sign-in with native settings and audio', (
    tester,
  ) async {
    // Use an isolated empty account key, never the user's saved connection.
    // Read native settings, but do not connect to a server or start playback.
    await tester.pumpWidget(
      HyperstreamApp(
        accountSession: AccountSession(
          store: const SecureAccountStore(
            key: 'hyperstream.integration.startup.v1',
          ),
        ),
      ),
    );
    final deadline = DateTime.now().add(const Duration(seconds: 25));
    while (find.byType(ConnectionScreen).evaluate().isEmpty &&
        DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(
      find.byType(ConnectionScreen),
      findsOneWidget,
      reason:
          'Startup did not reach sign-in. Visible text: ${tester.widgetList<Text>(find.byType(Text)).map((text) => text.data).join(' | ')}',
    );
    expect(find.text('Connect'), findsOneWidget);
    expect(tester.takeException(), isNull);
    // Leave sign-in visible for the host's screenshot. The host terminates the
    // simulator app; widget tests separately cover disposal during startup.
    binding.reportData = {'startupReachedSignIn': true};
  });
}
