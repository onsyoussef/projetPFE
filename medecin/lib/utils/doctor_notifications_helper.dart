import 'package:flutter/material.dart';

import '../chat_medecin_page.dart';
import '../screens/doctor_blood_pressure_screen.dart';
import '../services/api_service.dart';
import '../widgets/doctor_notifications_sheet.dart';
import 'doctor_notification_dismiss_storage.dart';
import 'doctor_ui_utils.dart';
import 'doctor_waiting_room_dismiss_storage.dart';

class DoctorNotificationEntry {
  const DoctorNotificationEntry({
    required this.sheetId,
    required this.conversationId,
    required this.title,
    required this.subtitle,
    required this.patientName,
    required this.kind,
    this.patientId,
    this.patientPhotoPath,
    this.waitingEnteredAt,
    this.occurredAt,
    this.alertDismissId,
  });

  final String sheetId;
  final String conversationId;
  final String title;
  final String subtitle;
  final String patientName;
  final String? patientId;
  final String? patientPhotoPath;
  final DoctorNotificationVisualKind kind;
  final DateTime? occurredAt;
  final int? waitingEnteredAt;
  final String? alertDismissId;

  bool get isWaitingRoom => waitingEnteredAt != null;
  bool get isBloodPressureAlert => alertDismissId != null;
}

bool doctorConversationQualifiesForNotification(Map<String, dynamic> c) {
  if (c['urgenceFormulairePending'] == true) return false;
  final lastType = c['lastMessageType']?.toString() ?? '';
  final lastFrom = c['lastMessageFromType']?.toString() ?? '';
  if (lastType != 'request_teleconsult' && lastType != 'form_teleconsult') {
    return false;
  }
  return lastFrom == 'patient' || lastFrom == 'system';
}

Future<List<DoctorNotificationEntry>> loadDoctorNotificationEntries({
  required String doctorId,
}) async {
  if (doctorId.isEmpty) return const [];

  final dismissed = await DoctorNotificationDismissStorage.getMap(doctorId);
  final waitingDismissed =
      await DoctorWaitingRoomDismissStorage.getMap(doctorId);

  List<Map<String, dynamic>> conversations = [];
  List<Map<String, dynamic>> waitingItems = [];
  try {
    conversations = await ApiService.getDoctorConversations(doctorId: doctorId);
  } catch (_) {}
  try {
    waitingItems = await ApiService.getDoctorWaitingRooms(doctorId: doctorId);
  } catch (_) {}

  String? photoForConv(String conversationId) {
    for (final c in conversations) {
      if (c['conversationId']?.toString() == conversationId) {
        return c['patientPhotoPath']?.toString();
      }
    }
    return null;
  }

  String? patientIdForConv(String conversationId) {
    for (final c in conversations) {
      if (c['conversationId']?.toString() == conversationId) {
        final p = c['patientId']?.toString();
        if (p != null && p.isNotEmpty) return p;
      }
    }
    return null;
  }

  final out = <DoctorNotificationEntry>[];

  for (final w in waitingItems) {
    final cid = w['conversationId']?.toString() ?? '';
    if (cid.isEmpty) continue;
    final rawAt = w['enteredAt']?.toString();
    final dt = DateTime.tryParse(rawAt ?? '');
    final ms = dt?.millisecondsSinceEpoch ??
        DateTime.now().millisecondsSinceEpoch;
    if (waitingRoomSessionDismissed(cid, ms, waitingDismissed)) continue;

    final name = readablePatientName(w['patientName']?.toString());
    out.add(
      DoctorNotificationEntry(
        sheetId: 'wr-$cid-$ms',
        conversationId: cid,
        title: 'Alerte Urgence — $name',
        subtitle: 'Le patient est en attente de téléconsultation.',
        patientName: name,
        patientId: w['patientId']?.toString() ?? patientIdForConv(cid),
        patientPhotoPath: photoForConv(cid),
        waitingEnteredAt: ms,
        kind: DoctorNotificationVisualKind.urgent,
        occurredAt: DateTime.fromMillisecondsSinceEpoch(ms),
      ),
    );
  }

  for (final c in conversations) {
    final id = c['conversationId']?.toString() ?? '';
    if (id.isEmpty) continue;
    if (notificationDismissedForConversation(c, dismissed)) continue;
    if (!doctorConversationQualifiesForNotification(c)) continue;

    final name = readablePatientName(c['patientName']?.toString());
    final last = c['lastMessage']?.toString() ?? '';
    final lastType = c['lastMessageType']?.toString() ?? '';
    final tags = conversationTags(c['tags']);
    final occurredAt = DateTime.tryParse(
      c['lastMessageAt']?.toString() ?? c['updatedAt']?.toString() ?? '',
    );

    late final String title;
    late final String subtitle;
    late final DoctorNotificationVisualKind kind;
    if (lastType == 'request_teleconsult') {
      if (tags.contains('urgent')) {
        kind = DoctorNotificationVisualKind.urgent;
        title = 'Alerte Urgence — $name';
        subtitle =
            last.isNotEmpty ? last : 'Intervention requise pour ce patient.';
      } else {
        kind = DoctorNotificationVisualKind.message;
        title = 'Messages — $name';
        subtitle = last.isNotEmpty
            ? last
            : '$name vous a envoyé une demande de téléconsultation.';
      }
    } else {
      kind = DoctorNotificationVisualKind.analysis;
      title = 'Analyses Reçues — $name';
      subtitle = last.isNotEmpty
          ? last
          : 'Les résultats sont disponibles dans son dossier.';
    }

    out.add(
      DoctorNotificationEntry(
        sheetId: 'conv-$id',
        conversationId: id,
        title: title,
        subtitle: subtitle,
        patientName: name,
        patientId: c['patientId']?.toString(),
        patientPhotoPath: c['patientPhotoPath']?.toString(),
        kind: kind,
        occurredAt: occurredAt,
      ),
    );
  }

  return out;
}

