import 'package:flutter/material.dart';

import '../headsapp_theme.dart';

const _navy = Color(0xFF1A3B5D);
const _bodyGrey = Color(0xFF5F6B7A);
const _footerGrey = Color(0xFF9AA8B8);
const _successGreen = Color(0xFF22C55E);
const _badgeTeal = Color(0xFF0D9488);
const _badgeBg = Color(0xFFE6F7F5);
const _infoCardBg = Color(0xFFF3F5F8);
const _infoIconBg = Color(0xFFE8F2FC);
const _infoIconColor = Color(0xFF4A89DC);

/// Écran « Accès autorisé » affiché quand le patient sélectionne aucun symptôme grave.
class EmergencyAccessGrantedScreen extends StatelessWidget {
  const EmergencyAccessGrantedScreen({
    super.key,
    required this.onContinue,
  });

  final VoidCallback onContinue;

  static Future<void> show(
    BuildContext context, {
    required VoidCallback onContinue,
  }) {
    return Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (context, animation, secondaryAnimation) {
          return FadeTransition(
            opacity: animation,
            child: EmergencyAccessGrantedScreen(onContinue: onContinue),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.sizeOf(context);

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: size.height - 48),
              child: Column(
                children: [
                  const SizedBox(height: 40),
                  const _SuccessIcon(),
                  const SizedBox(height: 24),
                  Text(
                    'Accès autorisé',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: _navy,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: _badgeBg,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.medical_information_outlined,
                          size: 18,
                          color: _badgeTeal,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Symptômes non urgents',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: _badgeTeal,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'Votre auto-évaluation ne présente aucun signe d\'urgence immédiate. Vous pouvez désormais accéder à votre espace de suivi personnalisé.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: _bodyGrey,
                      height: 1.55,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
                    decoration: BoxDecoration(
                      color: _infoCardBg,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Column(
                      children: const [
                        _InfoRow(
                          icon: Icons.verified_user_outlined,
                          title: 'Données sécurisées',
                          description:
                              'Vos réponses ont été analysées et archivées dans votre dossier patient confidentiel.',
                        ),
                        SizedBox(height: 18),
                        _InfoRow(
                          icon: Icons.assignment_ind_outlined,
                          title: 'Prochaines étapes',
                          description:
                              'Consultez vos conseils de soin personnalisés et programmez un suivi si nécessaire.',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  _AccessGrantedButton(onPressed: onContinue),
                  const SizedBox(height: 18),
                  Text(
                    'En cas de changement brutal de votre état de santé, contactez immédiatement les services d\'urgence.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: _footerGrey,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SuccessIcon extends StatelessWidget {
  const _SuccessIcon();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 104,
      height: 104,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 104,
            height: 104,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _successGreen.withValues(alpha: 0.12),
            ),
          ),
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: _successGreen,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: _successGreen.withValues(alpha: 0.28),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Icon(
              Icons.check_rounded,
              color: Colors.white,
              size: 36,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: _infoIconBg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: _infoIconColor, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: const Color(0xFF374151),
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: _bodyGrey,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AccessGrantedButton extends StatelessWidget {
  const _AccessGrantedButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: const LinearGradient(
          colors: [
            Color(0xFFD4A5B5),
            Color(0xFF4A89DC),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: HeadsAppColors.brandPrimary.withValues(alpha: 0.32),
            blurRadius: 20,
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
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Accéder à mon espace',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.arrow_forward_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
