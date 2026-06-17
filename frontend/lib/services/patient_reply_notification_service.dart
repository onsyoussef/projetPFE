import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';
import '../utils/patient_ui_utils.dart';

/// Détection hors écran de chat de l’événement « Répondre par message » (médecin).
class PatientReplyNotificationService {
  PatientReplyNotificationService(this.patientId);

  final String patientId;

  Timer? _timer;
  bool _tickInFlight = false;

  /// Conversation ouverte actuellement dans [ChatPage] : pas d’alerte doublon espace patient.
  static String? suppressedConversationId;

  static void setSuppressedConversation(String? conversationId) {
    suppressedConversationId = conversationId;
  }

  static String cursorPreferenceKey(String patientId, String conversationId) =>
      'patient_reply_cursor_${patientId}_$conversationId';

  static String? extractMessageObjectId(dynamic value) {
    if (value == null) return null;
    if (value is String) {
      final match = RegExp(r'[0-9a-fA-F]{24}').firstMatch(value);
      return match?.group(0);
    }
    final s = value.toString();
    final match = RegExp(r'[0-9a-fA-F]{24}').firstMatch(s);
    return match?.group(0);
  }

  static String? payloadEvent(Map<String, dynamic> m) {
    final p = m['payload'];
    if (p == null) return null;
    if (p is! Map) return null;
    final map = Map<String, dynamic>.from(p);
    final ev = map['event'];
    if (ev == null) return null;
    return ev.toString();
  }

  static bool isReplyByMessageEvent(Map<String, dynamic> m) {
    return payloadEvent(m) == 'reply_by_message';
  }

  static bool isTeleconsultScheduledMessage(Map<String, dynamic> m) {
    return (m['type'] as String? ?? '') == 'teleconsult_scheduled';
  }

  static bool isRdvTeleconsultProgrammeMessage(Map<String, dynamic> m) {
    return (m['type'] as String? ?? '') == 'rdv_teleconsult_programme';
  }

  /// Créneau planifié (message médecin ou message système RDV collection).
  static bool isScheduledTeleconsultLikeMessage(Map<String, dynamic> m) {
    return isTeleconsultScheduledMessage(m) || isRdvTeleconsultProgrammeMessage(m);
  }

  static String? scheduledAtIsoFromMessage(Map<String, dynamic> m) {
    final p = m['payload'];
    if (p is! Map) return null;
    final v = p['scheduledAt'];
    return v is String ? v : null;
  }

  static String? scheduledAtIsoFromRdvProgrammeMessage(Map<String, dynamic> m) {
    if (!isRdvTeleconsultProgrammeMessage(m)) return null;
    final p = m['payload'];
    if (p is! Map) return null;
    final map = Map<String, dynamic>.from(p);
    final ds = map['date']?.toString();
    final hs = map['heure']?.toString().trim();
    if (ds == null || hs == null || ds.isEmpty || hs.isEmpty) return null;
    final dm = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(ds);
    final hm = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(hs);
    if (dm == null || hm == null) return null;
    final y = int.tryParse(dm.group(1)!);
    final mo = int.tryParse(dm.group(2)!);
    final d = int.tryParse(dm.group(3)!);
    final hh = int.tryParse(hm.group(1)!);
    final mm = int.tryParse(hm.group(2)!);
    if (y == null || mo == null || d == null || hh == null || mm == null) {
      return null;
    }
    final local = DateTime(y, mo, d, hh, mm);
    return local.toUtc().toIso8601String();
  }

  static String? scheduledAtIsoFromAnyScheduledMessage(Map<String, dynamic> m) {
    return scheduledAtIsoFromMessage(m) ??
        scheduledAtIsoFromRdvProgrammeMessage(m);
  }

