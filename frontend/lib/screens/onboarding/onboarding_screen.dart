import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../login_page.dart';
import 'communication_page.dart';
import 'presentation_page.dart';
import 'splash_page.dart';
import 'teleconsultation_page.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();

  Future<void> _animateTo(int index) async {
    if (!_pageController.hasClients) return;
    await _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _nextFrom(int index) async {
    await _animateTo(index + 1);
  }

  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_completed', true);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => const LoginPage(),
      ),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView.builder(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 4,
        itemBuilder: (context, index) {
          switch (index) {
            case 0:
              return SplashPage(
                onNext: () => _animateTo(1),
              );
            case 1:
              return PresentationPage(
                onSkip: () => _pageController.jumpToPage(3),
                onNext: () => _nextFrom(1),
              );
            case 2:
              return CommunicationPage(
                onNext: () => _nextFrom(2),
              );
            default:
              return TeleconsultationPage(
                onFinish: _completeOnboarding,
              );
          }
        },
      ),
    );
  }
}
