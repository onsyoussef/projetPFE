import '../screens/patient_notifications_screen.dart';
import '../utils/patient_ui_utils.dart';

PatientNotificationEntry patientNotificationEntryFromApi(
  Map<String, dynamic> raw,
) {
  final id = raw['id']?.toString() ?? '';
  final typeRaw = raw['type']?.toString() ?? '';
  final title = raw['title']?.toString() ?? 'Notification';
  final body = raw['body']?.toString() ?? '';
  final payload = raw['payload'] is Map
      ? Map<String, dynamic>.from(raw['payload'] as Map)
      : <String, dynamic>{};
  final read = raw['read'] == true;
  final createdAt = DateTime.tryParse(raw['createdAt']?.toString() ?? '') ??
      DateTime.now();

  final status = payload['status']?.toString() ?? '';
  PatientNotificationType type;
  String description = body;

  if (typeRaw.contains('rejected') || status == 'rejected') {
    type = PatientNotificationType.rejected;
  } else if (typeRaw.contains('accepted') || status == 'accepted') {
    type = PatientNotificationType.accepted;
  } else if (typeRaw.contains('rdv') ||
      payload['scheduledAt'] != null ||
      typeRaw.contains('teleconsult_scheduled')) {
    type = PatientNotificationType.teleconsult;
    final doctorName = readableDoctorName(payload['doctorName']?.toString());
    final iso = payload['scheduledAt']?.toString() ?? '';
    if (iso.isNotEmpty) {
      final d = DateTime.tryParse(iso)?.toLocal();
      if (d != null) {
        final date =
            '${d.day}/${d.month}/${d.year}';
        final time =
            '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
        description =
            '$doctorName propose un créneau pour le $date à $time.';
      }
    }
  } else if (typeRaw.contains('file') || typeRaw.contains('document')) {
    type = PatientNotificationType.file;
  } else {
    type = PatientNotificationType.message;
    if (description.isEmpty) {
      final doctorName = readableDoctorName(payload['doctorName']?.toString());
      description = '$doctorName vous a répondu — ouvrir la discussion.';
    }
  }

  if (description.isEmpty) {
    description = title;
  }

  return PatientNotificationEntry(
    id: id,
    type: type,
    title: title,
    description: description,
    timestamp: createdAt,
    isNew: !read,
  );
}

bool patientNotificationOpenChatOnTap(Map<String, dynamic> raw) {
  final payload = raw['payload'] is Map
      ? Map<String, dynamic>.from(raw['payload'] as Map)
      : <String, dynamic>{};
  if (payload['openChat'] == false) return false;
  return payload['openChat'] == true ||
      payload['conversationId']?.toString().isNotEmpty == true;
}

Map<String, dynamic>? patientNotificationPayload(Map<String, dynamic> raw) {
  if (raw['payload'] is Map) {
    return Map<String, dynamic>.from(raw['payload'] as Map);
  }
  return null;
}
