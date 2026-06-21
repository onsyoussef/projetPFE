import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../headsapp_theme.dart';
import '../../login_page.dart';

const _logoAsset = 'assets/images/headsapp_logo.png';

class _FeatureSlide {
  const _FeatureSlide({
    required this.imageAsset,
    required this.title,
    required this.description,
    this.showChatOverlay = false,
    this.blurBackground = false,
  });

  final String imageAsset;
  final String title;
  final String description;
  final bool showChatOverlay;
  final bool blurBackground;
}

const _featureSlides = [
  _FeatureSlide(
    imageAsset: 'assets/images/onboarding_presentation.png',
    title: 'Présentation de l\'application',
    description:
        'Gérez votre santé en toute simplicité avec HeadsApp, votre compagnon médical au quotidien.',
  ),
  _FeatureSlide(
    imageAsset: 'assets/images/onboarding_communication.png',
    title: 'Communication directe',
    description:
        'Restez en contact permanent avec vos praticiens grâce à notre messagerie sécurisée.',
    showChatOverlay: true,
    blurBackground: true,
  ),
  _FeatureSlide(
    imageAsset: 'assets/images/onboarding_teleconsultation.png',
    title: 'Téléconsultation',
    description:
        'Consultez votre médecin où que vous soyez via un appel vidéo haute définition.',
  ),
];

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  Timer? _splashTimer;
  int _pageIndex = 0;

  @override
  void initState() {
    super.initState();
    _splashTimer = Timer(const Duration(milliseconds: 2500), () {
      if (!mounted || _pageIndex != 0) return;
      _goToPage(1);
    });
  }

  @override
  void dispose() {
    _splashTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _goToPage(int page) async {
    if (!_pageController.hasClients) return;
    await _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_completed', true);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const LoginPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final introPhase = _pageIndex < 2;

    return Scaffold(
      backgroundColor: Colors.white,
      body: introPhase
          ? _OnboardingBackdrop(
              child: SafeArea(
                child: Column(
                  children: [
                    Expanded(
                      child: PageView(
                        controller: _pageController,
                        physics: const NeverScrollableScrollPhysics(),
                        onPageChanged: (index) => setState(() => _pageIndex = index),
                        children: [
                          _OnboardingSplashPage(
                            onTap: () {
                              _splashTimer?.cancel();
                              _goToPage(1);
                            },
                          ),
                          _OnboardingWelcomePage(
                            onStart: () => setState(() => _pageIndex = 2),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 28),
                      child: _OnboardingIntroDots(activeIndex: _pageIndex),
                    ),
                  ],
                ),
              ),
            )
          : _OnboardingFeatureCarousel(
              onSkip: _completeOnboarding,
              onFinish: _completeOnboarding,
            ),
    );
  }
}

class _OnboardingFeatureCarousel extends StatefulWidget {
  const _OnboardingFeatureCarousel({
    required this.onSkip,
    required this.onFinish,
  });

  final VoidCallback onSkip;
  final VoidCallback onFinish;

  @override
  State<_OnboardingFeatureCarousel> createState() => _OnboardingFeatureCarouselState();
}

class _OnboardingFeatureCarouselState extends State<_OnboardingFeatureCarousel> {
  int _slideIndex = 0;

  void _next() {
    if (_slideIndex >= _featureSlides.length - 1) {
      widget.onFinish();
      return;
    }
    setState(() => _slideIndex += 1);
  }

  @override
  Widget build(BuildContext context) {
    final slide = _featureSlides[_slideIndex];
    final isLast = _slideIndex >= _featureSlides.length - 1;

    return Column(
      children: [
        Expanded(
          flex: 11,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (slide.blurBackground)
                ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 4.5, sigmaY: 4.5),
                  child: Image.asset(
                    slide.imageAsset,
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                    width: double.infinity,
                    height: double.infinity,
                  ),
                )
              else
                Image.asset(
                  slide.imageAsset,
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: slide.blurBackground ? 0.04 : 0.08),
                      Colors.white.withValues(alpha: slide.blurBackground ? 0.42 : 0.55),
                      Colors.white,
                    ],
                    stops: const [0.0, 0.68, 1.0],
                  ),
                ),
              ),
              SafeArea(
                child: Align(
                  alignment: Alignment.topRight,
                  child: TextButton(
                    onPressed: widget.onSkip,
                    child: const Text(
                      'Passer',
                      style: TextStyle(
                        color: HeadsAppColors.brandPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ),
              if (slide.showChatOverlay)
                const Align(
                  alignment: Alignment(0, 0.18),
                  child: _OnboardingChatOverlay(),
                ),
            ],
          ),
        ),
        Expanded(
          flex: 9,
          child: ColoredBox(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 4, 28, 24),
              child: Column(
                children: [
                  Text(
                    slide.title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: slide.showChatOverlay
                          ? HeadsAppColors.brandPrimary
                          : const Color(0xFF111827),
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    slide.description,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF64748B),
                      height: 1.5,
                    ),
                  ),
                  const Spacer(),
                  _OnboardingCarouselDots(
                    activeIndex: _slideIndex,
                    count: _featureSlides.length,
                  ),
                  const SizedBox(height: 22),
                  _OnboardingPrimaryButton(
                    label: isLast ? 'Commencer →' : 'Suivant →',
                    onPressed: _next,
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _OnboardingChatOverlay extends StatelessWidget {
  const _OnboardingChatOverlay();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: const BoxDecoration(
              color: HeadsAppColors.brandPrimary,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.chat_bubble_outline_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 72,
                  height: 7,
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCE7F5),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: 110,
                  height: 7,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8EEF5),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardingBackdrop extends StatelessWidget {
  const _OnboardingBackdrop({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFFFF6FA),
            Color(0xFFFFFFFF),
            Color(0xFFF3F8FF),
          ],
          stops: [0.0, 0.52, 1.0],
        ),
      ),
      child: child,
    );
  }
}

