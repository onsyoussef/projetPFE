import 'package:flutter/material.dart';

import 'gradient_button.dart';

import '../headsapp_theme.dart';

const _titleColor = Color(0xFF111827);
const _bodyGrey = Color(0xFF6B7280);
const _powerBlue = Color(0xFF265AA6);
const _powerCircleBg = Color(0xFFEEF2F7);
const _secondaryBtnBg = Color(0xFFF3F4F6);
const _secondaryBtnText = Color(0xFF374151);

/// Popup de confirmation avant déconnexion patient.
Future<bool> showPatientLogoutDialog(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (dialogContext) {
      return Dialog(
        backgroundColor: Colors.white,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  color: _powerCircleBg,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.power_settings_new_rounded,
                  color: _powerBlue,
                  size: 32,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Se déconnecter ?',
                textAlign: TextAlign.center,
                style: Theme.of(dialogContext).textTheme.titleLarge?.copyWith(
                      color: _titleColor,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
              ),
              const SizedBox(height: 10),
              Text(
                'Êtes-vous sûr de vouloir\nvous déconnecter ?',
                textAlign: TextAlign.center,
                style: Theme.of(dialogContext).textTheme.bodyMedium?.copyWith(
                      color: _bodyGrey,
                      height: 1.45,
                    ),
              ),
              const SizedBox(height: 26),
              HeadsAppGradientButton(
                label: 'Annuler',
                height: 52,
                onPressed: () => Navigator.of(dialogContext).pop(false),
              ),
              const SizedBox(height: 12),
              _LogoutSecondaryButton(
                label: 'Se déconnecter',
                onPressed: () => Navigator.of(dialogContext).pop(true),
              ),
            ],
          ),
        ),
      );
    },
  );
  return result == true;
}
class _LogoutSecondaryButton extends StatelessWidget {
  const _LogoutSecondaryButton({
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _secondaryBtnBg,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(999),
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: Center(
            child: Text(
              label,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: _secondaryBtnText,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}
