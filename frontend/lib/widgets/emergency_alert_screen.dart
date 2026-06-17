import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

const _alertRed = Color(0xFFC62828);
const _alertRedDark = Color(0xFFB71C1C);
const _bodyText = Color(0xFF374151);
const _sectionLabel = Color(0xFF9AA3B2);
const _retourColor = Color(0xFF8FA4C4);
const _warningBoxBg = Color(0xFFFDECEC);

/// Écran d'alerte d'urgence affiché lors de la sélection d'un symptôme grave.
class EmergencyAlertScreen extends StatelessWidget {
  const EmergencyAlertScreen({
    super.key,
    required this.onRetour,
  });

  final VoidCallback onRetour;

  static Future<void> show(BuildContext context, {required VoidCallback onRetour}) {
    return Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (context, animation, secondaryAnimation) {
          return FadeTransition(
            opacity: animation,
            child: EmergencyAlertScreen(onRetour: onRetour),
          );
        },
      ),
    );
  }

  Future<void> _callEmergency(String number) async {
    final uri = Uri(scheme: 'tel', path: number);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.sizeOf(context);

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFF8F5F5),
              Color(0xFFF0D4D4),
              Color(0xFFE5B5B5),
            ],
            stops: [0.0, 0.55, 1.0],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: size.height - 48),
              child: Column(
                children: [
                  const SizedBox(height: 36),
                  const _EmergencyAlertIcon(),
                  const SizedBox(height: 22),
                  Text(
                    'Alerte d\'urgence',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: _alertRedDark,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: _alertRed.withValues(alpha: 0.08),
                          blurRadius: 24,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Text(
                          'Votre sécurité est notre priorité. Pour des raisons de santé immédiates, l\'accès à l\'application a été suspendu.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: _bodyText,
                            height: 1.55,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: _warningBoxBg,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            'Veuillez contacter immédiatement un service d\'urgence',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: const Color(0xFF1F2937),
                              fontWeight: FontWeight.w800,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'NUMÉROS D\'URGENCE (TUNIS)',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: _sectionLabel,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _EmergencyNumberPill(
                    number: '190',
                    label: 'Urgence Tunisienne',
                    onTap: () => _callEmergency('190'),
                  ),
                  const SizedBox(height: 48),
                  TextButton(
                    onPressed: onRetour,
                    style: TextButton.styleFrom(
                      foregroundColor: _retourColor,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                    child: Text(
                      'Retour',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: _retourColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
      ),
    );
  }
}

class _EmergencyAlertIcon extends StatelessWidget {
  const _EmergencyAlertIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 76,
      height: 76,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: _alertRed.withValues(alpha: 0.12),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Center(
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: _alertRed,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.priority_high_rounded,
            color: Colors.white,
            size: 30,
          ),
        ),
      ),
    );
  }
}

class _EmergencyNumberPill extends StatelessWidget {
  const _EmergencyNumberPill({
    required this.number,
    required this.label,
    required this.onTap,
  });

  final String number;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 0,
      shadowColor: Colors.black.withValues(alpha: 0.06),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: _bodyText,
                    fontWeight: FontWeight.w500,
                  ),
              children: [
                TextSpan(
                  text: number,
                  style: const TextStyle(
                    color: _alertRed,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                TextSpan(text: '  $label'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
