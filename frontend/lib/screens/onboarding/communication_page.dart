import 'package:flutter/material.dart';

import '../../headsapp_theme.dart';
import '../../widgets/dot_indicator.dart';
import '../../widgets/gradient_button.dart';

class CommunicationPage extends StatelessWidget {
  const CommunicationPage({
    super.key,
    required this.onNext,
  });

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
                  Positioned(
                    left: 24,
                    right: 24,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: HeadsAppColors.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: HeadsAppColors.border),
                        boxShadow: [
                          BoxShadow(
                            color: HeadsAppColors.brandPrimary.withValues(alpha: 0.10),
                            blurRadius: 12,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: HeadsAppColors.brandPrimary,
                            ),
                            child: const Icon(
                              Icons.message_outlined,
                              size: 18,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              children: [
                                Container(
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: HeadsAppColors.border,
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: HeadsAppColors.border.withValues(alpha: 0.8),
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                HeadsAppMetrics.pagePadding,
                38,
                HeadsAppMetrics.pagePadding,
                24,
              ),
              child: Column(
                children: [
                  const Text(
                    'Communication\ndirecte',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: HeadsAppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Restez en contact permanent\navec vos praticiens grâce à\nnotre messagerie sécurisée.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: HeadsAppColors.textSecondary,
                      fontSize: 15,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const DotIndicator(activeIndex: 1),
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
