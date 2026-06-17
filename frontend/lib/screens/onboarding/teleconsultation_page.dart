import 'package:flutter/material.dart';

import '../../headsapp_theme.dart';
import '../../widgets/dot_indicator.dart';
import '../../widgets/gradient_button.dart';

class TeleconsultationPage extends StatelessWidget {
  const TeleconsultationPage({
    super.key,
    required this.onFinish,
  });

  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HeadsAppColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Image.asset(
                      'assets/images/headsapp_logo.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.white.withValues(alpha: 0),
                            Colors.white,
                          ],
                          stops: const [0.68, 1],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                HeadsAppMetrics.pagePadding,
                12,
                HeadsAppMetrics.pagePadding,
                24,
              ),
              child: Column(
                children: [
                  const Text(
                    'Téléconsultation',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: HeadsAppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Consultez votre médecin où que vous\nsoyez via un appel vidéo haute\ndéfinition.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: HeadsAppColors.textSecondary,
                      fontSize: 15,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const DotIndicator(activeIndex: 2),
                  const SizedBox(height: 24),
                  GradientButton(
                    label: 'Commencer →',
                    onPressed: onFinish,
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: onFinish,
                    child: const Text(
                      'Déjà un compte ? Se connecter',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
