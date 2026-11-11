import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperstream_client/features/player/output_button.dart';

void main() {
  testWidgets(
    'output selection waits for native success and reports disconnected devices',
    (tester) async {
      const channel = MethodChannel('dev.hyperstream/audio_outputs');
      var selected = '';
      var fail = false;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'getOutputs') {
          return [
            {'id': '', 'name': 'System default', 'selected': selected.isEmpty},
            {
              'id': 'headphones',
              'name': 'Headphones',
              'selected': selected == 'headphones',
            },
          ];
        }
        if (fail) {
          throw PlatformException(
            code: 'unavailable',
            message: 'private native details',
          );
        }
        selected = call.arguments as String;
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: AudioOutputsSheet())),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Headphones'));
      await tester.pumpAndSettle();
      expect(selected, 'headphones');
      expect(
        tester
            .widget<ListTile>(find.widgetWithText(ListTile, 'Headphones'))
            .selected,
        isTrue,
      );
      fail = true;
      await tester.tap(find.text('System default'));
      await tester.pumpAndSettle();
      expect(selected, 'headphones');
      expect(find.textContaining('may have disconnected'), findsOneWidget);
      expect(find.textContaining('private native details'), findsNothing);
    },
  );
}
