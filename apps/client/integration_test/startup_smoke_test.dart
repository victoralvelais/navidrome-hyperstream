import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperstream_client/features/connect/connection_screen.dart';
import 'package:hyperstream_client/main.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('real app startup reaches sign-in with native settings and audio', (
    tester,
  ) async {
    // Read the same non-secret settings as the app; do not write preferences,
    // connect to a server, or start playback.
    await tester.pumpWidget(const HyperstreamApp());
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
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 500));
  });
}
