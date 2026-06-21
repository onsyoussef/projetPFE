import 'package:shared_preferences/shared_preferences.dart';

/// Catégories du tableau de bord médecin (badges « nouveautés »).
enum DoctorDashboardCategory {
  demande,
  formulaire,
}

/// Dernière fois que le médecin a ouvert la liste d’une catégorie (décrémente le badge).
class DoctorCategoryBadgeStorage {
  DoctorCategoryBadgeStorage._();

  static String _key(String doctorId, DoctorDashboardCategory c) {
    final s = switch (c) {
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
