// Run from apps/client: flutter test tool/export_brand.dart
// Exports the same vector painter used inside the app; no external artwork tool.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:hyperstream_client/widgets/hyperstream_mark.dart';

Future<Uint8List> render(int size) async {
  final recorder = ui.PictureRecorder();
  const HyperstreamMarkPainter().paint(
    ui.Canvas(recorder),
    ui.Size.square(size.toDouble()),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(size, size);
  final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  picture.dispose();
  // Apple's marketing icon must have no alpha channel, even when fully opaque.
  final rgb = Uint8List(size * (size * 3 + 1));
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final source = (y * size + x) * 4;
      final target = y * (size * 3 + 1) + 1 + x * 3;
      for (var channel = 0; channel < 3; channel++) {
        rgb[target + channel] = rgba!.getUint8(source + channel);
      }
    }
  }
  final header = ByteData(13)
    ..setUint32(0, size)
    ..setUint32(4, size)
    ..setUint8(8, 8)
    ..setUint8(9, 2);
  final output = BytesBuilder()..add([137, 80, 78, 71, 13, 10, 26, 10]);
  void chunk(String name, List<int> bytes) {
    final data = [...ascii.encode(name), ...bytes];
    var crc = 0xffffffff;
    for (final byte in data) {
      crc ^= byte;
      for (var bit = 0; bit < 8; bit++) {
        crc = (crc & 1) == 1 ? 0xedb88320 ^ (crc >> 1) : crc >> 1;
      }
    }
    output.add((ByteData(4)..setUint32(0, bytes.length)).buffer.asUint8List());
    output.add(data);
    output.add(
      (ByteData(4)..setUint32(0, crc ^ 0xffffffff)).buffer.asUint8List(),
    );
  }

  chunk('IHDR', header.buffer.asUint8List());
  chunk('IDAT', ZLibEncoder().convert(rgb));
  chunk('IEND', []);
  return output.takeBytes();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Export platform icons from the shared vector mark', () async {
    final catalog = Directory('ios/Runner/Assets.xcassets/AppIcon.appiconset');
    final json = jsonDecode(
      await File('${catalog.path}/Contents.json').readAsString(),
    ) as Map<String, dynamic>;
    final cache = <int, Uint8List>{};
    Future<Uint8List> pixels(int size) async =>
        cache[size] ??= await render(size);
    for (final entry in json['images'] as List) {
      final size =
          (double.parse((entry['size'] as String).split('x').first) *
                  double.parse((entry['scale'] as String).replaceAll('x', '')))
              .round();
      await File('${catalog.path}/${entry['filename']}')
          .writeAsBytes(await pixels(size));
    }
    final sizes = [16, 24, 32, 48, 64, 128, 256];
    final header = ByteData(6 + sizes.length * 16)
      ..setUint16(2, 1, Endian.little)
      ..setUint16(4, sizes.length, Endian.little);
    final images = <Uint8List>[];
    var offset = header.lengthInBytes;
    for (var i = 0; i < sizes.length; i++) {
      final bytes = await pixels(sizes[i]);
      images.add(bytes);
      final at = 6 + i * 16;
      header.setUint8(at, sizes[i] == 256 ? 0 : sizes[i]);
      header.setUint8(at + 1, sizes[i] == 256 ? 0 : sizes[i]);
      header.setUint16(at + 4, 1, Endian.little);
      header.setUint16(at + 6, 24, Endian.little);
      header.setUint32(at + 8, bytes.length, Endian.little);
      header.setUint32(at + 12, offset, Endian.little);
      offset += bytes.length;
    }
    final ico = BytesBuilder()..add(header.buffer.asUint8List());
    for (final bytes in images) {
      ico.add(bytes);
    }
    await File('windows/runner/resources/app_icon.ico')
        .writeAsBytes(ico.takeBytes());
  });
}
