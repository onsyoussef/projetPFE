import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';
import 'patient_ui_utils.dart';

/// Nom patient affichable : préfère le profil API (déchiffré côté backend).
Future<String> resolvePatientDisplayName({
  required String patientId,
  String? cached,
}) async {
  var name = readablePatientName(cached);
  if (patientId.trim().isEmpty) return name;

  try {
    final profile = await ApiService.getPatientProfile(patientId: patientId);
    final fromApi = profile['fullName'] as String?;
    if (fromApi != null &&
        fromApi.trim().isNotEmpty &&
        !looksLikeEncryptedValue(fromApi)) {
      name = fromApi.trim();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('patientName', name);
    }
  } catch (_) {
    // Conserve le cache local si l'API est indisponible.
  }

  return name;
}

/// Lit le nom patient depuis le cache local en masquant une valeur chiffrée.
Future<String> readCachedPatientName({String fallback = 'Patient'}) async {
  final prefs = await SharedPreferences.getInstance();
  return readablePatientName(prefs.getString('patientName'), fallback: fallback);
}

/// Enregistre un nom patient uniquement s'il est lisible (pas chiffré brut).
Future<void> cachePatientNameIfReadable(String? name) async {
  final trimmed = name?.trim() ?? '';
  if (trimmed.isEmpty || looksLikeEncryptedValue(trimmed)) return;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('patientName', trimmed);
}
