import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperstream_client/widgets/hyperstream_mark.dart';

void main() {
  testWidgets('launch mark stays square inside a stretched sign-in column', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 340,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [HyperstreamMark(), Text('Hyperstream')],
            ),
          ),
        ),
      ),
    );
    final canvas = find.descendant(
      of: find.byType(HyperstreamMark),
      matching: find.byType(CustomPaint),
    );
    expect(tester.getSize(canvas), const Size.square(72));
    expect(tester.getCenter(canvas).dx, 170);
  });
}
