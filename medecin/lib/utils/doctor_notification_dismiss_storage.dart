import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Mémorise pour chaque conversation le dernier `lastMessageAt` « vu / effacé »
/// par le médecin. Une nouvelle activité (timestamp plus récent) refait apparaître la notif.
class DoctorNotificationDismissStorage {
  DoctorNotificationDismissStorage._();

  static String _key(String doctorId) => 'doctor_notif_dismiss_$doctorId';

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

/// True si la conversation est masquée (déjà effacée pour ce [lastMessageAt] ou plus ancien).
bool notificationDismissedForConversation(
  Map<String, dynamic> conversation,
  Map<String, String> dismissedLastMessageAtByConvId,
) {
  final id = conversation['conversationId']?.toString() ?? '';
  if (id.isEmpty) return false;
  final stored = dismissedLastMessageAtByConvId[id];
  if (stored == null) return false;
  final cut = DateTime.tryParse(stored)?.toUtc();
  if (cut == null) return true;
  final raw = conversation['lastMessageAt'];
  if (raw == null) return true;
  final last = DateTime.tryParse(raw.toString())?.toUtc();
  if (last == null) return true;
  return !last.isAfter(cut);
}

String notificationDismissSnapshotIso(Map<String, dynamic> conversation) {
  final raw = conversation['lastMessageAt'];
  if (raw != null) {
    final dt = DateTime.tryParse(raw.toString());
    if (dt != null) return dt.toUtc().toIso8601String();
  }
  return DateTime.now().toUtc().toIso8601String();
}
