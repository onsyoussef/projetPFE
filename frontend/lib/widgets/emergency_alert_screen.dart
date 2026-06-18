import 'package:flutter/material.dart';

const _pageBg = Color(0xFFFFF0F3);
const _alertRed = Color(0xFFC62828);
const _alertRedDark = Color(0xFFB71C1C);
const _bodyText = Color(0xFF374151);
const _warningBoxBg = Color(0xFFFCE7F3);
const _warningText = Color(0xFFB91C1C);
const _buttonText = Color(0xFF1A2740);

/// Écran d'alerte d'urgence affiché lors de la sélection d'un symptôme grave.
class EmergencyAlertScreen extends StatelessWidget {
  const EmergencyAlertScreen({
    super.key,
    required this.onAcknowledge,
  });

  final VoidCallback onAcknowledge;

  static Future<void> show(
    BuildContext context, {
    required VoidCallback onAcknowledge,
  }) {
    return Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (context, animation, secondaryAnimation) {
          return FadeTransition(
            opacity: animation,
            child: EmergencyAlertScreen(onAcknowledge: onAcknowledge),
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
        backgroundColor: _pageBg,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: size.height - 48),
              child: Column(
                children: [
                  const SizedBox(height: 48),
                  const _EmergencyAlertIcon(),
                  const SizedBox(height: 24),
                  Text(
                    'Alerte d\'urgence',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: _alertRedDark,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                      fontSize: 26,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(22, 26, 22, 20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: _alertRed.withValues(alpha: 0.06),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
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
                            fontSize: 15,
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
                              color: _warningText,
                              fontWeight: FontWeight.w800,
                              height: 1.35,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  Material(
                    color: Colors.white,
                    elevation: 0,
                    shadowColor: Colors.black.withValues(alpha: 0.08),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: InkWell(
                      onTap: onAcknowledge,
                      borderRadius: BorderRadius.circular(999),
                      child: Container(
                        width: double.infinity,
                        height: 54,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Text(
                          'Je comprends',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: _buttonText,
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                      ),
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

class _EmergencyAlertIcon extends StatelessWidget {
  const _EmergencyAlertIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: _alertRed.withValues(alpha: 0.10),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Center(
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: _alertRed,
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: const Text(
            '!',
            style: TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}
