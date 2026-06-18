import 'dart:async';

import 'package:flutter/material.dart';

import '../models/blood_pressure_alert.dart';
import '../models/blood_pressure_measurement.dart';
import '../services/api_service.dart';
import '../services/blood_pressure_ble_service.dart';

enum BloodPressureStatus { normal, hypotension, hypertension }

class BloodPressureProvider extends ChangeNotifier {
  BloodPressureProvider({required this.patientId});

  final String patientId;
  final BloodPressureBleService _ble = BloodPressureBleService.instance;

  bool loading = true;
  String? error;
  bool bleConnecting = false;
  String? bleStatusMessage;

  BloodPressureMeasurement? latest;
  List<BloodPressureMeasurement> history = <BloodPressureMeasurement>[];
  List<BloodPressureAlert> alerts = <BloodPressureAlert>[];
  Timer? _pollTimer;
  StreamSubscription<Map<String, int>>? _bleSub;

  bool get bleConnected => _ble.connected;

  BloodPressureStatus get status {
    final m = latest;
    if (m == null) return BloodPressureStatus.normal;
    if (m.systolic < 90 || m.diastolic < 60) return BloodPressureStatus.hypotension;
    if (m.systolic >= 140 || m.diastolic >= 90) return BloodPressureStatus.hypertension;
    return BloodPressureStatus.normal;
  }

  Future<void> initialize() async {
    _bleSub = _ble.measurements.listen(_onBleMeasurement);
    await refresh();
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (bleConnected) refresh(silent: true);
    });
  }

  Future<void> connectBle() async {
    if (bleConnecting || bleConnected) return;
    bleConnecting = true;
    error = null;
    bleStatusMessage = 'Connexion au tensiomètre…';
    notifyListeners();
    try {
      await _ble.connect();
      bleStatusMessage = _ble.statusMessage;
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '');
      bleStatusMessage = null;
      rethrow;
    } finally {
      bleConnecting = false;
      notifyListeners();
    }
  }

  Future<void> disconnectBle() async {
    await _ble.disconnect();
    bleStatusMessage = null;
    notifyListeners();
  }

  Future<void> _onBleMeasurement(Map<String, int> data) async {
    try {
      await ApiService.postBloodPressureMeasurement(
        patientId: patientId,
        systolic: data['systolic']!,
        diastolic: data['diastolic']!,
        heartRate: data['heartRate'],
        deviceName: _ble.deviceName,
      );
      await refresh(silent: true);
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
    }
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
      if (!silent) {
        error = e.toString().replaceFirst('Exception: ', '');
      }
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _bleSub?.cancel();
    super.dispose();
  }
}