class _OnboardingLogoCard extends StatelessWidget {
  const _OnboardingLogoCard({this.size = 96});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: HeadsAppColors.brandPrimary.withValues(alpha: 0.10),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Image.asset(
        _logoAsset,
        width: size,
        height: size,
        fit: BoxFit.contain,
      ),
    );
  }
}

class _OnboardingSplashPage extends StatelessWidget {
  const _OnboardingSplashPage({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        children: [
          const Spacer(flex: 3),
          const _OnboardingLogoCard(),
          const SizedBox(height: 22),
          const Text(
            'HeadsApp',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: HeadsAppColors.brandPrimary,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Votre santé, simplifiée',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: HeadsAppColors.textSecondary,
            ),
          ),
          const Spacer(flex: 4),
        ],
      ),
    );
  }
}

class _OnboardingWelcomePage extends StatelessWidget {
  const _OnboardingWelcomePage({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        children: [
          const Spacer(flex: 2),
          const _OnboardingLogoCard(size: 88),
          const SizedBox(height: 28),
          const Text(
            'Bienvenue',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              color: HeadsAppColors.brandPrimary,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Votre santé, simplifiée',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: HeadsAppColors.textSecondary,
              height: 1.4,
            ),
          ),
          const Spacer(flex: 2),
          _OnboardingPrimaryButton(label: 'Commencer', onPressed: onStart),
          const SizedBox(height: 12),
          const Spacer(),
        ],
      ),
    );
  }
}

class _OnboardingPrimaryButton extends StatelessWidget {
  const _OnboardingPrimaryButton({
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: const LinearGradient(
          colors: [
            Color(0xFFD87093),
            Color(0xFF4169E1),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3B82F6).withValues(alpha: 0.24),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            width: double.infinity,
            height: HeadsAppMetrics.buttonHeight,
            child: Center(
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OnboardingIntroDots extends StatelessWidget {
  const _OnboardingIntroDots({required this.activeIndex});

  final int activeIndex;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(2, (index) {
        final active = index == activeIndex;
        return Container(
          width: 8,
          height: 8,
          margin: const EdgeInsets.symmetric(horizontal: 5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? const Color(0xFF93C5FD) : const Color(0xFFE2E8F0),
          ),
        );
      }),
    );
  }
}

class _OnboardingCarouselDots extends StatelessWidget {
  const _OnboardingCarouselDots({
    required this.activeIndex,
    required this.count,
  });

  final int activeIndex;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (index) {
        final active = index == activeIndex;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          width: active ? 24 : 8,
          height: 8,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: active ? HeadsAppColors.brandPrimary : const Color(0xFFE2E8F0),
          ),
        );
      }),
    );
  }
}
