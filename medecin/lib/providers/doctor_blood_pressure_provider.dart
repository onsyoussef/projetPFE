import 'dart:async';

import 'package:flutter/material.dart';

import '../models/doctor_blood_pressure_alert.dart';
import '../models/doctor_blood_pressure_measurement.dart';
import '../models/doctor_patient_brief.dart';
import '../services/api_service.dart';

class DoctorBloodPressureProvider extends ChangeNotifier {
  DoctorBloodPressureProvider({required this.doctorId});

  final String doctorId;

  bool loading = true;
  String? error;
  List<DoctorPatientBrief> patients = <DoctorPatientBrief>[];
  List<DoctorBloodPressureMeasurement> measurements = <DoctorBloodPressureMeasurement>[];
  List<DoctorBloodPressureAlert> alerts = <DoctorBloodPressureAlert>[];
  Timer? _pollTimer;

  Future<void> initialize() async {
    await refresh();
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 12), (_) {
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
      final patientsJson = await ApiService.getDoctorTensiometerPatients(doctorId: doctorId);
      final measuresJson = await ApiService.getDoctorBloodPressureMeasurements(
        doctorId: doctorId,
      );
      final alertsJson = await ApiService.getDoctorBloodPressureAlerts(doctorId: doctorId);

      patients = patientsJson.map(DoctorPatientBrief.fromJson).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      measurements = measuresJson.map(DoctorBloodPressureMeasurement.fromJson).toList()
        ..sort((a, b) => b.measuredAt.compareTo(a.measuredAt));
      alerts = alertsJson.map(DoctorBloodPressureAlert.fromJson).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      error = null;
    } catch (_) {
      // Fallback demo data en attendant le backend final.
      final now = DateTime.now();
      patients = [
        DoctorPatientBrief(id: 'p1', name: 'Amine Ben Salah'),
        DoctorPatientBrief(id: 'p2', name: 'Meriem Trabelsi'),
      ];
      measurements = [
        DoctorBloodPressureMeasurement(
          patientId: 'p1',
          patientName: 'Amine Ben Salah',
          systolic: 145,
          diastolic: 92,
          heartRate: 88,
          measuredAt: now.subtract(const Duration(minutes: 20)),
        ),
        DoctorBloodPressureMeasurement(
          patientId: 'p1',
          patientName: 'Amine Ben Salah',
          systolic: 138,
          diastolic: 86,
          heartRate: 80,
          measuredAt: now.subtract(const Duration(hours: 3)),
        ),
        DoctorBloodPressureMeasurement(
          patientId: 'p2',
          patientName: 'Meriem Trabelsi',
          systolic: 88,
          diastolic: 56,
          heartRate: 68,
          measuredAt: now.subtract(const Duration(hours: 2)),
        ),
        DoctorBloodPressureMeasurement(
          patientId: 'p2',
          patientName: 'Meriem Trabelsi',
          systolic: 110,
          diastolic: 70,
          heartRate: 74,
          measuredAt: now.subtract(const Duration(days: 1)),
        ),
      ];
      alerts = [
        DoctorBloodPressureAlert(
          patientId: 'p1',
          patientName: 'Amine Ben Salah',
          type: 'Hypertension',
          systolic: 145,
          diastolic: 92,
          createdAt: now.subtract(const Duration(minutes: 20)),
        ),
        DoctorBloodPressureAlert(
          patientId: 'p2',
          patientName: 'Meriem Trabelsi',
          type: 'Hypotension',
          systolic: 88,
          diastolic: 56,
          createdAt: now.subtract(const Duration(hours: 2)),
        ),
      ];
      error = 'Données tensiomètre en mode démo (backend non disponible).';
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
