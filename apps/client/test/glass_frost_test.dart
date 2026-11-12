import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperstream_client/app_theme.dart';
import 'package:hyperstream_client/widgets/glass_surface.dart';

int _channel(ByteData data, int width, int x, int y, [int channel = 0]) =>
    data.getUint8((y * width + x) * 4 + channel);

class _Stripes extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    for (var x = 0; x < size.width; x++) {
      canvas.drawRect(
        Rect.fromLTWH(x.toDouble(), 0, 1, size.height),
        Paint()
          ..color = x.isEven
              ? const Color(0xff202020)
              : const Color(0xffe0e0e0),
      );
    }
  }

  @override
  bool shouldRepaint(_Stripes oldDelegate) => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final brightness in Brightness.values) {
    testWidgets(
      'full-panel frost blurs both its edge and center and keeps the backdrop in $brightness',
      (tester) async {
        final capture = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme: hyperstreamTheme(brightness),
            home: Scaffold(
              body: Center(
                child: RepaintBoundary(
                  key: capture,
                  child: SizedBox(
                    width: 300,
                    height: 180,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: CustomPaint(painter: _Stripes()),
                        ),
                        const Positioned(
                          left: 40,
                          top: 40,
                          width: 220,
                          height: 100,
                          child: GlassSurface(child: SizedBox.expand()),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          final boundary =
              capture.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final pixels = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          double contrast(int from, int to) {
            var total = 0;
            for (var x = from; x < to; x++) {
              total +=
                  (_channel(pixels, 300, x, 90) -
                          _channel(pixels, 300, x + 1, 90))
                      .abs();
            }
            return total / (to - from);
          }

          expect(
            contrast(110, 180),
            lessThan(10),
            reason:
                'The glass must preserve real backdrop blur, not only tint.',
          );
          expect(
            contrast(47, 54),
            lessThan(10),
            reason: 'The lighter frost must extend through the former clear edge band.',
          );
          expect(
            _channel(pixels, 300, 150, 90),
            greaterThan(brightness == Brightness.light ? 150 : 50),
            reason: 'The full panel must stay translucent instead of turning black.',
          );
          image.dispose();
        });
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
