import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperstream_client/features/search/online_search_toggle.dart';
import 'package:hyperstream_client/services/music_sources.dart';

void main() {
  testWidgets(
    'keyboard and secondary click expose the source menu without toggling',
    (tester) async {
      final sources = MusicSources()..enabled = true;
      addTearDown(sources.dispose);
      var enabled = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => Align(
                alignment: Alignment.topRight,
                child: OnlineSearchToggle(
                  enabled: enabled,
                  sources: sources,
                  onChanged: (value) => setState(() => enabled = value),
                ),
              ),
            ),
          ),
        ),
      );
      final toggle = find.byType(OnlineSearchToggle);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(enabled, true);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.f10);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('online-source-monochrome')),
        findsOneWidget,
      );
      expect(enabled, true);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.tap(
        toggle,
        buttons: kSecondaryMouseButton,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('online-source-monochrome')),
        findsOneWidget,
      );
      expect(enabled, true);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    },
  );
}