  /// À appeler depuis le chat après chargement des messages : évite une re-notification à la sortie du chat.
  static Future<void> syncCursorToLatestMessage({
    required String patientId,
    required String conversationId,
    required List<Map<String, dynamic>> messages,
  }) async {
    if (messages.isEmpty) return;
    final id = extractMessageObjectId(messages.last['_id']);
    if (id == null || id.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(cursorPreferenceKey(patientId, conversationId), id);
  }

  Future<void> pollOnce({
    required bool notificationsEnabled,
    required void Function(
      String doctorName,
      String doctorId,
      String conversationId, {
      String? doctorPhotoPath,
    }) onDoctorReplyByMessage,
    void Function(
      String doctorName,
      String doctorId,
      String conversationId,
      String scheduledAtIso, {
      String? doctorPhotoPath,
    })? onTeleconsultScheduled,
  }) async {
    if (_tickInFlight) return;
    _tickInFlight = true;
    try {
      final convs = await ApiService.getPatientConversations(patientId: patientId);
      final prefs = await SharedPreferences.getInstance();

      for (final c in convs) {
        final convId = c['conversationId'] as String? ?? '';
        if (convId.isEmpty) continue;
        final doctorName = readableDoctorName(c['doctorName'] as String?);
        final doctorId = c['doctorId'] as String? ?? '';
        final doctorPhotoPath = c['doctorPhotoPath']?.toString();
        final key = cursorPreferenceKey(patientId, convId);
        final cursor = prefs.getString(key);
        final suppress = suppressedConversationId != null &&
            suppressedConversationId == convId;

        if (cursor == null || cursor.isEmpty) {
          final data = await ApiService.getMessages(conversationId: convId);
          final list = data['messages'] as List?;
          if (list != null && list.isNotEmpty) {
            final messages = list
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
            final last = messages.last;
            final lastId = extractMessageObjectId(last['_id']);
            if (lastId != null && lastId.isNotEmpty) {
              await prefs.setString(key, lastId);
            }
            // Première init : si le dernier message est « répondre par message »
            // (récent), le patient n’a pas pu être notifié par poll incrémental.
            final notifDedupKey = 'patient_rbm_notified_${patientId}_$convId';
            final lastReplyId = extractMessageObjectId(last['_id']);
            if (isReplyByMessageEvent(last) &&
                notificationsEnabled &&
                !suppress &&
                lastReplyId != null &&
                lastReplyId.isNotEmpty &&
                prefs.getString(notifDedupKey) != lastReplyId) {
              onDoctorReplyByMessage(
                doctorName,
                doctorId,
                convId,
                doctorPhotoPath: doctorPhotoPath,
              );
              await prefs.setString(notifDedupKey, lastReplyId);
            }
            final tcsDedupKey = 'patient_tcs_notified_${patientId}_$convId';
            final tcsIsoBoot = scheduledAtIsoFromAnyScheduledMessage(last);
            if (onTeleconsultScheduled != null &&
                isScheduledTeleconsultLikeMessage(last) &&
                notificationsEnabled &&
                !suppress &&
                tcsIsoBoot != null &&
                lastReplyId != null &&
                lastReplyId.isNotEmpty &&
                prefs.getString(tcsDedupKey) != lastReplyId) {
              onTeleconsultScheduled(
                doctorName,
                doctorId,
                convId,
                tcsIsoBoot,
                doctorPhotoPath: doctorPhotoPath,
              );
              await prefs.setString(tcsDedupKey, lastReplyId);
            }
          }
          continue;
        }

        final afterBundle = await ApiService.getMessagesAfter(
          conversationId: convId,
          afterId: cursor,
        );
        final newMsgs = (afterBundle['messages'] as List?)
                ?.map((e) => Map<String, dynamic>.from(e as Map))
                .toList() ??
            <Map<String, dynamic>>[];
        if (newMsgs.isEmpty) continue;

        final lastNewId = extractMessageObjectId(newMsgs.last['_id']);
        Map<String, dynamic>? replyMsg;
        for (final raw in newMsgs) {
          final m = Map<String, dynamic>.from(raw);
          if (isReplyByMessageEvent(m)) {
            replyMsg = m; // dernier « reply_by_message » du lot
          }
        }
        final hasReply = replyMsg != null;

        final notifDedupKey = 'patient_rbm_notified_${patientId}_$convId';
        final replyId =
            replyMsg != null ? extractMessageObjectId(replyMsg['_id']) : null;

        if (hasReply &&
            notificationsEnabled &&
            !suppress &&
            replyId != null &&
            replyId.isNotEmpty &&
            prefs.getString(notifDedupKey) != replyId) {
          onDoctorReplyByMessage(
            doctorName,
            doctorId,
            convId,
            doctorPhotoPath: doctorPhotoPath,
          );
          await prefs.setString(notifDedupKey, replyId);
        }

        Map<String, dynamic>? tcsMsg;
        for (final raw in newMsgs) {
          final m = Map<String, dynamic>.from(raw);
          if (isScheduledTeleconsultLikeMessage(m)) {
            tcsMsg = m;
          }
        }
        final tcsDedupKey2 = 'patient_tcs_notified_${patientId}_$convId';
        final tcsId =
            tcsMsg != null ? extractMessageObjectId(tcsMsg['_id']) : null;
        final tcsIso = tcsMsg != null
            ? scheduledAtIsoFromAnyScheduledMessage(tcsMsg)
            : null;
        if (onTeleconsultScheduled != null &&
            tcsMsg != null &&
            notificationsEnabled &&
            !suppress &&
            tcsId != null &&
            tcsId.isNotEmpty &&
            tcsIso != null &&
            prefs.getString(tcsDedupKey2) != tcsId) {
          onTeleconsultScheduled(
            doctorName,
            doctorId,
            convId,
            tcsIso,
            doctorPhotoPath: doctorPhotoPath,
          );
          await prefs.setString(tcsDedupKey2, tcsId);
        }

        if (lastNewId != null && lastNewId.isNotEmpty) {
          await prefs.setString(key, lastNewId);
        }
      }
    } catch (e, st) {
      debugPrint('PatientReplyNotificationService: $e\n$st');
    } finally {
      _tickInFlight = false;
    }
  }

  void start({
    required Duration interval,
    required bool Function() notificationsEnabled,
    required void Function(
      String doctorName,
      String doctorId,
      String conversationId, {
      String? doctorPhotoPath,
    }) onDoctorReplyByMessage,
    void Function(
      String doctorName,
      String doctorId,
      String conversationId,
      String scheduledAtIso, {
      String? doctorPhotoPath,
    })? onTeleconsultScheduled,
  }) {
    stop();
    _timer = Timer.periodic(interval, (_) {
      pollOnce(
        notificationsEnabled: notificationsEnabled(),
        onDoctorReplyByMessage: onDoctorReplyByMessage,
        onTeleconsultScheduled: onTeleconsultScheduled,
      );
    });
    Future<void>(() async {
      await pollOnce(
        notificationsEnabled: notificationsEnabled(),
        onDoctorReplyByMessage: onDoctorReplyByMessage,
        onTeleconsultScheduled: onTeleconsultScheduled,
      );
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() => stop();
}
