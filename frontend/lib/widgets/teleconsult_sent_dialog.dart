import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../discussions_patient_page.dart';
import '../headsapp_theme.dart';
import '../utils/patient_ui_utils.dart';

enum TeleconsultSentDialogKind { request, form }

const _titleNavy = Color(0xFF1A458B);
const _primaryBlue = Color(0xFF2E5AAC);
const _bodyGrey = Color(0xFF4B5563);
const _successGreen = Color(0xFF16A34A);
const _successGreenBg = Color(0xFFD1FAE5);

/// Popup de confirmation après envoi d'une demande ou d'un formulaire téléconsultation.
Future<void> showTeleconsultSentDialog(
  BuildContext context, {
  required TeleconsultSentDialogKind kind,
  required String patientId,
}) {
  final title = kind == TeleconsultSentDialogKind.request
      ? 'Demande envoyée'
      : 'Formulaire envoyé';

  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (dialogContext) {
      Future<void> openMessages() async {
        Navigator.of(dialogContext).pop();
        if (!context.mounted) return;
        final prefs = await SharedPreferences.getInstance();
        final patientName = readablePatientName(prefs.getString('patientName'));
        final photoPath = prefs.getString('patientPhotoPath');
        if (!context.mounted) return;
        await Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute<void>(
            builder: (_) => DiscussionsPatientPage(
              patientId: patientId,
              patientName: patientName,
              patientPhotoPath: photoPath,
            ),
          ),
          (route) => route.isFirst,
        );
      }

      return Dialog(
        backgroundColor: Colors.white,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.bottomCenter,
                children: [
                  Container(
                    height: 76,
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      gradient: HeadsAppColors.primaryButtonGradient,
                    ),
                  ),
                  Positioned(
                    bottom: -34,
                    child: Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Container(
                          width: 50,
                          height: 50,
                          decoration: const BoxDecoration(
                            color: _successGreenBg,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check_rounded,
                            color: _successGreen,
                            size: 30,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 48),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(dialogContext).textTheme.titleLarge?.copyWith(
                        color: _titleNavy,
                        fontWeight: FontWeight.w800,
                        fontSize: 22,
                        letterSpacing: -0.3,
                      ),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: Theme.of(dialogContext).textTheme.bodyMedium?.copyWith(
                          color: _bodyGrey,
                          height: 1.5,
                          fontSize: 14.5,
                        ),
                    children: [
                      const TextSpan(
                        text:
                            'Votre demande a été envoyée. Un professionnel vous répondra sous peu dans l\'onglet ',
                      ),
                      TextSpan(
                        text: 'Messages',
                        style: const TextStyle(
                          color: _titleNavy,
                          fontWeight: FontWeight.w800,
                          decoration: TextDecoration.underline,
                          decorationColor: _titleNavy,
                        ),
                        recognizer: TapGestureRecognizer()..onTap = openMessages,
                      ),
                      const TextSpan(text: '.'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    style: FilledButton.styleFrom(
                      backgroundColor: _primaryBlue,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Fermer',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text(
                  'Voir mes demandes',
                  style: TextStyle(
                    color: _titleNavy,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      );
    },
  );
}
