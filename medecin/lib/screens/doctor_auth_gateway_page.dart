import 'package:flutter/material.dart';

import '../headsapp_theme.dart';
import '../widgets/headsapp_brand_widgets.dart';
import '../login_page.dart';
import '../signup_page.dart';

class DoctorAuthGatewayPage extends StatelessWidget {
  const DoctorAuthGatewayPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: HeadsAppGradientBackdrop(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 390),
                  child: SizedBox(
                    height: constraints.maxHeight - 32,
                    child: Column(
                      children: [
                        const Spacer(),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(18, 20, 18, 0),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFEFEFF), Color(0xFFF5F9FF)],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(color: HeadsAppColors.border),
                            boxShadow: [
                              BoxShadow(
                                color: HeadsAppColors.brandPrimary.withValues(alpha: 0.06),
                                blurRadius: 24,
                                offset: const Offset(0, 10),
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
                                  height: 78,
                                  child: CustomPaint(
                                    painter: _BottomWavePainter(
                                      start: HeadsAppColors.brandPrimary,
                                      end: HeadsAppColors.brandAccent,
                                    ),
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(14, 6, 14, 34),
                                child: Column(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(22),
                                      child: Image.asset(
                                        'assets/onboarding/doctor_splash.png',
                                        height: 258,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    const Text(
                                      'Communiquez efficacement\navec vos patients et suivez\nleurs dossiers.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 19,
                                        height: 1.45,
                                        fontWeight: FontWeight.w500,
                                        color: HeadsAppColors.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 22),
                                    DecoratedBox(
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                          colors: [
                                            HeadsAppColors.brandPrimary,
                                            HeadsAppColors.brandAccent,
                                          ],
                                          begin: Alignment.centerLeft,
                                          end: Alignment.centerRight,
                                        ),
                                        borderRadius: BorderRadius.circular(16),
                                        boxShadow: [
                                          BoxShadow(
                                            color: HeadsAppColors.brandPrimary.withValues(alpha: 0.15),
                                            blurRadius: 14,
                                            offset: const Offset(0, 7),
                                          ),
                                        ],
                                      ),
                                      child: SizedBox(
                                        width: 190,
                                        child: FilledButton(
                                          onPressed: () {
                                            Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (_) => const SignupPage(),
                                              ),
                                            );
                                          },
                                          style: FilledButton.styleFrom(
                                            backgroundColor: Colors.transparent,
                                            foregroundColor: Colors.white,
                                            minimumSize: const Size.fromHeight(54),
                                            shadowColor: Colors.transparent,
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(16),
                                            ),
                                          ),
                                          child: const Text(
                                            'Démarrer',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [
                                HeadsAppColors.brandPrimary,
                                HeadsAppColors.brandAccent,
                              ],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(builder: (_) => const SignupPage()),
                                );
                              },
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                foregroundColor: Colors.white,
                                minimumSize: const Size.fromHeight(56),
                                shadowColor: Colors.transparent,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
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
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => const LoginPage()),
                              );
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: HeadsAppColors.textPrimary,
                              side: const BorderSide(color: HeadsAppColors.border),
                              minimumSize: const Size.fromHeight(56),
                              backgroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
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

class _BottomWavePainter extends CustomPainter {
  const _BottomWavePainter({
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
        colors: [start, end],
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      ).createShader(rect);

    final path = Path()
      ..moveTo(0, size.height * 0.48)
      ..quadraticBezierTo(
        size.width * 0.25,
        size.height * 0.18,
        size.width * 0.52,
        size.height * 0.34,
      )
      ..quadraticBezierTo(
        size.width * 0.78,
        size.height * 0.50,
        size.width,
        size.height * 0.22,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _BottomWavePainter oldDelegate) {
    return oldDelegate.start != start || oldDelegate.end != end;
  }
}
