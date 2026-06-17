class BloodPressureAlert {
  BloodPressureAlert({
    required this.type,
    required this.message,
    required this.createdAt,
    this.severity = 'info',
  });

  final String type;
  final String message;
  final DateTime createdAt;
  final String severity;

  factory BloodPressureAlert.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic v) {
      final s = v?.toString() ?? '';
      return DateTime.tryParse(s)?.toLocal() ?? DateTime.now();
    }

    return BloodPressureAlert(
      type: (json['type'] ?? 'info').toString(),
      message: (json['message'] ?? '').toString(),
      severity: (json['severity'] ?? 'info').toString(),
      createdAt: parseDate(json['createdAt']),
    );
  }
}

