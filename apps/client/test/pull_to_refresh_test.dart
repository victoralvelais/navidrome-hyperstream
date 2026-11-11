import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperstream_client/widgets/pull_to_refresh.dart';

void main() {
  testWidgets('empty lists refresh by drag and F5 after focus', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PullToRefresh(
            onRefresh: () async {
              calls++;
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [ListTile(title: Text('Empty library'))],
            ),
          ),
        ),
      ),
    );
    await tester.drag(find.byType(ListView), const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(calls, 1);
    await tester.tap(find.text('Empty library'));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.f5);
    await tester.pumpAndSettle();
    expect(calls, 2);
  });
}
