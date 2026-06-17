import 'dart:async';

import 'package:flutter/material.dart';

import '../../headsapp_theme.dart';
import '../../services/onboarding_service.dart';

class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({super.key});

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  final PageController _pageController = PageController();
  Timer? _splashTimer;

  @override
  void initState() {
    super.initState();
    _splashTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      _goTo(1);
    });
  }

  Future<void> _goTo(int page) async {
    if (!_pageController.hasClients) return;
    await _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _finish() async {
    await OnboardingService.setHasSeenOnboarding(true);
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/home');
  }

  @override
  void dispose() {
    _splashTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F9),
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          const _SplashScreen(),
          _GetStartedScreen(onStart: () => _goTo(2)),
          _WelcomeScreen(
            onSkip: () => _goTo(4),
            onNext: () => _goTo(3),
          ),
          _PatientsScreen(onNext: () => _goTo(4)),
          _SecureChatScreen(onBack: () => _goTo(3), onStart: _finish),
        ],
      ),
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF2F4F8), Color(0xFFE8F2FD)],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            _LogoCard(size: 88),
            const SizedBox(height: 16),
            Text(
              'HeadsApp',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: HeadsAppColors.brandPrimary,
                  ),
            ),
            const SizedBox(height: 4),
            const Text(
              "L'EXCELLENCE MÉDICALE",
              style: TextStyle(
                color: HeadsAppColors.textTertiary,
                letterSpacing: 0.4,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 88),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: const LinearProgressIndicator(
                  minHeight: 4,
                  color: HeadsAppColors.brandPrimary,
                  backgroundColor: HeadsAppColors.border,
                ),
              ),
            ),
            const SizedBox(height: 56),
          ],
        ),
      ),
    );
  }
}

class _GetStartedScreen extends StatelessWidget {
  const _GetStartedScreen({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Stack(
        children: [
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              height: 64,
              decoration: const BoxDecoration(
                color: HeadsAppColors.brandPrimary,
                borderRadius: BorderRadius.vertical(top: Radius.circular(999)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 120),
            child: Column(
              children: [
                const SizedBox(height: 26),
                const _LogoCard(),
                const SizedBox(height: 28),
                const Text(
                  'Communiquez efficacement\navec vos patients et suivez\nleurs dossiers.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    color: HeadsAppColors.textPrimary,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 28),
                _PrimaryButton(label: 'Démarrer', onPressed: onStart),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WelcomeScreen extends StatelessWidget {
  const _WelcomeScreen({required this.onSkip, required this.onNext});

  final VoidCallback onSkip;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                color: const Color(0xFFEAF0F8),
                child: const Center(
                  child: Icon(Icons.medical_services_rounded, size: 80, color: HeadsAppColors.brandPrimary),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onSkip,
                child: const Text("Passer l'introduction"),
              ),
            ),
            const SizedBox(height: 8),
            const Center(
              child: _Tag(label: 'BIENVENUE SUR HEADSAPP'),
            ),
            const SizedBox(height: 14),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'Simplifiez votre\nquotidien médical.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 44 / 2,
                  fontWeight: FontWeight.w800,
                  color: HeadsAppColors.textPrimary,
                  height: 1.2,
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'Une interface de gestion hospitalière conçue par et pour des médecins, privilégiant la clarté, la rapidité et la sérénité au cœur de votre pratique.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: HeadsAppColors.textSecondary,
                  height: 1.45,
                ),
              ),
            ),
            const SizedBox(height: 16),
            const _Dots(active: 1, count: 4),
            const SizedBox(height: 22),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _PrimaryButton(label: 'Suivant', onPressed: onNext),
            ),
          ],
        ),
      ),
    );
  }
}

class _PatientsScreen extends StatelessWidget {
  const _PatientsScreen({required this.onNext});
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
        child: Column(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F6FB),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Center(
                  child: Icon(Icons.groups_rounded, size: 84, color: HeadsAppColors.brandPrimary),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Gérez vos patients en\nun clic.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 40 / 2,
                fontWeight: FontWeight.w800,
                color: HeadsAppColors.textPrimary,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              "Accédez à l'historique médical complet et aux ordonnances en quelques secondes.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: HeadsAppColors.textSecondary, height: 1.45),
            ),
            const SizedBox(height: 16),
            const _Dots(active: 2, count: 4),
            const SizedBox(height: 20),
            _PrimaryButton(label: 'Suivant', onPressed: onNext),
          ],
        ),
      ),
    );
  }
}

class _SecureChatScreen extends StatelessWidget {
  const _SecureChatScreen({required this.onBack, required this.onStart});

  final VoidCallback onBack;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
        child: Column(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F6FB),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Center(
                  child: Icon(Icons.forum_rounded, size: 84, color: HeadsAppColors.brandPrimary),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Communiquez en toute\nsécurité',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 40 / 2,
                fontWeight: FontWeight.w800,
                color: HeadsAppColors.brandPrimary,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Une messagerie cryptée pour échanger avec vos confrères et vos patients.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: HeadsAppColors.textSecondary, height: 1.45),
            ),
            const SizedBox(height: 16),
            const _Dots(active: 4, count: 4),
            const SizedBox(height: 20),
            _PrimaryButton(label: 'Commencer', onPressed: onStart),
            const SizedBox(height: 10),
            TextButton(onPressed: onBack, child: const Text('Retour')),
          ],
        ),
      ),
    );
  }
}

class _LogoCard extends StatelessWidget {
  const _LogoCard({this.size = 92});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size * 0.78,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: const Icon(
        Icons.health_and_safety_rounded,
        size: 44,
        color: HeadsAppColors.brandPrimary,
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: HeadsAppColors.brandPrimary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          color: HeadsAppColors.brandPrimary,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.active, required this.count});
  final int active;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final index = i + 1;
        final isActive = index == active;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: isActive ? 24 : 8,
          height: 6,
          decoration: BoxDecoration(
            color: isActive ? HeadsAppColors.brandPrimary : HeadsAppColors.border,
            borderRadius: BorderRadius.circular(999),
          ),
        );
      }),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: HeadsAppMetrics.buttonHeight,
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1662BF), Color(0xFF1AB6E5)],
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: HeadsAppColors.brandPrimary.withValues(alpha: 0.18),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onPressed,
            child: Center(
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 20 / 1.2,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
