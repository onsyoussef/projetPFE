import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../chat_page.dart';
import '../screens/doctor_profile_patient_page.dart';
import '../services/api_service.dart';
import '../utils/patient_ui_utils.dart';

const _titleNavy = Color(0xFF1A458B);
const _titleColor = Color(0xFF111827);
const _bodyGrey = Color(0xFF6B7280);
const _onlineGreen = Color(0xFF2ECC71);

String _displayDoctorName(String fullName) {
  final trimmed = fullName.trim();
  if (trimmed.isEmpty) return 'Dr. —';
  final lower = trimmed.toLowerCase();
  if (lower.startsWith('dr.') || lower.startsWith('dr ')) return trimmed;
  return 'Dr. $trimmed';
}

/// Popup « Que souhaitez-vous faire ? » après « Voir plus » sur une carte médecin.
Future<void> showDoctorInteractionDialog(
  BuildContext context, {
  required Map<String, dynamic> doctor,
  required String patientId,
}) {
  final fullName = readableDoctorName(doctor['fullName'] as String?, fallback: '—');
  final displayName = _displayDoctorName(fullName);
  final doctorId = doctor['id']?.toString() ?? '';
  final photoPath = doctor['photoPath']?.toString();
  final photoUrl = ApiService.resolveMediaUrlOrNull(photoPath);
  final isOnline = (doctor['status'] as String? ?? 'available') == 'available';

  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (dialogContext) {
      return Dialog(
        backgroundColor: Colors.white,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  ClipOval(
                    child: Container(
                      width: 88,
                      height: 88,
                      color: const Color(0xFFE8F0FE),
                      child: photoUrl != null
                          ? Image.network(
                              photoUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.person_rounded,
                                color: _titleNavy,
                                size: 44,
                              ),
                            )
                          : const Icon(
                              Icons.person_rounded,
                              color: _titleNavy,
                              size: 44,
                            ),
                    ),
                  ),
                  if (isOnline)
                    Positioned(
                      right: 2,
                      bottom: 2,
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: _onlineGreen,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2.5),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 22),
              Text(
                'Que souhaitez-vous faire ?',
                textAlign: TextAlign.center,
                style: Theme.of(dialogContext).textTheme.titleLarge?.copyWith(
                      color: _titleColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                      letterSpacing: -0.3,
                    ),
              ),
              const SizedBox(height: 10),
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: Theme.of(dialogContext).textTheme.bodyMedium?.copyWith(
                        color: _bodyGrey,
                        height: 1.45,
                        fontWeight: FontWeight.w500,
                      ),
                  children: [
                    const TextSpan(
                      text: 'Vous êtes sur le point d\'interagir avec le profil du ',
                    ),
                    TextSpan(
                      text: '$displayName.',
                      style: const TextStyle(
                        color: _titleNavy,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _GradientActionButton(
                icon: Icons.person_outline_rounded,
                label: 'Voir le profil',
                onTap: () async {
                  Navigator.of(dialogContext).pop();
                  if (!context.mounted) return;
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => DoctorProfilePatientPage(
                        doctor: doctor,
                        patientId: patientId,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              _OutlinedActionButton(
                icon: Icons.chat_bubble_outline_rounded,
                label: 'Lancer une conversation',
                onTap: () async {
                  Navigator.of(dialogContext).pop();
                  if (doctorId.isEmpty || !context.mounted) return;
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString('lastRoute', 'chat');
                  await prefs.setString('chatDoctorId', doctorId);
                  await prefs.setString('chatDoctorName', fullName);
                  if (!context.mounted) return;
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ChatPage(
                        patientId: patientId,
                        doctorId: doctorId,
                        doctorName: fullName,
                        doctorPhotoPath: photoPath,
                      ),
                    ),
                  );
                  if (!context.mounted) return;
                  await prefs.remove('lastRoute');
                  await prefs.remove('chatDoctorId');
                  await prefs.remove('chatDoctorName');
                  await prefs.remove('chatDoctorPhotoPath');
                },
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text(
                  'Annuler',
                  style: TextStyle(
                    color: _bodyGrey,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _GradientActionButton extends StatelessWidget {
  const _GradientActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: const LinearGradient(
          colors: [
            Color(0xFFE8719A),
            Color(0xFF3B5998),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3B5998).withValues(alpha: 0.22),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                children: [
                  Icon(icon, color: Colors.white, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OutlinedActionButton extends StatelessWidget {
  const _OutlinedActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                children: [
                  Icon(icon, color: _titleNavy, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: _titleNavy,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: _titleNavy,
                    size: 16,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
