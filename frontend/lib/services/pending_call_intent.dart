import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Intent stocké quand l’utilisateur ouvre l’app depuis une notification d’appel entrant.
class PendingCallIntent {
  PendingCallIntent._();

  static const _prefsKey = 'pending_call_intent_json';

  static String? roomId;
  static String? callId;
  static String? doctorId;
  static String? doctorName;
  static String? conversationId;
  static String? fromUserId;
  static bool isVideo = false;
  /// true = Répondre ou tap sur le corps ; false = refus depuis la notification.
  static bool wantsAnswer = true;

  static bool get hasPending => (roomId ?? '').trim().isNotEmpty;

  static void setFromPayload(Map<String, String> data, {required bool answer}) {
    callId = data['callId']?.trim().isNotEmpty == true ? data['callId'] : data['roomId'];
    roomId = data['roomId'];
    doctorId = data['doctorId']?.isNotEmpty == true ? data['doctorId'] : data['fromUserId'];
    doctorName = data['doctorName'];
    conversationId = data['conversationId'];
    fromUserId = data['fromUserId'];
    isVideo = data['mediaType'] == 'video';
    wantsAnswer = answer;
  }

  static Future<void> persist() async {
    if (!hasPending) return;
    final p = await SharedPreferences.getInstance();
    await p.setString(
      _prefsKey,
      jsonEncode({
        'roomId': roomId,
        'callId': callId,
        'doctorId': doctorId,
        'doctorName': doctorName,
        'conversationId': conversationId,
        'fromUserId': fromUserId,
        'isVideo': isVideo,
        'wantsAnswer': wantsAnswer,
      }),
    );
  }

  static Future<void> loadFromPrefs() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_prefsKey);
    if (s == null || s.isEmpty) return;
    try {
      final m = jsonDecode(s) as Map<String, dynamic>;
      roomId = m['roomId']?.toString();
      callId = m['callId']?.toString();
      doctorId = m['doctorId']?.toString();
      doctorName = m['doctorName']?.toString();
      conversationId = m['conversationId']?.toString();
      fromUserId = m['fromUserId']?.toString();
      isVideo = m['isVideo'] == true;
      wantsAnswer = m['wantsAnswer'] != false;
    } catch (_) {}
  }

  static Future<void> clear() async {
    roomId = null;
    callId = null;
    doctorId = null;
    doctorName = null;
    conversationId = null;
    fromUserId = null;
    isVideo = false;
    wantsAnswer = true;
    final p = await SharedPreferences.getInstance();
    await p.remove(_prefsKey);
  }
}

/// Navigation depuis une notification « appel manqué » (conversation à ouvrir).
class PendingMissedCallIntent {
  PendingMissedCallIntent._();

  static const _prefsKey = 'pending_missed_call_json';

  static String? conversationId;
  static String? messageId;
  static String? doctorId;
  static String? doctorName;

  static bool get hasPending => (conversationId ?? '').trim().isNotEmpty;

  static void setFromPayload(Map<String, String> data) {
    conversationId = data['conversationId'];
    messageId = data['messageId'];
    doctorId = data['doctorId'];
    doctorName = data['doctorName'];
  }

  static Future<void> persist() async {
    if (!hasPending) return;
    final p = await SharedPreferences.getInstance();
    await p.setString(
      _prefsKey,
      jsonEncode({
        'conversationId': conversationId,
        'messageId': messageId,
        'doctorId': doctorId,
        'doctorName': doctorName,
      }),
    );
  }

  static Future<void> loadFromPrefs() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_prefsKey);
    if (s == null || s.isEmpty) return;
    try {
      final m = jsonDecode(s) as Map<String, dynamic>;
      conversationId = m['conversationId']?.toString();
      messageId = m['messageId']?.toString();
      doctorId = m['doctorId']?.toString();
      doctorName = m['doctorName']?.toString();
    } catch (_) {}
  }

  static Future<void> clear() async {
    conversationId = null;
    messageId = null;
    doctorId = null;
    doctorName = null;
    final p = await SharedPreferences.getInstance();
    await p.remove(_prefsKey);
  }
}
