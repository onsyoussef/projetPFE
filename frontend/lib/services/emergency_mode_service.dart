import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Persistance du mode urgence (24 h de blocage de l'espace patient).
class EmergencyModeService {
  EmergencyModeService._();

  static const Duration lockDuration = Duration(hours: 24);

  static const String _keyActive = 'emergency_mode_active';
  static const String _keyStartedAt = 'emergency_mode_started_at';
  static const String _keySymptoms = 'emergency_mode_symptoms';
  static const String lastRouteKey = 'emergency_dashboard';

  static Future<void> activate({
    required List<Map<String, String>> symptoms,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyActive, true);
    await prefs.setString(_keyStartedAt, DateTime.now().toIso8601String());
    await prefs.setString(_keySymptoms, jsonEncode(symptoms));
    await prefs.setString('lastRoute', lastRouteKey);
  }

  static Future<bool> isActive() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_keyActive) != true) return false;
    final startedAt = await startedAtTime();
    if (startedAt == null) return false;
    return DateTime.now().difference(startedAt) < lockDuration;
  }

  static Future<DateTime?> startedAtTime() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyStartedAt);
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  static Future<Duration> remainingLockTime() async {
    final startedAt = await startedAtTime();
    if (startedAt == null) return Duration.zero;
    final elapsed = DateTime.now().difference(startedAt);
    final remaining = lockDuration - elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  static Future<bool> canAccessEspace() async {
    final remaining = await remainingLockTime();
    return remaining == Duration.zero;
  }

  static Future<List<Map<String, String>>> symptomsWithTimes() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keySymptoms);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => Map<String, String>.from(e as Map))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyActive);
    await prefs.remove(_keyStartedAt);
    await prefs.remove(_keySymptoms);
  }
}
