import 'package:flutter/material.dart';

import '../../headsapp_theme.dart';
import '../../widgets/dot_indicator.dart';
import '../../widgets/gradient_button.dart';

class PresentationPage extends StatelessWidget {
  const PresentationPage({
    super.key,
    required this.onSkip,
    required this.onNext,
  });

  final VoidCallback onSkip;
  final VoidCallback onNext;

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
                            Colors.white.withValues(alpha: 0.97),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: TextButton(
                      onPressed: onSkip,
                      child: const Text(
                        'Passer',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                HeadsAppMetrics.pagePadding,
                8,
                HeadsAppMetrics.pagePadding,
                24,
              ),
              child: Column(
                children: [
                  const Text(
                    'Présentation de\nl\'application',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: HeadsAppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Gérez votre santé en toute simplicité avec HeadsApp,\nvotre compagnon médical au quotidien.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: HeadsAppColors.textSecondary,
                      fontSize: 15,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const DotIndicator(activeIndex: 0),
                  const SizedBox(height: 24),
                  GradientButton(
                    label: 'Suivant →',
                    onPressed: onNext,
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
