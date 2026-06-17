import 'dart:async';

import 'package:flutter/material.dart';

import '../models/blood_pressure_alert.dart';
import '../models/blood_pressure_measurement.dart';
import '../services/api_service.dart';

enum BloodPressureStatus { normal, hypotension, hypertension }

class BloodPressureProvider extends ChangeNotifier {
  BloodPressureProvider({required this.patientId});

  final String patientId;

  bool loading = true;
  String? error;
  bool deviceConnected = false;
  BloodPressureMeasurement? latest;
  List<BloodPressureMeasurement> history = <BloodPressureMeasurement>[];
  List<BloodPressureAlert> alerts = <BloodPressureAlert>[];
  Timer? _pollTimer;

  BloodPressureStatus get status {
    final m = latest;
    if (m == null) return BloodPressureStatus.normal;
    if (m.systolic < 90 || m.diastolic < 60) return BloodPressureStatus.hypotension;
    if (m.systolic >= 140 || m.diastolic >= 90) return BloodPressureStatus.hypertension;
    return BloodPressureStatus.normal;
  }

  Future<void> initialize() async {
    await refresh();
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      refresh(silent: true);
    });
  }

  Future<void> refresh({bool silent = false}) async {
    if (!silent) {
      loading = true;
      error = null;
      notifyListeners();
    }
    try {
      final latestJson = await ApiService.getPatientBloodPressureLatest(patientId: patientId);
      final historyJson = await ApiService.getPatientBloodPressureHistory(patientId: patientId);
      final alertsJson = await ApiService.getPatientBloodPressureAlerts(patientId: patientId);

      latest = latestJson == null ? null : BloodPressureMeasurement.fromJson(latestJson);
      deviceConnected = latestJson != null;
      history = historyJson
          .map((e) => BloodPressureMeasurement.fromJson(e))
          .toList()
        ..sort((a, b) => b.measuredAt.compareTo(a.measuredAt));
      alerts = alertsJson
          .map((e) => BloodPressureAlert.fromJson(e))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      error = null;
    } catch (e) {
      // Fallback UI de démo pour ne pas bloquer l’intégration frontend
      final now = DateTime.now();
      latest = BloodPressureMeasurement(
        systolic: 132,
        diastolic: 84,
        heartRate: 76,
        measuredAt: now,
      );
      history = [
        latest!,
        BloodPressureMeasurement(
          systolic: 126,
          diastolic: 80,
          heartRate: 72,
          measuredAt: now.subtract(const Duration(hours: 5)),
        ),
        BloodPressureMeasurement(
          systolic: 142,
          diastolic: 92,
          heartRate: 81,
          measuredAt: now.subtract(const Duration(days: 1)),
        ),
      ];
      alerts = [
        BloodPressureAlert(
          type: 'high',
          message: 'Tension élevée détectée',
          severity: 'high',
          createdAt: now.subtract(const Duration(days: 1)),
        ),
      ];
      deviceConnected = true;
      error = 'Backend tensiomètre non disponible pour le moment.';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}

