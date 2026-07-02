import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class ThinkingIndicator extends StatefulWidget {
  final double size;
  const ThinkingIndicator({Key? key, this.size = 52}) : super(key: key);

  @override
  ThinkingIndicatorState createState() => ThinkingIndicatorState();
}

class ThinkingIndicatorState extends State<ThinkingIndicator> with TickerProviderStateMixin {
  late AnimationController _scaleGlowController;
  late AnimationController _opacityController;
  late AnimationController _tailController;

  @override
  void initState() {
    super.initState();
    // Breathing scale: 1.00 -> 1.015 -> 1.00 (Duration: 2400 ms full cycle)
    _scaleGlowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    // Opacity: 0.90 -> 1.00 -> 0.90 (Duration: 2200 ms full cycle)
    _opacityController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);

    // Tail ripples: 0 -> 2pi over a suitable duration for a calm wave
    _tailController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000), // Adjust if needed
    )..repeat();
  }

  @override
  void dispose() {
    _scaleGlowController.dispose();
    _opacityController.dispose();
    _tailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_scaleGlowController, _opacityController, _tailController]),
      builder: (context, child) {
        // Scale: 1.00 to 1.015 using easeInOut
        final scaleValue = 1.0 + (0.015 * Curves.easeInOut.transform(_scaleGlowController.value));
        
        // Glow intensity: 0 to 20%
        final glowValue = 0.20 * Curves.easeInOut.transform(_scaleGlowController.value);
        
        // Opacity: 0.90 to 1.00
        final opacityValue = 0.90 + (0.10 * Curves.easeInOut.transform(_opacityController.value));

        return Opacity(
          opacity: opacityValue,
          child: Transform.scale(
            scale: scaleValue,
            alignment: Alignment.center,
            child: CustomPaint(
              size: Size(widget.size, widget.size * (404.0 / 743.0)), // Maintain aspect ratio from SVG viewbox
              painter: _LogoPainter(
                tailTime: _tailController.value * 2 * pi, // 0 to 2pi
                glowOpacity: glowValue,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LogoPainter extends CustomPainter {
  final double tailTime;
  final double glowOpacity;

  _LogoPainter({required this.tailTime, required this.glowOpacity});

  Offset _rotate(double x, double y, double cx, double cy, double angle) {
    if (angle == 0.0) return Offset(x, y);
    final double dx = x - cx;
    final double dy = y - cy;
    final double nx = dx * cos(angle) - dy * sin(angle);
    final double ny = dx * sin(angle) + dy * cos(angle);
    return Offset(nx + cx, ny + cy);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final double scaleX = size.width / 743.0;
    final double scaleY = size.height / 404.0;
    
    // Tail spikes animation
    // Top spike: amplitude 2°
    // Middle spike: amplitude 3°
    // Bottom spike: amplitude 4°
    // Delays: 0, 120ms, 240ms (using 2000ms full wave = 120ms is 0.06 phase = 0.377 rad)
    final double topAngle = (2.0 * pi / 180.0) * sin(tailTime);
    final double midAngle = (3.0 * pi / 180.0) * sin(tailTime - 0.377);
    final double botAngle = (4.0 * pi / 180.0) * sin(tailTime - 0.754);

    final Path path = Path();
    path.moveTo(501.747, 250.712);
    path.cubicTo(559.873, 211.829, 598.833, 204.299, 691.095, 214.101);
    path.cubicTo(646.412, 172.845, 512.143, 189.92, 455.73, 205.851);
    path.cubicTo(490.157, 191.199, 510.775, 185.802, 546.185, 179.969);
    path.cubicTo(665.6, 169.469, 726.169, 197.68, 716.683, 262.358);
    path.cubicTo(775.896, 195.904, 733.087, 68.9887, 585.029, 70.0324);
    path.lineTo(574.732, 92.1788);
    path.lineTo(574.732, 65.6818);
    path.cubicTo(495.902, 11.9113, 440.298, -6.80007, 351.413, 2.13582);

    // Top spike
    Offset p9_1 = _rotate(250.01, 19.6744, 240.221, 122.938, topAngle * 0.5);
    Offset p9_2 = _rotate(199.456, 54.2324, 240.221, 122.938, topAngle * 0.7);
    Offset p9_3 = _rotate(142.716, 134.011, 240.221, 122.938, topAngle);
    path.cubicTo(p9_1.dx, p9_1.dy, p9_2.dx, p9_2.dy, p9_3.dx, p9_3.dy);

    Offset p10_1 = _rotate(180.32, 124.276, 240.221, 122.938, topAngle);
    Offset p10_2 = _rotate(201.852, 121.493, 240.221, 122.938, topAngle * 0.5);
    path.cubicTo(p10_1.dx, p10_1.dy, p10_2.dx, p10_2.dy, 240.221, 122.938);

    // Middle spike
    Offset p11_1 = _rotate(146.149, 159.8, 213.769, 217.06, midAngle * 0.5);
    Offset p11_2 = _rotate(95.0336, 201.669, 213.769, 217.06, midAngle * 0.7);
    Offset p11_3 = _rotate(58.1933, 256.32, 213.769, 217.06, midAngle);
    path.cubicTo(p11_1.dx, p11_1.dy, p11_2.dx, p11_2.dy, p11_3.dx, p11_3.dy);

    Offset p12_1 = _rotate(140.647, 217.143, 213.769, 217.06, midAngle);
    Offset p12_2 = _rotate(178.058, 218.92, 213.769, 217.06, midAngle * 0.5);
    path.cubicTo(p12_1.dx, p12_1.dy, p12_2.dx, p12_2.dy, 213.769, 217.06);

    // Bottom spike
    Offset p13_1 = _rotate(92.1827, 266.484, 217.32, 309.056, botAngle * 0.5);
    Offset p13_2 = _rotate(32.5964, 319.867, 217.32, 309.056, botAngle * 0.7);
    Offset p13_3 = _rotate(0, 370.007, 217.32, 309.056, botAngle);
    path.cubicTo(p13_1.dx, p13_1.dy, p13_2.dx, p13_2.dy, p13_3.dx, p13_3.dy);

    Offset p14_1 = _rotate(85.5025, 326.167, 217.32, 309.056, botAngle);
    Offset p14_2 = _rotate(135.96, 311.872, 217.32, 309.056, botAngle * 0.5);
    path.cubicTo(p14_1.dx, p14_1.dy, p14_2.dx, p14_2.dy, 217.32, 309.056);

    // Remaining path
    path.cubicTo(164.397, 327.516, 134.165, 345.982, 83.7038, 380.555);
    path.cubicTo(112.411, 378.887, 147.242, 380.196, 204.541, 394.143);
    path.cubicTo(271.335, 406.534, 304.335, 407.16, 337.187, 396.084);
    path.cubicTo(385.919, 381.292, 408.43, 364.504, 439.109, 326.216);
    path.cubicTo(458.335, 295.609, 472.272, 277.138, 501.747, 250.712);
    path.close();

    // Scale path
    final Matrix4 matrix = Matrix4.identity()..scale(scaleX, scaleY);
    final Path scaledPath = path.transform(matrix.storage);

    // Gradients
    final Offset p1 = Offset(507.567 * scaleX, 443.366 * scaleY);
    final Offset p2 = Offset(-290.929 * scaleX, 500.124 * scaleY);

    if (glowOpacity > 0.0) {
      final Paint glowPaint = Paint()
        ..shader = ui.Gradient.linear(
          p1,
          p2,
          [Colors.white.withValues(alpha: glowOpacity), const Color(0xFFE2A730).withValues(alpha: glowOpacity)],
        )
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12.0)
        ..style = PaintingStyle.fill;
      canvas.drawPath(scaledPath, glowPaint);
    }

    final Paint exactFillPaint = Paint()
      ..shader = ui.Gradient.linear(
        p1,
        p2,
        [Colors.white, const Color(0xFFE2A730)],
      )
      ..style = PaintingStyle.fill;
    
    canvas.drawPath(scaledPath, exactFillPaint);
  }

  @override
  bool shouldRepaint(covariant _LogoPainter oldDelegate) {
    return oldDelegate.tailTime != tailTime || oldDelegate.glowOpacity != glowOpacity;
  }
}
