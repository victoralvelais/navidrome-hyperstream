import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('lens bends a translated panel edge while preserving the center and exterior', () async {
    const width = 320;
    const height = 200;
    const bounds = ui.Rect.fromLTWH(58, 57, 210, 80);
    final backgroundRecorder = ui.PictureRecorder();
    final backgroundCanvas = ui.Canvas(backgroundRecorder);
    for (var x = 0; x < width; x += 8) {
      backgroundCanvas.drawRect(
        ui.Rect.fromLTWH(x.toDouble(), 0, 8, height.toDouble()),
        ui.Paint()
          ..color = x % 16 == 0
              ? const ui.Color(0xffb77bdb)
              : const ui.Color(0xff273c76),
      );
    }
    final backgroundPicture = backgroundRecorder.endRecording();
    final background = await backgroundPicture.toImage(width, height);
    backgroundPicture.dispose();
    final program = await ui.FragmentProgram.fromAsset('shaders/glass.frag');
    final shader = program.fragmentShader()
      ..setFloat(0, width.toDouble())
      ..setFloat(1, height.toDouble())
      ..setFloat(2, bounds.left)
      ..setFloat(3, bounds.top)
      ..setFloat(4, bounds.width)
      ..setFloat(5, bounds.height)
      ..setFloat(6, 28)
      ..setFloat(7, 1)
      ..setFloat(8, 0)
      ..setImageSampler(0, background);
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawImage(background, ui.Offset.zero, ui.Paint());
    canvas.save();
    canvas.clipRRect(
      ui.RRect.fromRectAndRadius(bounds, const ui.Radius.circular(28)),
    );
    canvas.drawPaint(ui.Paint()..shader = shader);
    canvas.restore();
    final picture = recorder.endRecording();
    final result = await picture.toImage(width, height);
    picture.dispose();
    final before = (await background.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!;
    final after = (await result.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!;
    int difference(int x, int y) {
      final offset = (y * width + x) * 4;
      return List.generate(
        3,
        (i) => (before.getUint8(offset + i) - after.getUint8(offset + i)).abs(),
      ).reduce((a, b) => a + b);
    }

    // A screen-sized SDF would produce no edge changes in this inset panel.
    var warped = 0;
    for (var x = 60; x < 71; x++) {
      if (difference(x, 97) > 40) warped++;
    }
    expect(warped, greaterThan(1));
    for (var x = 100; x < 220; x++) {
      expect(difference(x, 97), lessThan(4));
      expect(difference(x, 40), lessThan(4));
    }
    if (const bool.fromEnvironment('CAPTURE_PREVIEWS')) {
      final png = (await result.toByteData(format: ui.ImageByteFormat.png))!;
      final file = File('build/previews/glass-lens.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(Uint8List.view(png.buffer));
    }
    result.dispose();
    background.dispose();
    shader.dispose();
  });
}
