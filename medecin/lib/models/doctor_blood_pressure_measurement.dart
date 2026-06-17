import '../utils/doctor_ui_utils.dart';

class DoctorBloodPressureMeasurement {
  DoctorBloodPressureMeasurement({
    required this.patientId,
    required this.patientName,
    required this.systolic,
    required this.diastolic,
    this.heartRate,
    required this.measuredAt,
  });

  final String patientId;
  final String patientName;
  final int systolic;
  final int diastolic;
  final int? heartRate;
  final DateTime measuredAt;

  factory DoctorBloodPressureMeasurement.fromJson(Map<String, dynamic> json) {
    int parseInt(dynamic v, int fallback) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v?.toString() ?? '') ?? fallback;
    }

    DateTime parseDate(dynamic v) {
      final s = v?.toString() ?? '';
      return DateTime.tryParse(s)?.toLocal() ?? DateTime.now();
    }

    final hrRaw = json['heartRate'];
    int? hr;
    if (hrRaw != null) {
      hr = parseInt(hrRaw, 0);
      if (hr <= 0) hr = null;
    }

    return DoctorBloodPressureMeasurement(
      patientId: (json['patientId'] ?? '').toString(),
      patientName: readablePatientName(json['patientName']?.toString()),
      systolic: parseInt(json['systolic'], 0),
      diastolic: parseInt(json['diastolic'], 0),
      heartRate: hr,
      measuredAt: parseDate(json['measuredAt']),
    );
  }
}
