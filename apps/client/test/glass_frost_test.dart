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

  test(
    'rounded frost mask fades continuously across the former inset boundary',
    () async {
      final program = await ui.FragmentProgram.fromAsset(
        'shaders/glass_frost.frag',
      );
      for (final size in [const Size(220, 100), const Size(44, 44)]) {
        final shader = program.fragmentShader()
          ..setFloat(0, size.width)
          ..setFloat(1, size.height)
          ..setFloat(2, 28)
          ..setFloat(3, 20);
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawRect(Offset.zero & size, Paint()..shader = shader);
        final picture = recorder.endRecording();
        final image = await picture.toImage(
          size.width.toInt(),
          size.height.toInt(),
        );
        final pixels = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        final width = size.width.toInt();
        final y = size.height ~/ 2;
        expect(_channel(pixels, width, 0, 0, 3), 0);
        expect(_channel(pixels, width, 0, y, 3), lessThan(3));
        expect(_channel(pixels, width, width ~/ 2, y, 3), 255);
        for (var x = 1; x < 20; x++) {
          final delta =
              _channel(pixels, width, x, y, 3) -
              _channel(pixels, width, x - 1, y, 3);
          expect(
            delta,
            inInclusiveRange(0, 24),
            reason: 'No hard inner frost edge at x=$x.',
          );
        }
        image.dispose();
        picture.dispose();
        shader.dispose();
      }
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'masked glass blurs its center, retains edge detail, and keeps the backdrop in $brightness',
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
        await tester.runAsync(
          () => ui.FragmentProgram.fromAsset('shaders/glass_frost.frag'),
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
            reason: 'The mask must preserve real backdrop blur, not only tint.',
          );
          expect(contrast(47, 54), greaterThan(contrast(110, 180) + 30));
          expect(
            _channel(pixels, 300, 150, 90),
            greaterThan(brightness == Brightness.light ? 150 : 50),
            reason: 'The backdrop must survive the mask save layer instead of turning black.',
          );
          image.dispose();
        });
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
