import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/entities/android_params.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/entities/ios_params.dart';
import 'package:flutter_callkit_incoming/entities/call_event.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

import 'api_service.dart';
import 'call_navigation_bridge.dart';
import 'pending_call_intent.dart';
import 'webrtc_service.dart';

/// UI d’appel natif (CallKit / ConnectionService) — flux type WhatsApp.
class CallkitService {
  CallkitService._();
  static final CallkitService instance = CallkitService._();

  StreamSubscription<CallEvent?>? _sub;
  final Set<String> _activeIncomingIds = <String>{};

  /// À appeler une fois l’UI Flutter prête (après login).
  void listenEvents() {
    if (kIsWeb) return;
    _sub ??= FlutterCallkitIncoming.onEvent.listen(_onCallEvent);
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }

  Future<void> _onCallEvent(CallEvent? event) async {
    if (event == null) return;
    final body = event.body;
    final Map<String, dynamic> map;
    if (body is Map) {
      map = {};
      body.forEach((k, v) {
        map[k.toString()] = v;
      });
    } else {
      map = {};
    }
    final id = map['id']?.toString() ?? '';
    final extra = map['extra'];
    Map<String, String> extraStr = {};
    if (extra is Map) {
      extra.forEach((k, v) {
        extraStr[k.toString()] = v?.toString() ?? '';
      });
    } else if (extraStr.isEmpty) {
      map.forEach((k, v) {
        if (k != 'id' && k != 'event' && v != null) {
          extraStr[k] = v.toString();
        }
      });
    }

    switch (event.event) {
      case Event.actionCallAccept:
        await _onAccept(id, extraStr);
        break;
      case Event.actionCallDecline:
        await _onDecline(id, extraStr);
        break;
      case Event.actionCallTimeout:
        await _onTimeout(id, extraStr);
        break;
      case Event.actionCallEnded:
        if (id.isNotEmpty) _activeIncomingIds.remove(id);
        break;
      case Event.actionDidUpdateDevicePushTokenVoip:
        final t = map['deviceTokenVoIP']?.toString() ?? map['deviceToken']?.toString() ?? '';
        if (t.isNotEmpty) {
          await _registerVoipToken(t);
        }
        break;
      default:
        break;
    }
  }

  Future<void> _registerVoipToken(String token) async {
    try {
      final messagingToken = await FirebaseMessaging.instance.getToken();
      if (messagingToken == null || messagingToken.isEmpty) return;
      await ApiService.registerPushDevice(
        token: messagingToken,
        platform: 'ios',
        voipToken: token,
      );
    } catch (e) {
      debugPrint('[Callkit] voip token register: $e');
    }
  }

  Future<void> _onAccept(String id, Map<String, String> extra) async {
    final data = _payloadFromExtra(extra);
    PendingCallIntent.setFromPayload(data, answer: true);
    await PendingCallIntent.persist();
    await WebRtcService.instance.handleIncomingCallFromNotification(data);
    CallNavigationBridge.openChatAfterCallAccepted();
    if (id.isNotEmpty) {
      await FlutterCallkitIncoming.setCallConnected(id);
    }
  }

  Future<void> _onDecline(String id, Map<String, String> extra) async {
    final data = _payloadFromExtra(extra);
    final callId = data['callId']?.isNotEmpty == true ? data['callId']! : (data['roomId'] ?? '');
    final roomId = data['roomId'] ?? '';
    final doctorId = data['doctorId']?.isNotEmpty == true ? data['doctorId']! : (data['fromUserId'] ?? '');
    if (callId.isNotEmpty && doctorId.isNotEmpty) {
      try {
        await ApiService.reportIncomingCallDeclined(
          callId: callId,
          roomId: roomId.isNotEmpty ? roomId : callId,
          doctorUserId: doctorId,
        );
      } catch (e) {
        debugPrint('[Callkit] decline API: $e');
      }
    }
    if (id.isNotEmpty) {
      await FlutterCallkitIncoming.endCall(id);
    }
    _activeIncomingIds.remove(id);
  }

