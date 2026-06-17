import '../utils/patient_ui_utils.dart';

class PrescriptionMedLine {
  const PrescriptionMedLine({
    required this.name,
    required this.dosage,
    required this.duration,
    required this.instructions,
  });

  final String name;
  final String dosage;
  final String duration;
  final String instructions;

  factory PrescriptionMedLine.fromJson(Map<String, dynamic> json) {
    return PrescriptionMedLine(
      name: '${json['name'] ?? ''}'.trim(),
      dosage: '${json['dosage'] ?? ''}'.trim(),
      duration: '${json['duration'] ?? ''}'.trim(),
      instructions: '${json['instructions'] ?? ''}'.trim(),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'dosage': dosage,
        'duration': duration,
        'instructions': instructions,
      };
}

class PrescriptionHistoryEntry {
  const PrescriptionHistoryEntry({
    required this.id,
    required this.patientId,
    required this.doctorId,
    required this.conversationId,
    required this.medications,
    required this.note,
    required this.createdAt,
    required this.updatedAt,
    required this.doctorName,
    required this.doctorSpecialty,
    required this.city,
    required this.pdfUrl,
    required this.statusLabelKey,
  });

  final String id;
  final String patientId;
  final String doctorId;
  final String conversationId;
  final List<PrescriptionMedLine> medications;
  final String note;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String doctorName;
  final String doctorSpecialty;
  final String city;
  final String pdfUrl;
  final String statusLabelKey;

  factory PrescriptionHistoryEntry.fromJson(Map<String, dynamic> json) {
    final medsRaw = json['medications'];
    final meds = <PrescriptionMedLine>[];
    if (medsRaw is List) {
      for (final e in medsRaw) {
        if (e is Map) {
          meds.add(PrescriptionMedLine.fromJson(Map<String, dynamic>.from(e)));
        }
      }
    }
    return PrescriptionHistoryEntry(
      id: '${json['id'] ?? ''}'.trim(),
      patientId: '${json['patientId'] ?? ''}'.trim(),
      doctorId: '${json['doctorId'] ?? ''}'.trim(),
      conversationId: '${json['conversationId'] ?? ''}'.trim(),
      medications: meds,
      note: '${json['note'] ?? ''}'.trim(),
      createdAt: _parseDate(json['createdAt']),
      updatedAt: _parseDate(json['updatedAt']),
      doctorName: readableDoctorName(json['doctorName']?.toString()),
      doctorSpecialty: readableDecryptedField(json['doctorSpecialty']?.toString()),
      city: readableDecryptedField(json['city']?.toString()),
      pdfUrl: '${json['pdfUrl'] ?? ''}'.trim(),
      statusLabelKey: '${json['statusLabelKey'] ?? json['statusBadge'] ?? 'delivered'}'
          .trim(),
    );
  }

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString());
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'patientId': patientId,
        'doctorId': doctorId,
        'conversationId': conversationId,
        'medications': medications.map((m) => m.toJson()).toList(),
        'note': note,
        'createdAt': createdAt?.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
        'doctorName': doctorName,
        'doctorSpecialty': doctorSpecialty,
        'city': city,
        'pdfUrl': pdfUrl,
        'statusLabelKey': statusLabelKey,
      };
}
