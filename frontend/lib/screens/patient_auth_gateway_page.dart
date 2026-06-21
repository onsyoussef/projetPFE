import 'package:flutter/material.dart';

import '../headsapp_theme.dart';
import '../widgets/headsapp_brand_widgets.dart';
import '../login_page.dart';
import '../signup_page.dart';

class PatientAuthGatewayPage extends StatelessWidget {
  const PatientAuthGatewayPage({super.key});

  static const String _logoAsset = 'assets/images/headsapp_logo.png';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: HeadsAppGradientBackdrop(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 390),
                  child: SizedBox(
                    height: constraints.maxHeight - 40,
                    child: Column(
                      children: [
                        const Spacer(),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFBFDFF), Color(0xFFF2F7FF)],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(color: HeadsAppColors.border),
                            boxShadow: [
                              BoxShadow(
                                color: HeadsAppColors.brandPrimary.withValues(alpha: 0.07),
                                blurRadius: 26,
                                offset: const Offset(0, 14),
                              ),
                            ],
                          ),
                          child: Stack(
                            children: [
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 0,
                                child: SizedBox(
                                  height: 74,
                                  child: CustomPaint(
                                    painter: _PatientBottomGlowPainter(
                                      start: HeadsAppColors.brandPrimary,
                                      end: HeadsAppColors.brandAccent,
                                    ),
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(10, 4, 10, 34),
                                child: Column(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(24),
                                        boxShadow: [
                                          BoxShadow(
                                            color: HeadsAppColors.brandPrimary.withValues(alpha: 0.08),
                                            blurRadius: 18,
                                            offset: const Offset(0, 8),
                                          ),
                                        ],
                                      ),
                                      child: Image.asset(
                                        _logoAsset,
                                        width: 102,
                                        height: 102,
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                    const SizedBox(height: 18),
                                    const Text(
                                      'HeadsApp',
                                      style: TextStyle(
                                        fontSize: 26,
                                        fontWeight: FontWeight.w800,
                                        color: HeadsAppColors.brandPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Votre partenaire professionnel de santé',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 14.5,
                                        height: 1.55,
                                        color: HeadsAppColors.textSecondary,
                                      ),
                                    ),
                                    const SizedBox(height: 24),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: HeadsAppColors.primaryButtonGradient,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                foregroundColor: Colors.white,
                                shadowColor: Colors.transparent,
                                minimumSize: const Size.fromHeight(56),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(builder: (_) => const SignupPage()),
                                );
                              },
                              child: const Text(
                                "S'inscrire",
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: HeadsAppColors.brandPrimary,
                              side: const BorderSide(color: HeadsAppColors.border),
                              minimumSize: const Size.fromHeight(56),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              backgroundColor: Colors.white,
                            ),
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => const LoginPage()),
                              );
                            },
                            child: const Text(
                              'Se connecter',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PatientBottomGlowPainter extends CustomPainter {
  const _PatientBottomGlowPainter({
    required this.start,
    required this.end,
  });

  final Color start;
  final Color end;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..shader = LinearGradient(
        colors: [start.withValues(alpha: 0.85), end.withValues(alpha: 0.85)],
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      ).createShader(rect);

    final path = Path()
      ..moveTo(0, size.height * 0.82)
      ..quadraticBezierTo(
        size.width * 0.28,
        size.height * 0.34,
        size.width * 0.55,
        size.height * 0.60,
      )
      ..quadraticBezierTo(
        size.width * 0.78,
        size.height * 0.78,
        size.width,
        size.height * 0.48,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _PatientBottomGlowPainter oldDelegate) {
    return oldDelegate.start != start || oldDelegate.end != end;
  }
}
