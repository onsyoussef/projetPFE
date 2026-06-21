import 'dart:async';

import 'package:flutter/material.dart';

import '../../headsapp_theme.dart';
import '../../services/onboarding_service.dart';
import '../../widgets/headsapp_logo_text.dart';

const _logoAsset = 'assets/images/headsapp_logo.png';

class _IntroSlide {
  const _IntroSlide({
    this.heroAsset,
    this.heroCropFactor = 1.0,
    this.badge,
    required this.titleLeading,
    this.titleAccent,
    required this.description,
    this.showSecurityBadge = false,
    this.illustration,
    this.showSkipLink = false,
    this.roundedHero = false,
    this.titleAllPrimary = false,
    this.showBackLink = false,
    this.showHeroGradient = true,
    this.heroAlignment = Alignment.topCenter,
    this.heroSectionFlex,
    this.contentSectionFlex,
  });

  final String? heroAsset;
  final double heroCropFactor;
  final String? badge;
  final String titleLeading;
  final String? titleAccent;
  final String description;
  final bool showSecurityBadge;
  final Widget? illustration;
  final bool showSkipLink;
  final bool roundedHero;
  final bool titleAllPrimary;
  final bool showBackLink;
  final bool showHeroGradient;
  final Alignment heroAlignment;
  final int? heroSectionFlex;
  final int? contentSectionFlex;
}

const _introSlides = [
  _IntroSlide(
    heroAsset: 'assets/onboarding/doctor_onboarding_welcome_hero.png',
    heroCropFactor: 1.0,
    heroAlignment: Alignment.center,
    showHeroGradient: false,
    heroSectionFlex: 2,
    contentSectionFlex: 3,
    badge: 'BIENVENUE SUR HEADSAPP',
    titleLeading: 'Simplifiez votre ',
    titleAccent: 'quotidien médical.',
    description:
        'Une interface de gestion hospitalière conçue par et pour des médecins, privilégiant la clarté, la rapidité et la sérénité au cœur de votre pratique.',
    showSkipLink: true,
  ),
  _IntroSlide(
    illustration: _PatientListIllustration(),
    titleLeading: 'Gérez vos patients ',
    titleAccent: 'en un clic.',
    description:
        'Accédez à l\'historique médical complet et aux ordonnances en quelques secondes.',
  ),
  _IntroSlide(
    heroAsset: 'assets/onboarding/doctor_teleconsult_hero.png',
    roundedHero: true,
    titleLeading: 'Téléconsultations fluides.',
    description:
        'Réalisez vos rendez-vous à distance avec une qualité vidéo HD et un chat intégré sécurisé. Le soin, là où vous êtes.',
    showSecurityBadge: true,
  ),
  _IntroSlide(
    illustration: _SecureChatIllustration(),
    titleLeading: 'Communiquez en toute sécurité',
    titleAllPrimary: true,
    description:
        'Une messagerie cryptée pour échanger avec vos confrères et vos patients.',
    showBackLink: true,
  ),
];

class DoctorOnboardingScreen extends StatefulWidget {
  const DoctorOnboardingScreen({super.key});

  @override
  State<DoctorOnboardingScreen> createState() => _DoctorOnboardingScreenState();
}

