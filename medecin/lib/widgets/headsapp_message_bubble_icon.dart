import 'package:flutter/material.dart';

/// Bulle de message pleine (maquette dashboard HeadsApp).
class HeadsAppMessageBubbleIcon extends StatelessWidget {
  const HeadsAppMessageBubbleIcon({
    super.key,
    this.size = 24,
    this.color = const Color(0xFF1A3B70),
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _HeadsAppMessageBubblePainter(color: color),
      ),
    );
  }
}

class _HeadsAppMessageBubblePainter extends CustomPainter {
  _HeadsAppMessageBubblePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final w = size.width;
    final h = size.height;

    final bubble = Path()
      ..moveTo(w * 0.22, h * 0.14)
      ..lineTo(w * 0.78, h * 0.14)
      ..quadraticBezierTo(w * 0.92, h * 0.14, w * 0.92, h * 0.28)
      ..lineTo(w * 0.92, h * 0.58)
      ..quadraticBezierTo(w * 0.92, h * 0.72, w * 0.78, h * 0.72)
      ..lineTo(w * 0.36, h * 0.72)
      ..lineTo(w * 0.18, h * 0.92)
      ..lineTo(w * 0.24, h * 0.72)
      ..lineTo(w * 0.22, h * 0.72)
      ..quadraticBezierTo(w * 0.08, h * 0.72, w * 0.08, h * 0.58)
      ..lineTo(w * 0.08, h * 0.28)
      ..quadraticBezierTo(w * 0.08, h * 0.14, w * 0.22, h * 0.14)
      ..close();

    canvas.drawPath(bubble, paint);
  }

  @override
  bool shouldRepaint(covariant _HeadsAppMessageBubblePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
