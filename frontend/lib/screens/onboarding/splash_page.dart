import 'dart:async';

import 'package:flutter/material.dart';

import '../../headsapp_theme.dart';
import '../../widgets/dot_indicator.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({
    super.key,
    required this.onNext,
  });

  final VoidCallback onNext;

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Delai du splash ajustable simplement ici (2 secondes).
    _timer = Timer(const Duration(seconds: 2), widget.onNext);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: HeadsAppColors.surface,
        gradient: RadialGradient(
          center: Alignment.center,
          radius: 1.2,
          colors: [
            HeadsAppColors.surface,
            const Color(0xFFF6EDF2),
          ],
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: HeadsAppMetrics.pagePadding),
          child: Column(
            children: [
              const Spacer(flex: 3),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: HeadsAppColors.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: HeadsAppColors.border),
                  boxShadow: [
                    BoxShadow(
                      color: HeadsAppColors.brandPrimary.withValues(alpha: 0.10),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Image.asset(
                  'assets/images/headsapp_logo.png',
                  width: 84,
                  height: 84,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'HeadsApp',
                style: TextStyle(
                  fontSize: 46 / 1.6,
                  fontWeight: FontWeight.bold,
                  color: HeadsAppColors.brandPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Votre santé, simplifiée',
                style: TextStyle(
                  fontSize: 15,
                  color: HeadsAppColors.textTertiary,
                ),
              ),
              const Spacer(flex: 4),
              const DotIndicator(activeIndex: null),
              const SizedBox(height: 26),
            ],
          ),
        ),
      ),
    );
  }
}