class _DoctorOnboardingScreenState extends State<DoctorOnboardingScreen>
    with SingleTickerProviderStateMixin {
  final PageController _pageController = PageController();
  Timer? _splashTimer;
  late final AnimationController _progressController;
  int _pageIndex = 0;
  bool _showFeatureCarousel = false;

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..forward();
    _splashTimer = Timer(const Duration(milliseconds: 2600), () {
      if (!mounted || _pageIndex != 0 || _showFeatureCarousel) return;
      _goToPage(1);
    });
  }

  @override
  void dispose() {
    _splashTimer?.cancel();
    _progressController.dispose();
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

  Future<void> _finishOnboarding() async {
    await OnboardingService.setOnboardingCompleted();
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/home');
  }

  void _openFeatureCarousel() {
    setState(() => _showFeatureCarousel = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_showFeatureCarousel) {
      return _DoctorFeatureCarousel(onFinish: _finishOnboarding);
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: _DoctorOnboardingBackdrop(
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (index) => setState(() => _pageIndex = index),
                  children: [
                    _DoctorSplashPage(
                      onTap: () {
                        _splashTimer?.cancel();
                        _goToPage(1);
                      },
                    ),
                    _DoctorWelcomePage(onStart: _openFeatureCarousel),
                  ],
                ),
              ),
              if (_pageIndex == 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(48, 0, 48, 28),
                  child: AnimatedBuilder(
                    animation: _progressController,
                    builder: (context, _) {
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: _progressController.value,
                          minHeight: 4,
                          backgroundColor: const Color(0xFFE8EDF3),
                          color: HeadsAppColors.brandPrimary,
                        ),
                      );
                    },
                  ),
                )
              else
                const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }
}

class _DoctorFeatureCarousel extends StatefulWidget {
  const _DoctorFeatureCarousel({required this.onFinish});

  final VoidCallback onFinish;

  @override
  State<_DoctorFeatureCarousel> createState() => _DoctorFeatureCarouselState();
}

class _DoctorFeatureCarouselState extends State<_DoctorFeatureCarousel> {
  int _slideIndex = 0;

  void _next() {
    if (_slideIndex >= _introSlides.length - 1) {
      widget.onFinish();
      return;
    }
    setState(() => _slideIndex += 1);
  }

  void _back() {
    if (_slideIndex <= 0) return;
    setState(() => _slideIndex -= 1);
  }

  @override
  Widget build(BuildContext context) {
    final slide = _introSlides[_slideIndex];
    final isLast = _slideIndex >= _introSlides.length - 1;
    final heroFlex = slide.heroSectionFlex ?? 11;
    final contentFlex = slide.contentSectionFlex ?? 9;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          Expanded(
            flex: heroFlex,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (slide.roundedHero && slide.heroAsset != null)
                  ColoredBox(
                    color: Colors.white,
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(22, 24, 22, 8),
                        child: _RoundedHeroCard(
                          asset: slide.heroAsset!,
                          showSecurityBadge: slide.showSecurityBadge,
                        ),
                      ),
                    ),
                  )
                else if (slide.heroAsset != null)
                  _HeroImage(
                    asset: slide.heroAsset!,
                    cropFactor: slide.heroCropFactor,
                    alignment: slide.heroAlignment,
                  )
                else if (slide.illustration != null)
                  ColoredBox(
                    color: Colors.white,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: slide.illustration,
                      ),
                    ),
                  ),
                if (slide.showSecurityBadge && !slide.roundedHero)
                  const Positioned(
                    left: 20,
                    bottom: 20,
                    child: _SecureChannelBadge(),
                  ),
                if (slide.heroAsset != null &&
                    !slide.roundedHero &&
                    slide.showHeroGradient)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.white.withValues(alpha: 0.05),
                          Colors.white.withValues(alpha: 0.55),
                        ],
                        stops: const [0.45, 0.78, 1.0],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            flex: contentFlex,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (slide.showSkipLink)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: widget.onFinish,
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF94A3B8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 0,
                          ),
                        ),
                        child: const Text(
                          'Passer l\'introduction',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    )
                  else
                    const SizedBox(height: 4),
                  if (slide.badge != null) ...[
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F2FC),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          slide.badge!,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                            color: HeadsAppColors.brandPrimary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                  ] else
                    const SizedBox(height: 8),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: slide.titleLeading,
                          style: TextStyle(
                            color: slide.titleAllPrimary
                                ? HeadsAppColors.brandPrimary
                                : const Color(0xFF111827),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (slide.titleAccent != null)
                          TextSpan(
                            text: slide.titleAccent,
                            style: const TextStyle(
                              color: HeadsAppColors.brandPrimary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 26, height: 1.25),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    slide.description,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF64748B),
                      height: 1.55,
                    ),
                  ),
                  const Spacer(),
                  _DoctorIntroProgressBar(
                    activeIndex: _slideIndex,
                    count: _introSlides.length,
                  ),
                  const SizedBox(height: 22),
                  _DoctorOnboardingPrimaryButton(
                    label: isLast ? 'Commencer' : 'Suivant',
                    onPressed: _next,
                  ),
                  if (isLast && slide.showBackLink) ...[
                    const SizedBox(height: 6),
                    TextButton(
                      onPressed: _back,
                      child: const Text(
                        'Retour',
                        style: TextStyle(
                          color: HeadsAppColors.brandPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ] else
                    const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroImage extends StatelessWidget {
  const _HeroImage({
    required this.asset,
    required this.cropFactor,
    this.alignment = Alignment.topCenter,
  });

  final String asset;
  final double cropFactor;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    if (cropFactor >= 0.99) {
      return Image.asset(
        asset,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        alignment: alignment,
      );
    }
    return ClipRect(
      child: Align(
        alignment: alignment,
        heightFactor: cropFactor,
        child: Image.asset(
          asset,
          width: double.infinity,
          fit: BoxFit.cover,
          alignment: alignment,
        ),
      ),
    );
  }
}

class _DoctorIntroProgressBar extends StatelessWidget {
  const _DoctorIntroProgressBar({
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
          width: active ? 28 : 8,
          height: 8,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: active
                ? HeadsAppColors.brandPrimary
                : const Color(0xFFE2E8F0),
          ),
        );
      }),
    );
  }
}