Future<int> countDoctorNotifications(String doctorId) async {
  final items = await loadDoctorNotificationEntries(doctorId: doctorId);
  return items.length;
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
    dismissible: n.isWaitingRoom || n.isBloodPressureAlert,
    onTap: n.isWaitingRoom
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
        : n.isBloodPressureAlert
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

  final convUpdates = <String, String>{};
  for (final n in entries) {
    if (n.isWaitingRoom || n.isBloodPressureAlert) continue;
    for (final c in await ApiService.getDoctorConversations(doctorId: doctorId)) {
      if (c['conversationId']?.toString() == n.conversationId) {
        convUpdates[n.conversationId] = notificationDismissSnapshotIso(c);
        break;
      }
    }
  }
  if (convUpdates.isNotEmpty) {
    await DoctorNotificationDismissStorage.merge(doctorId, convUpdates);
    entries = await loadDoctorNotificationEntries(doctorId: doctorId);
    if (!context.mounted) return;
  }

  await showDoctorNotificationsSheet(
    context,
    items: entries
        .map(
          (n) => _toSheetItem(
            n,
            context,
            doctorId: doctorId,
            beforeNavigate: beforeNavigate,
          ),
        )
        .toList(),
    onDismissItem: (item) async {
      DoctorNotificationEntry? match;
      for (final n in entries) {
        if (n.sheetId == item.id) {
          match = n;
          break;
        }
      }
      if (match == null) return;
      if (match.isWaitingRoom && match.waitingEnteredAt != null) {
        await DoctorWaitingRoomDismissStorage.merge(doctorId, {
          match.conversationId: '${match.waitingEnteredAt}',
        });
      } else if (!match.isBloodPressureAlert) {
        for (final c
            in await ApiService.getDoctorConversations(doctorId: doctorId)) {
          if (c['conversationId']?.toString() == match.conversationId) {
            await DoctorNotificationDismissStorage.merge(doctorId, {
              match.conversationId: notificationDismissSnapshotIso(c),
            });
            break;
          }
        }
      }
    },
    onDismissAll: () async {
      final waitingUpdates = <String, String>{};
      final convDismiss = <String, String>{};
      for (final n in entries) {
        if (n.isWaitingRoom && n.waitingEnteredAt != null) {
          waitingUpdates[n.conversationId] = '${n.waitingEnteredAt}';
        } else if (!n.isBloodPressureAlert) {
          for (final c
              in await ApiService.getDoctorConversations(doctorId: doctorId)) {
            if (c['conversationId']?.toString() == n.conversationId) {
              convDismiss[n.conversationId] = notificationDismissSnapshotIso(c);
              break;
            }
          }
        }
      }
      if (waitingUpdates.isNotEmpty) {
        await DoctorWaitingRoomDismissStorage.merge(doctorId, waitingUpdates);
      }
      if (convDismiss.isNotEmpty) {
        await DoctorNotificationDismissStorage.merge(doctorId, convDismiss);
      }
    },
  );
}
