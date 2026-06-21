class BloodPressureMeasurement {
  BloodPressureMeasurement({
    required this.systolic,
    required this.diastolic,
    this.meanArterialPressure,
    this.heartRate,
    required this.measuredAt,
  });

  final int systolic;
  final int diastolic;
  final int? meanArterialPressure;
  final int? heartRate;
  final DateTime measuredAt;

  factory BloodPressureMeasurement.fromJson(Map<String, dynamic> json) {
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

    final mapRaw = json['meanArterialPressure'] ?? json['pam'] ?? json['map'];
    int? map;
    if (mapRaw != null) {
      map = parseInt(mapRaw, 0);
      if (map <= 0) map = null;
    }

    return BloodPressureMeasurement(
      systolic: parseInt(json['systolic'], 0),
      diastolic: parseInt(json['diastolic'], 0),
      meanArterialPressure: map,
      heartRate: hr,
      measuredAt: parseDate(json['measuredAt']),
    );
  }
}

