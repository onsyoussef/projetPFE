import '../utils/doctor_ui_utils.dart';

class DoctorBloodPressureAlert {
  DoctorBloodPressureAlert({
    required this.patientId,
    required this.patientName,
    required this.type,
    required this.systolic,
    required this.diastolic,
    required this.createdAt,
  });

  final String patientId;
  final String patientName;
  final String type;
  final int systolic;
  final int diastolic;
  final DateTime createdAt;

  bool get isHypertension => type.toLowerCase().contains('hyper');

  factory DoctorBloodPressureAlert.fromJson(Map<String, dynamic> json) {
    int parseInt(dynamic v, int fallback) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v?.toString() ?? '') ?? fallback;
    }

    DateTime parseDate(dynamic v) {
      final s = v?.toString() ?? '';
      return DateTime.tryParse(s)?.toLocal() ?? DateTime.now();
    }

    return DoctorBloodPressureAlert(
      patientId: (json['patientId'] ?? '').toString(),
      patientName: readablePatientName(json['patientName']?.toString()),
      type: (json['type'] ?? 'Hypertension').toString(),
      systolic: parseInt(json['systolic'], 0),
      diastolic: parseInt(json['diastolic'], 0),
      createdAt: parseDate(json['createdAt']),
    );
  }
}
