import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';
import '../session_keys.dart';
import 'doctor_ui_utils.dart';

/// Nom médecin affichable : préfère le profil API (déchiffré côté backend).
Future<String> resolveDoctorDisplayName({
  required String doctorId,
  String? cached,
}) async {
  var name = readableDoctorName(cached);
  if (doctorId.trim().isEmpty) return name;

  try {
    final profile = await ApiService.getDoctorProfile(doctorId);
    final fromApi = profile['fullName']?.toString();
    if (fromApi != null &&
        fromApi.trim().isNotEmpty &&
        !looksLikeEncryptedValue(fromApi)) {
      name = fromApi.trim();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kSessionDoctorNameKey, name);
    }
  } catch (_) {
    // Conserve le cache local si l'API est indisponible.
  }

  return name;
}

Future<void> cacheDoctorNameIfReadable(String? name) async {
  final trimmed = name?.trim() ?? '';
  if (trimmed.isEmpty || looksLikeEncryptedValue(trimmed)) return;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(kSessionDoctorNameKey, trimmed);
}
