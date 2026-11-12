import 'package:flutter/material.dart';

/// The original five-band launch mark, now shared with the platform app icons.
class HyperstreamMark extends StatelessWidget {
  const HyperstreamMark({super.key, this.size = 72});
  final double size;
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Hyperstream icon',
    image: true,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(size * .23),
      child: CustomPaint(
        size: Size.square(size),
        painter: const HyperstreamMarkPainter(),
      ),
    ),
  );
}

class HyperstreamMarkPainter extends CustomPainter {
  const HyperstreamMarkPainter();
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);
    const bounds = Rect.fromLTWH(0, 0, 100, 100);
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xff39206f), Color(0xff180e35), Color(0xff351663)],
        ).createShader(bounds),
    );
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-.35, -.45),
          radius: 1.05,
          colors: [Color(0x704b32a7), Color(0x004b32a7)],
        ).createShader(bounds),
    );
    final band = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xffeedcff), Color(0xffb57bff), Color(0xff7944ea)],
      ).createShader(const Rect.fromLTWH(22, 22, 56, 56));
    for (var i = 0; i < 5; i++) {
      final height = [20.0, 36.0, 56.0, 36.0, 20.0][i];
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(25 + i * 11.0, 50 - height / 2, 6, height),
          const Radius.circular(3),
        ),
        band,
      );
    }
    void sparkle(double x, double y, double radius) {
      final path = Path()
        ..moveTo(x, y - radius)
        ..quadraticBezierTo(x + radius * .22, y - radius * .22, x + radius, y)
        ..quadraticBezierTo(x + radius * .22, y + radius * .22, x, y + radius)
        ..quadraticBezierTo(x - radius * .22, y + radius * .22, x - radius, y)
        ..quadraticBezierTo(x - radius * .22, y - radius * .22, x, y - radius)
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xffffefae), Color(0xffffc34f)],
          ).createShader(Rect.fromCircle(center: Offset(x, y), radius: radius)),
      );
    }

    sparkle(78, 23, 10);
    sparkle(23, 77, 7);
    sparkle(20, 27, 3.5);
    canvas.drawCircle(
      const Offset(78, 77),
      1.8,
      Paint()..color = const Color(0xffffd578),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(HyperstreamMarkPainter oldDelegate) => false;
}
