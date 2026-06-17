import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Mémorise les sessions salle d’attente « vues / effacées » (clé = conversationId,
/// valeur = `enteredAtMs` de la session). Survit aux reconnexions et déconnexions.
class DoctorWaitingRoomDismissStorage {
  DoctorWaitingRoomDismissStorage._();

  static String _key(String doctorId) => 'doctor_waiting_dismiss_$doctorId';

  static Future<Map<String, String>> getMap(String doctorId) async {
    if (doctorId.isEmpty) return {};
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(doctorId));
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return Map<String, String>.from(
          decoded.map((k, v) => MapEntry(k.toString(), v.toString())),
        );
      }
    } catch (_) {}
    return {};
  }

  static Future<void> merge(
    String doctorId,
    Map<String, String> updates,
  ) async {
    if (doctorId.isEmpty || updates.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final current = await getMap(doctorId);
    current.addAll(updates);
    await prefs.setString(_key(doctorId), jsonEncode(current));
  }
}

bool waitingRoomSessionDismissed(
  String conversationId,
  int enteredAtMs,
  Map<String, String> dismissedEnteredAtByConvId,
) {
  final stored = dismissedEnteredAtByConvId[conversationId];
  return stored != null && stored == '$enteredAtMs';
}
