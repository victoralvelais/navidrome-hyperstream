import 'dart:typed_data';
import 'dart:ui' as ui;

/// Original procedural artwork for local UI previews, never shipped in the app.
Future<Uint8List> previewArtwork(int index) async {
  final colors = [
    [
      const ui.Color(0xff181538),
      const ui.Color(0xffa85389),
      const ui.Color(0xfff0b385),
    ],
    [
      const ui.Color(0xff12494d),
      const ui.Color(0xff70a997),
      const ui.Color(0xffe4dbb5),
    ],
    [
      const ui.Color(0xff142d65),
      const ui.Color(0xff4c83ce),
      const ui.Color(0xffcad8f4),
    ],
    [
      const ui.Color(0xff763a35),
      const ui.Color(0xffd18c54),
      const ui.Color(0xffedd4a5),
    ],
  ][index];
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    const ui.Rect.fromLTWH(0, 0, 400, 400),
    ui.Paint()
      ..shader = ui.Gradient.linear(
        const ui.Offset(0, 0),
        const ui.Offset(400, 400),
        colors,
        [0, .5, 1],
      ),
  );
  canvas.drawCircle(
    ui.Offset(290 - index * 25, 125 + index * 20),
    87,
    ui.Paint()..color = colors.last.withValues(alpha: .8),
  );
  for (var i = 0; i < 7; i++) {
    final y = 210.0 + i * 30;
    canvas.drawPath(
      ui.Path()
        ..moveTo(0, y + 35)
        ..quadraticBezierTo(180, y - 100, 400, y + 20)
        ..lineTo(400, 400)
        ..lineTo(0, 400)
        ..close(),
      ui.Paint()..color = ui.Color.lerp(colors.first, colors[1], i / 12)!,
    );
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(400, 400);
  final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
      .asUint8List();
  image.dispose();
  picture.dispose();
  return bytes;
}
