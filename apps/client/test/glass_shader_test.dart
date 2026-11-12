import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

const _width = 320;
const _height = 200;
const _bounds = ui.Rect.fromLTWH(58, 57, 210, 80);
final _shape = ui.RRect.fromRectAndRadius(
  _bounds,
  const ui.Radius.circular(28),
);

Future<ui.Image> _background(void Function(ui.Canvas) paint) async {
  final recorder = ui.PictureRecorder();
  paint(ui.Canvas(recorder));
  final picture = recorder.endRecording();
  final result = await picture.toImage(_width, _height);
  picture.dispose();
  return result;
}

Future<ui.Image> _filter(ui.Image input, {double softness = 0}) async {
  final program = await ui.FragmentProgram.fromAsset('shaders/glass.frag');
  final shader = program.fragmentShader()
    ..setFloat(0, _width.toDouble())
    ..setFloat(1, _height.toDouble())
    ..setFloat(2, _bounds.left)
    ..setFloat(3, _bounds.top)
    ..setFloat(4, _bounds.width)
    ..setFloat(5, _bounds.height)
    ..setFloat(6, 28)
    ..setFloat(7, 1)
    ..setFloat(8, softness)
    ..setImageSampler(0, input);
  // Intentionally no Canvas.clipRRect: the filter itself must preserve every
  // exterior pixel, including the cutouts at the rounded corners.
  final result = await _background(
    (canvas) => canvas.drawPaint(ui.Paint()..shader = shader),
  );
  shader.dispose();
  return result;
}

Future<ByteData> _pixels(ui.Image image) async =>
    (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;

int _channel(ByteData data, int x, int y, [int channel = 0]) =>
    data.getUint8((y * _width + x) * 4 + channel);

Future<void> _preview(ui.Image image, String name) async {
  if (!const bool.fromEnvironment('CAPTURE_PREVIEWS')) return;
  final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
  final file = File('build/previews/$name.png');
  await file.parent.create(recursive: true);
  await file.writeAsBytes(
    png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('translated lens refracts only its narrow rim and leaves every exterior pixel intact', () async {
    final background = await _background((canvas) {
      for (var x = 0; x < _width; x += 4) {
        canvas.drawRect(
          ui.Rect.fromLTWH(x.toDouble(), 0, 4, _height.toDouble()),
          ui.Paint()
            ..color = x % 8 == 0
                ? const ui.Color(0xffb77bdb)
                : const ui.Color(0xff273c76),
        );
      }
    });
    final result = await _filter(background);
    final before = await _pixels(background);
    final after = await _pixels(result);
    int difference(int x, int y) => List.generate(
      3,
      (i) => (_channel(before, x, y, i) - _channel(after, x, y, i)).abs(),
    ).reduce((a, b) => a + b);
    var warped = 0;
    for (var x = 59; x < 66; x++) {
      if (difference(x, 97) > 40) warped++;
    }
    expect(warped, greaterThan(0));
    // The slightly wider ten-point rim still leaves the center unwarped.
    for (var x = 69; x < 257; x++) {
      expect(difference(x, 97), lessThan(4));
    }
    var outsideChanges = 0;
    for (var y = 0; y < _height; y++) {
      for (var x = 0; x < _width; x++) {
        if (!_shape.contains(ui.Offset(x + .5, y + .5)) &&
            difference(x, y) >= 4) {
          outsideChanges++;
        }
      }
    }
    expect(
      outsideChanges,
      0,
      reason: 'Refraction must not escape the panel or its rounded corners.',
    );
    await _preview(result, 'glass-lens');
    result.dispose();
    background.dispose();
  });

  test('frost and lens taps do not pull adjacent content across any rounded border', () async {
    final background = await _background((canvas) {
      canvas.drawPaint(ui.Paint()..color = const ui.Color(0xff00ff00));
      canvas.drawRRect(
        _shape,
        ui.Paint()
          ..isAntiAlias = false
          ..color = const ui.Color(0xff808080),
      );
    });
    final result = await _filter(background, softness: 2.5);
    final pixels = await _pixels(result);
    var contaminated = 0;
    for (var y = 0; y < _height; y++) {
      for (var x = 0; x < _width; x++) {
        if (!_shape.deflate(1.5).contains(ui.Offset(x + .5, y + .5))) continue;
        if ((_channel(pixels, x, y, 1) - _channel(pixels, x, y)).abs() > 2) {
          contaminated++;
        }
      }
    }
    expect(
      contaminated,
      0,
      reason: 'Neighboring green content must stay outside the gray surface.',
    );
    await _preview(result, 'glass-bounded-frost');
    result.dispose();
    background.dispose();
  });

  test(
    'baseline frost diffuses fine detail instead of making shifted copies',
    () async {
      final background = await _background((canvas) {
        for (var x = 0; x < _width; x++) {
          canvas.drawRect(
            ui.Rect.fromLTWH(x.toDouble(), 0, 1, _height.toDouble()),
            ui.Paint()
              ..color = x.isEven
                  ? const ui.Color(0xff202020)
                  : const ui.Color(0xffe0e0e0),
          );
        }
      });
      final result = await _filter(background, softness: 1);
      final pixels = await _pixels(result);
      for (var x = 100; x < 200; x++) {
        expect(
          (_channel(pixels, x, 97) - _channel(pixels, x + 1, 97)).abs(),
          lessThan(20),
        );
        expect(_channel(pixels, x, 97), inInclusiveRange(100, 156));
      }
      result.dispose();
      background.dispose();
    },
  );
}
