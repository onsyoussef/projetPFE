import 'package:flutter/material.dart';

import '../headsapp_theme.dart';
import '../services/api_service.dart';

/// Détecte une valeur chiffrée AES-256-GCM (`iv:authTag:cipher` en hex).
/// Aligné sur `backend/services/cryptoService.js`.
bool looksLikeEncryptedValue(String? value) {
  if (value == null || value.trim().isEmpty) return false;
  final parts = value.split(':');
  if (parts.length != 3) return false;
  final hex = RegExp(r'^[0-9a-fA-F]+$');
  return parts.every((part) => part.isNotEmpty && hex.hasMatch(part));
}

/// Champ texte issu de l'API : masque les valeurs encore chiffrées.
String readableDecryptedField(String? value, {String fallback = ''}) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty || looksLikeEncryptedValue(trimmed)) return fallback;
  return trimmed;
}

/// Nom patient (fullName déchiffré côté backend).
String readablePatientName(String? value, {String fallback = 'Patient'}) {
  return readableDecryptedField(value, fallback: fallback);
}

/// Nom médecin (fullName déchiffré côté backend).
String readableDoctorName(String? value, {String fallback = 'Médecin'}) {
  return readableDecryptedField(value, fallback: fallback);
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

List<String> conversationTags(dynamic raw) {
  if (raw is! List) return [];
  return raw.map((e) => e.toString()).toList();
}

bool isUrgentConversation(List<String> tags) => tags.contains('urgent');

bool isDemandeConversation(List<String> tags) => tags.contains('demande');

/// Aperçu sur 2 lignes (texte brut, tronqué).
String doctorFormBodyPreview(String raw, {int maxChars = 140}) {
  final lines = raw
      .replaceAll('\r\n', '\n')
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .take(2)
      .join('\n');
  if (lines.length <= maxChars) return lines;
  return '${lines.substring(0, maxChars).trim()}…';
}

/// Avatar patient côté médecin : photo réseau si disponible, sinon initiales.
Widget patientAvatarForDoctor({
  required String name,
  String? patientPhotoPath,
  double radius = 22,
  Color backgroundColor = HeadsAppColors.surfaceSoft,
  Color accentColor = HeadsAppColors.brandPrimary,
}) {
  final url = ApiService.resolveMediaUrl(patientPhotoPath);
  final hasUrl = url.isNotEmpty;
  return CircleAvatar(
    radius: radius,
    backgroundColor: backgroundColor,
    backgroundImage: hasUrl ? NetworkImage(url) : null,
    onBackgroundImageError: hasUrl ? (_, _) {} : null,
    child: hasUrl
        ? null
        : Text(
            doctorInitials(name),
            style: TextStyle(
              color: accentColor,
              fontWeight: FontWeight.w600,
              fontSize: radius * 0.9,
            ),
          ),
  );
}
