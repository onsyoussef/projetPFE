import 'dart:convert';

import 'package:flutter/material.dart';

import '../providers/call_provider.dart';
import '../screens/incoming_call_screen.dart';
import '../services/push_notification_service.dart';

bool patientIncomingCallUiVisible = false;

/// Quand le chat patient est ouvert, son [CallProvider] doit gérer l’appel entrant.
class IncomingCallDelegate {
  static CallProvider? chatCallProvider;
}

/// Normalise l’offre SDP (Map, parfois JSON string selon la couche socket).
Map<String, dynamic>? coerceCallOfferSdp(dynamic raw) {
  if (raw == null) return null;
  if (raw is Map) {
    final m = <String, dynamic>{};
    raw.forEach((k, v) {
      m[k.toString()] = v;
    });
    final type = (m['type'] ?? m['Type'])?.toString().trim().toLowerCase() ?? '';
    final sdp = (m['sdp'] ?? m['SDP'])?.toString() ?? '';
    if (type.isEmpty || sdp.isEmpty) return null;
    return {'type': type, 'sdp': sdp};
  }
  if (raw is String) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    try {
      final d = jsonDecode(t);
      if (d is Map) return coerceCallOfferSdp(d);
    } catch (_) {}
  }
  return null;
}

/// Valide le payload socket `call:incoming`.
Map<String, dynamic>? parseIncomingCallPayload(Map<String, dynamic> data) {
  final roomId = data['roomId']?.toString().trim() ?? '';
  final fromUserId = data['fromUserId']?.toString().trim() ?? '';
  final sdp =
      coerceCallOfferSdp(data['sdp']) ?? coerceCallOfferSdp(data['offer']);
  if (roomId.isEmpty || fromUserId.isEmpty || sdp == null) {
    debugPrint(
      '[IncomingCall] payload ignoré roomId=$roomId fromUserId=$fromUserId '
      'sdpType=${data['sdp']?.runtimeType}',
    );
    return null;
  }
  return {
    'roomId': roomId,
    'fromUserId': fromUserId,
    'sdp': sdp,
    'mediaType': data['mediaType']?.toString() ?? 'audio',
    'callerInfo': Map<String, dynamic>.from(
      (data['callerInfo'] as Map?) ?? const {},
    ),
  };
}

Future<void> showPatientIncomingCallScreen({
  required CallProvider callProvider,
  required Map<String, dynamic> data,
  required String fallbackDoctorName,
  String? fallbackDoctorPhotoPath,
}) async {
  if (patientIncomingCallUiVisible) return;

  final parsed = parseIncomingCallPayload(data);
  if (parsed == null) return;

  final nav = PushNotificationService.navigatorKey?.currentState;
  if (nav == null || !nav.mounted) {
    debugPrint('[IncomingCall] navigator indisponible — écran non affiché');
    return;
  }

  final effectiveProvider =
      IncomingCallDelegate.chatCallProvider ?? callProvider;

  final callerInfo =
      Map<String, dynamic>.from(parsed['callerInfo'] as Map<String, dynamic>);
  final mediaType = parsed['mediaType'] as String;
  final roomId = parsed['roomId'] as String;
  final fromUserId = parsed['fromUserId'] as String;
  final offer = Map<String, dynamic>.from(parsed['sdp'] as Map<String, dynamic>);

  patientIncomingCallUiVisible = true;
  try {
    await nav.push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => IncomingCallScreen(
          callProvider: effectiveProvider,
          fromUserId: fromUserId,
          displayName: callerInfo['name']?.toString() ?? fallbackDoctorName,
          avatarUrl: callerInfo['avatarUrl']?.toString() ??
              fallbackDoctorPhotoPath,
          specialty: callerInfo['specialty']?.toString(),
          roomId: roomId,
          offer: offer,
          isVideoCall: mediaType == 'video',
        ),
      ),
    );
  } finally {
    patientIncomingCallUiVisible = false;
    effectiveProvider.resetAfterCallUi();
  }
}
