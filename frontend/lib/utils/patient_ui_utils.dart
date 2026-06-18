import 'package:flutter/material.dart';

import '../headsapp_theme.dart';
import '../services/api_service.dart';

/// Détecte une valeur chiffrée AES-256-GCM (`iv:authTag:cipher` en hex).
bool looksLikeEncryptedValue(String? value) {
  if (value == null || value.trim().isEmpty) return false;
  final parts = value.split(':');
  if (parts.length != 3) return false;
  final hex = RegExp(r'^[0-9a-fA-F]+$');
  return parts.every((part) => part.isNotEmpty && hex.hasMatch(part));
}

/// Nom affichable : évite d'exposer une chaîne chiffrée brute à l'utilisateur.
String readablePatientName(String? value, {String fallback = 'Patient'}) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty || looksLikeEncryptedValue(trimmed)) return fallback;
  return trimmed;
}

/// Champ texte issu de l'API : masque les valeurs encore chiffrées.
String readableDecryptedField(String? value, {String fallback = ''}) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty || looksLikeEncryptedValue(trimmed)) return fallback;
  return trimmed;
}

/// Nom médecin (fullName déchiffré par le backend).
String readableDoctorName(String? value, {String fallback = 'Médecin'}) {
  return readableDecryptedField(value, fallback: fallback);
}

/// Lit un champ déchiffré depuis une réponse JSON API.
String readApiField(
  Map<String, dynamic>? json,
  String key, {
  String fallback = '',
}) {
  if (json == null) return fallback;
  return readableDecryptedField(json[key]?.toString(), fallback: fallback);
}

String doctorInitials(String name) {
  final parts =
      name.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) {
    return parts[0].substring(0, 1).toUpperCase();
  }
  return (parts[0].substring(0, 1) + parts[parts.length - 1].substring(0, 1))
      .toUpperCase();
}

/// Avatar médecin côté patient : photo réseau si disponible, sinon initiales.
Widget doctorAvatarForPatient({
  required String name,
  String? doctorPhotoPath,
  double radius = 24,
  Color backgroundColor = HeadsAppColors.surfaceSoft,
  Color accentColor = HeadsAppColors.brandPrimary,
  Widget? fallbackChild,
}) {
  final url = ApiService.resolveMediaUrlOrNull(doctorPhotoPath);
  final hasUrl = url != null;
  return CircleAvatar(
    radius: radius,
    backgroundColor: backgroundColor,
    backgroundImage: hasUrl ? NetworkImage(url) : null,
    onBackgroundImageError: hasUrl ? (_, _) {} : null,
    child: hasUrl
        ? null
        : (fallbackChild ??
            Text(
              doctorInitials(name),
              style: TextStyle(
                color: accentColor,
                fontWeight: FontWeight.w600,
                fontSize: radius * 0.9,
              ),
            )),
  );
}
