import 'package:shared_preferences/shared_preferences.dart';

/// Catégories du tableau de bord médecin (badges « nouveautés »).
enum DoctorDashboardCategory {
  urgence,
  demande,
  formulaire,
}

/// Dernière fois que le médecin a ouvert la liste d’une catégorie (décrémente le badge).
class DoctorCategoryBadgeStorage {
  DoctorCategoryBadgeStorage._();

  static String _key(String doctorId, DoctorDashboardCategory c) {
    final s = switch (c) {
      DoctorDashboardCategory.urgence => 'urgence',
      DoctorDashboardCategory.demande => 'demande',
      DoctorDashboardCategory.formulaire => 'formulaire',
    };
    return 'doctor_dashboard_last_view_${doctorId}_$s';
  }

  static Future<DateTime?> lastConsultedUtc(
    String doctorId,
    DoctorDashboardCategory category,
  ) async {
    if (doctorId.isEmpty) return null;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(doctorId, category));
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  static Future<void> markConsultedNow(
    String doctorId,
    DoctorDashboardCategory category,
  ) async {
    if (doctorId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key(doctorId, category),
      DateTime.now().toUtc().toIso8601String(),
    );
  }
}

/// Nombre d’éléments dont `createdAt` est strictement après la dernière consultation.
/// Si [lastConsultedUtc] est null (jamais ouvert), tout le monde compte comme « à voir ».
int countDashboardItemsSince(
  List<Map<String, dynamic>> items,
  DateTime? lastConsultedUtc,
) {
  if (lastConsultedUtc == null) return items.length;
  final threshold = lastConsultedUtc.toUtc();
  var n = 0;
  for (final it in items) {
    final raw = it['createdAt'];
    if (raw == null) continue;
    final dt = DateTime.tryParse(raw.toString());
    if (dt == null) continue;
    if (dt.toUtc().isAfter(threshold)) n++;
  }
  return n;
}
