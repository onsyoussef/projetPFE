import '../utils/doctor_ui_utils.dart';

class DoctorPatientBrief {
  DoctorPatientBrief({
    required this.id,
    required this.name,
  });

  final String id;
  final String name;

  factory DoctorPatientBrief.fromJson(Map<String, dynamic> json) {
    final firstName = (json['firstName'] ?? '').toString().trim();
    final lastName = (json['lastName'] ?? '').toString().trim();
    final fallbackName = readablePatientName(
      (json['name'] ?? json['fullName'])?.toString(),
      fallback: '',
    );
    final merged = '$firstName $lastName'.trim();
    final resolved = merged.isEmpty ? fallbackName : readablePatientName(merged, fallback: fallbackName);
    return DoctorPatientBrief(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      name: resolved.isEmpty ? 'Patient' : resolved,
    );
  }

  String get firstName {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '';
    return parts.first;
  }

  String get lastName {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length <= 1) return '';
    return parts.sublist(1).join(' ');
  }
}