class _RoundedHeroCard extends StatelessWidget {
  const _RoundedHeroCard({
    required this.asset,
    required this.showSecurityBadge,
  });

  final String asset;
  final bool showSecurityBadge;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: AspectRatio(
        aspectRatio: 1.05,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              asset,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
            ),
            if (showSecurityBadge)
              const Positioned(
                left: 14,
                right: 14,
                bottom: 14,
                child: _SecureChannelBadge(),
              ),
          ],
        ),
      ),
    );
  }
}

class _SecureChannelBadge extends StatelessWidget {
  const _SecureChannelBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: const Row(
        children: [
          _SecureLockIcon(),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Canal Sécurisé',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1A2740),
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Chiffrement de bout en bout actif',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF64748B),
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

class _SecureLockIcon extends StatelessWidget {
  const _SecureLockIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: const BoxDecoration(
        color: HeadsAppColors.brandAccent,
        shape: BoxShape.circle,
      ),
      child: const Icon(
        Icons.lock_rounded,
        color: Colors.white,
        size: 20,
      ),
    );
  }
}

class _PatientListIllustration extends StatelessWidget {
  const _PatientListIllustration();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 300,
      height: 340,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: 8,
            child: Opacity(
              opacity: 0.38,
              child: Transform.scale(
                scale: 0.92,
                child: _FadedPatientCard(initials: 'JD'),
              ),
            ),
          ),
          Positioned(
            bottom: 18,
            child: Opacity(
              opacity: 0.34,
              child: Transform.scale(
                scale: 0.9,
                child: _FadedPatientCard(initials: 'RB'),
              ),
            ),
          ),
          Positioned(
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                const _ActivePatientCard(),
                Positioned(
                  right: -4,
                  bottom: -4,
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1F4A88),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.18),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.add_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
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

class _FadedPatientCard extends StatelessWidget {
  const _FadedPatientCard({required this.initials});

  final String initials;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 268,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE8EDF3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: const Color(0xFFE8F2FC),
            child: Text(
              initials,
              style: const TextStyle(
                color: HeadsAppColors.brandPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 8,
                  width: 110,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 7),
                Container(
                  height: 8,
                  width: 72,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEDF2F7),
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

class _ActivePatientCard extends StatelessWidget {
  const _ActivePatientCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 286,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      decoration: BoxDecoration(
        color: HeadsAppColors.brandPrimary,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: HeadsAppColors.brandPrimary.withValues(alpha: 0.28),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: const Color(0xFF4A7FC7),
                child: const Text(
                  'ML',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 9,
                      width: 120,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 9,
                      width: 84,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.72),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.85),
                    width: 1.5,
                  ),
                ),
                child: Icon(
                  Icons.check_rounded,
                  size: 14,
                  color: Colors.white.withValues(alpha: 0.95),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _PatientActionPill(label: 'HISTORIQUE'),
              const SizedBox(width: 8),
              _PatientActionPill(label: 'ORDONNANCES'),
            ],
          ),
        ],
      ),
    );
  }
}

