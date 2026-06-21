import 'package:flutter/material.dart';

import '../chat_medecin_page.dart';
import '../screens/doctor_blood_pressure_screen.dart';
import '../services/api_service.dart';
import '../utils/doctor_ui_utils.dart';
import '../widgets/doctor_notifications_sheet.dart';

class DoctorNotificationEntry {
  const DoctorNotificationEntry({
    required this.sheetId,
    required this.notificationId,
    required this.conversationId,
    required this.title,
    required this.subtitle,
    required this.patientName,
    required this.kind,
    this.patientId,
    this.patientPhotoPath,
    this.occurredAt,
    this.isRead = false,
  });

  final String sheetId;
  final String notificationId;
  final String conversationId;
  final String title;
  final String subtitle;
  final String patientName;
  final String? patientId;
  final String? patientPhotoPath;
  final DoctorNotificationVisualKind kind;
  final DateTime? occurredAt;
  final bool isRead;

  bool get isWaitingRoom => kind == DoctorNotificationVisualKind.urgent &&
      subtitle.toLowerCase().contains('attente');
}

DoctorNotificationVisualKind _kindFromApi(
  String type,
  String title,
  String body,
) {
  final t = type.toLowerCase();
  final combined = '$title $body'.toLowerCase();
  if (t.contains('blood_pressure') || combined.contains('tension')) {
    return DoctorNotificationVisualKind.analysis;
  }
  if (t.contains('waiting') || combined.contains('attente')) {
    return DoctorNotificationVisualKind.urgent;
  }
  if (t.contains('form') || combined.contains('analyse') || combined.contains('formulaire')) {
    return DoctorNotificationVisualKind.analysis;
  }
  if (combined.contains('urgence')) {
    return DoctorNotificationVisualKind.urgent;
  }
  if (t.contains('teleconsult_request') || t.contains('chat_message')) {
    return DoctorNotificationVisualKind.message;
  }
  return DoctorNotificationVisualKind.newPatient;
}

DoctorNotificationEntry _entryFromApi(Map<String, dynamic> raw) {
  final id = raw['id']?.toString() ?? '';
  final type = raw['type']?.toString() ?? '';
  final title = raw['title']?.toString() ?? 'Notification';
  final body = raw['body']?.toString() ?? '';
  final payload = raw['payload'] is Map
      ? Map<String, dynamic>.from(raw['payload'] as Map)
      : <String, dynamic>{};
  final occurredAt = DateTime.tryParse(raw['createdAt']?.toString() ?? '');

  final patientName = readablePatientName(payload['patientName']?.toString());
  final conversationId = payload['conversationId']?.toString() ?? '';
  final kind = _kindFromApi(type, title, body);

  return DoctorNotificationEntry(
    sheetId: id.isNotEmpty ? id : '$type-${occurredAt?.millisecondsSinceEpoch ?? 0}',
    notificationId: id,
    conversationId: conversationId,
    title: title,
    subtitle: body.isNotEmpty ? body : title,
    patientName: patientName,
    patientId: payload['patientId']?.toString(),
    patientPhotoPath: payload['patientPhotoPath']?.toString(),
    kind: kind,
    occurredAt: occurredAt,
    isRead: raw['read'] == true,
  );
}

Future<List<DoctorNotificationEntry>> loadDoctorNotificationEntries({
  required String doctorId,
}) async {
  if (doctorId.isEmpty) return const [];
  try {
    final bundle = await ApiService.getDoctorNotifications(doctorId: doctorId);
    final list = (bundle['notifications'] as List?)
            ?.map((e) => Map<String, dynamic>.from(e as Map))
            .toList() ??
        [];
    return list.map(_entryFromApi).toList();
  } catch (_) {
    return const [];
  }
}

Future<int> countDoctorNotifications(String doctorId) async {
  if (doctorId.isEmpty) return 0;
  try {
    final bundle = await ApiService.getDoctorNotifications(doctorId: doctorId);
    final unread = bundle['unreadCount'];
    if (unread is num) return unread.toInt().clamp(0, 99);
    final list = (bundle['notifications'] as List?) ?? [];
    return list.where((n) => (n as Map)['read'] != true).length;
  } catch (_) {
    return 0;
  }
}

DoctorNotificationSheetItem _toSheetItem(
  DoctorNotificationEntry n,
  BuildContext context, {
  required String doctorId,
  VoidCallback? beforeNavigate,
}) {
  return DoctorNotificationSheetItem(
    id: n.sheetId,
    kind: n.kind,
    title: n.title,
    subtitle: n.subtitle,
    occurredAt: n.occurredAt,
    dismissible: false,
    onTap: n.conversationId.isNotEmpty && (n.patientId?.isNotEmpty ?? false)
        ? () {
            beforeNavigate?.call();
            WidgetsBinding.instance.addPostFrameCallback((_) {
              final pid = n.patientId;
              if (pid == null || pid.isEmpty) return;
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => ChatMedecinPage(
                    conversationId: n.conversationId,
                    patientId: pid,
                    patientName: n.patientName,
                    patientPhotoPath: n.patientPhotoPath,
                    doctorId: doctorId,
                  ),
                ),
              );
            });
          }
        : n.kind == DoctorNotificationVisualKind.analysis &&
                n.subtitle.toLowerCase().contains('tension')
            ? () {
                beforeNavigate?.call();
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => DoctorBloodPressureScreen(
                        doctorId: doctorId,
                      ),
                    ),
                  );
                });
              }
            : null,
  );
}

Future<void> showDoctorNotificationsPanel(
  BuildContext context, {
  required String doctorId,
  VoidCallback? beforeNavigate,
}) async {
  if (doctorId.isEmpty) return;

  var entries = await loadDoctorNotificationEntries(doctorId: doctorId);
  if (!context.mounted) return;

  await showDoctorNotificationsSheet(
    context,
    items: entries.map((n) => _toSheetItem(n, context, doctorId: doctorId, beforeNavigate: beforeNavigate)).toList(),
    onDismissItem: (item) async {
      DoctorNotificationEntry? match;
      for (final n in entries) {
        if (n.sheetId == item.id) {
          match = n;
          break;
        }
      }
      if (match == null || match.notificationId.isEmpty) return;
      try {
        await ApiService.markDoctorNotificationRead(
          doctorId: doctorId,
          notificationId: match.notificationId,
        );
      } catch (_) {}
    },
    onDismissAll: () async {
      try {
        await ApiService.markAllDoctorNotificationsRead(doctorId: doctorId);
      } catch (_) {}
    },
  );
}
