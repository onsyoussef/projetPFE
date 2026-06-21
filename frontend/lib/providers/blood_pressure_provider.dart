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
  final BloodPressureBleService _ble = BloodPressureBleService();

  bool loading = true;
  String? error;

  bool bleConnecting = false;
  bool bleConnected = false;
  String? bleError;

  BloodPressureMeasurement? latest;
  BloodPressureBleReading? liveReading;
  List<BloodPressureMeasurement> history = <BloodPressureMeasurement>[];
  List<BloodPressureAlert> alerts = <BloodPressureAlert>[];

  Timer? _pollTimer;
  StreamSubscription<BloodPressureBleReading>? _bleSub;
  DateTime? _lastPostedAt;
  String? _lastPostedKey;

  BloodPressureStatus get status {
    final m = _displayMeasurement;
    if (m == null) return BloodPressureStatus.normal;
    if (m.systolic < 90 || m.diastolic < 60) return BloodPressureStatus.hypotension;
    if (m.systolic >= 140 || m.diastolic >= 90) return BloodPressureStatus.hypertension;
    return BloodPressureStatus.normal;
  }

  BloodPressureMeasurement? get _displayMeasurement {
    final live = liveReading;
    if (live != null) {
      return BloodPressureMeasurement(
        systolic: live.systolic,
        diastolic: live.diastolic,
        meanArterialPressure: live.meanArterialPressure,
        measuredAt: live.measuredAt,
      );
    }
    return latest;
  }

  BloodPressureMeasurement? get displayMeasurement => _displayMeasurement;

  bool get bleSupported => BloodPressureBleService.isSupported;

  Future<void> initialize() async {
    await refresh();
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      refresh(silent: true);
    });
  }

  Future<void> connectBle() async {
    if (!bleSupported) {
      bleError = 'Bluetooth indisponible sur cette plateforme.';
      notifyListeners();
      return;
    }
    if (bleConnecting) return;

    bleConnecting = true;
    bleError = null;
    notifyListeners();

    try {
      await _ble.connect();
      bleConnected = true;
      bleError = null;

      await _bleSub?.cancel();
      _bleSub = _ble.readings.listen(_onBleReading);
    } catch (e) {
      bleConnected = false;
      bleError = e.toString().replaceFirst('Exception: ', '');
    } finally {
      bleConnecting = false;
      notifyListeners();
    }
  }

  Future<void> disconnectBle() async {
    await _bleSub?.cancel();
    _bleSub = null;
    await _ble.disconnect();
    bleConnected = false;
    bleConnecting = false;
    liveReading = null;
    notifyListeners();
  }

  void _onBleReading(BloodPressureBleReading reading) {
    liveReading = reading;
    latest = BloodPressureMeasurement(
      systolic: reading.systolic,
      diastolic: reading.diastolic,
      meanArterialPressure: reading.meanArterialPressure,
      measuredAt: reading.measuredAt,
    );
    notifyListeners();
    unawaited(_postBleReading(reading));
  }

  Future<void> _postBleReading(BloodPressureBleReading reading) async {
    final key =
        '${reading.systolic}/${reading.diastolic}/${reading.meanArterialPressure ?? 0}';
    final now = DateTime.now();
    if (_lastPostedKey == key &&
        _lastPostedAt != null &&
        now.difference(_lastPostedAt!) < const Duration(seconds: 4)) {
      return;
    }

    try {
      await ApiService.postBloodPressureMeasurement(
        patientId: patientId,
        systolic: reading.systolic,
        diastolic: reading.diastolic,
        meanArterialPressure: reading.meanArterialPressure,
        source: 'ble_esp32',
        deviceName: BloodPressureBleService.deviceName,
        measuredAt: reading.measuredAt,
      );
      _lastPostedKey = key;
      _lastPostedAt = now;
      await refresh(silent: true);
    } catch (e) {
      bleError = e.toString().replaceFirst('Exception: ', '');
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

      if (liveReading == null) {
        latest = latestJson == null ? null : BloodPressureMeasurement.fromJson(latestJson);
      }
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
    unawaited(_ble.dispose());
    super.dispose();
  }
}