class _PatientActionPill extends StatelessWidget {
  const _PatientActionPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF1F4A88),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _SecureChatIllustration extends StatelessWidget {
  const _SecureChatIllustration();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 310,
      height: 210,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Positioned(
            right: 18,
            top: 8,
            child: Container(
              width: 196,
              height: 78,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
          Positioned(
            left: 34,
            top: 24,
            right: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF3FB),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: Colors.white,
                    child: Icon(
                      Icons.person_rounded,
                      color: HeadsAppColors.brandPrimary.withValues(alpha: 0.75),
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          height: 9,
                          width: 96,
                          decoration: BoxDecoration(
                            color: const Color(0xFFDCE7F5),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          height: 9,
                          width: 132,
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
            ),
          ),
          Positioned(
            left: 0,
            top: 56,
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: HeadsAppColors.brandPrimary,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: HeadsAppColors.brandPrimary.withValues(alpha: 0.25),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.chat_bubble_outline_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DoctorOnboardingBackdrop extends StatelessWidget {
  const _DoctorOnboardingBackdrop({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFF8FBFF),
            Color(0xFFFFFFFF),
            Color(0xFFF0F6FC),
          ],
          stops: [0.0, 0.55, 1.0],
        ),
      ),
      child: child,
    );
  }
}

class _DoctorOnboardingLogoCard extends StatelessWidget {
  const _DoctorOnboardingLogoCard({this.size = 96});

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

class _DoctorSplashPage extends StatelessWidget {
  const _DoctorSplashPage({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        children: [
          const Spacer(flex: 3),
          const _DoctorOnboardingLogoCard(),
          const SizedBox(height: 22),
          const HeadsAppLogoText(fontSize: 28),
          const SizedBox(height: 10),
          Text(
            "L'EXCELLENCE MÉDICALE",
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.6,
              color: HeadsAppColors.textTertiary.withValues(alpha: 0.85),
            ),
          ),
          const Spacer(flex: 4),
        ],
      ),
    );
  }
}

class _DoctorWelcomePage extends StatelessWidget {
  const _DoctorWelcomePage({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            height: 180,
            width: double.infinity,
            child: CustomPaint(
              painter: _BottomArcPainter(
                color: HeadsAppColors.brandPrimary.withValues(alpha: 0.92),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const Spacer(flex: 2),
              const _DoctorOnboardingLogoCard(size: 88),
              const SizedBox(height: 36),
              const Text(
                'Communiquez efficacement avec vos patients et suivez leurs dossiers.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF6B7C93),
                  height: 1.55,
                ),
              ),
              const Spacer(flex: 2),
              _DoctorOnboardingPrimaryButton(
                label: 'Démarrer',
                onPressed: onStart,
              ),
              const SizedBox(height: 48),
            ],
          ),
        ),
      ],
    );
  }
}

class _DoctorOnboardingPrimaryButton extends StatelessWidget {
  const _DoctorOnboardingPrimaryButton({
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
            HeadsAppColors.authGradientEnd,
            HeadsAppColors.authGradientStart,
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        boxShadow: [
          BoxShadow(
            color: HeadsAppColors.brandPrimary.withValues(alpha: 0.22),
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

class _BottomArcPainter extends CustomPainter {
  _BottomArcPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(0, size.height * 0.55)
      ..quadraticBezierTo(
        size.width * 0.5,
        -size.height * 0.15,
        size.width,
        size.height * 0.55,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _BottomArcPainter oldDelegate) =>
      oldDelegate.color != color;
}