  Future<void> _onTimeout(String id, Map<String, String> extra) async {
    final data = _payloadFromExtra(extra);
    final callId = data['callId']?.isNotEmpty == true ? data['callId']! : (data['roomId'] ?? '');
    if (callId.isNotEmpty) {
      try {
        await ApiService.reportIncomingCallMissed(callId: callId);
      } catch (e) {
        debugPrint('[Callkit] missed API: $e');
      }
    }
    _activeIncomingIds.remove(id);
  }

  Map<String, String> _payloadFromExtra(Map<String, String> extra) {
    return {
      'type': 'incoming_call',
      'callId': extra['callId'] ?? '',
      'roomId': extra['roomId'] ?? '',
      'callerId': extra['callerId'] ?? '',
      'callerName': extra['callerName'] ?? '',
      'callerAvatar': extra['callerAvatar'] ?? '',
      'callType': extra['callType'] ?? extra['mediaType'] ?? 'audio',
      'fromUserId': extra['fromUserId'] ?? extra['callerId'] ?? '',
      'doctorId': extra['doctorId'] ?? '',
      'doctorName': extra['doctorName'] ?? '',
      'conversationId': extra['conversationId'] ?? '',
      'mediaType': extra['mediaType'] ?? extra['callType'] ?? 'audio',
    };
  }

  /// Affiche l’écran d’appel système (arrière-plan / terminé). [raw] = payload FCM (chaînes).
  Future<void> showIncomingCall(Map<String, String> raw) async {
    if (kIsWeb) return;
    final callId = (raw['callId'] ?? raw['roomId'] ?? '').trim();
    if (callId.isEmpty) return;
    if (_activeIncomingIds.contains(callId)) return;
    _activeIncomingIds.add(callId);

    final name = raw['callerName']?.isNotEmpty == true ? raw['callerName']! : (raw['doctorName'] ?? 'Médecin');
    final avatar = raw['callerAvatar']?.isNotEmpty == true
        ? raw['callerAvatar']!
        : (raw['doctorAvatarUrl'] ?? '');
    final isVideo =
        (raw['callType'] ?? raw['mediaType'] ?? 'audio').toLowerCase() == 'video';
    final extra = <String, dynamic>{
      'callId': callId,
      'roomId': raw['roomId'] ?? callId,
      'callerId': raw['callerId'] ?? raw['fromUserId'] ?? '',
      'callerName': name,
      'callerAvatar': avatar,
      'callType': isVideo ? 'video' : 'audio',
      'fromUserId': raw['fromUserId'] ?? raw['callerId'] ?? '',
      'doctorId': raw['doctorId'] ?? '',
      'doctorName': raw['doctorName'] ?? name,
      'conversationId': raw['conversationId'] ?? '',
      'mediaType': isVideo ? 'video' : 'audio',
    };

    final params = CallKitParams(
      id: callId,
      nameCaller: name,
      appName: 'Télémedecine',
      avatar: avatar.isNotEmpty ? avatar : null,
      handle: name,
      type: isVideo ? 1 : 0,
      duration: 30000,
      textAccept: 'Accepter',
      textDecline: 'Refuser',
      extra: extra,
      android: const AndroidParams(
        isCustomNotification: true,
        isShowLogo: true,
        isShowFullLockedScreen: true,
        isImportant: true,
      ),
      ios: const IOSParams(
        iconName: 'CallKitLogo',
        handleType: 'generic',
        supportsVideo: true,
        maximumCallGroups: 1,
        maximumCallsPerCallGroup: 1,
        audioSessionMode: 'default',
        audioSessionActive: true,
      ),
    );

    await FlutterCallkitIncoming.showCallkitIncoming(params);
  }

  Future<void> endCall(String callId) async {
    _activeIncomingIds.remove(callId);
    await FlutterCallkitIncoming.endCall(callId);
  }

  Future<bool> hasActiveCallUi(String callId) async {
    if (callId.isEmpty) return false;
    if (_activeIncomingIds.contains(callId)) return true;
    try {
      final active = await FlutterCallkitIncoming.activeCalls();
      if (active is List) {
        for (final x in active) {
          if (x is Map && '${x['id']}' == callId) return true;
        }
      }
    } catch (_) {}
    return false;
  }
}
