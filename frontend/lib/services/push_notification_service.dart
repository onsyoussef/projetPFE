import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';
import 'callkit_service.dart';
import '../screens/chat_opener_from_push.dart';
import 'pending_call_intent.dart';
import 'webrtc_service.dart';

const String _kMissedChannelId = 'telemedecine_missed_call';
const String _kDefaultChannelId = 'telemedecine_patient_channel';

/// ID stable pour annuler une notification d’appel par `roomId`.
int incomingNotificationId(String roomId) {
  return roomId.hashCode & 0x3fffffff;
}

@pragma('vm:entry-point')
Future<void> patientFirebaseBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  } catch (_) {}
  await PushNotificationService.handleRemoteDataMessage(message.data);
}

@pragma('vm:entry-point')
void patientNotificationBackgroundResponse(NotificationResponse details) {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(PushNotificationService.handleNotificationResponse(details));
}

class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  FirebaseMessaging? _messaging;
  FlutterLocalNotificationsPlugin? _local;
  bool _initialized = false;
  StreamSubscription<String>? _tokenRefreshSub;
  String? _lastToken;

  static GlobalKey<NavigatorState>? navigatorKey;

  static Future<void> handleRemoteDataMessage(Map<String, dynamic> raw) async {
    final data = raw.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''));
    final type = data['type'] ?? '';
    if (type == 'cancel_incoming_call') {
      final rid = data['roomId'] ?? '';
      if (rid.isEmpty) return;
      await _ensureLocalPlugin();
      await _localStatic?.cancel(id: incomingNotificationId(rid));
      if (!kIsWeb) {
        await CallkitService.instance.endCall(rid);
      }
      return;
    }
    if (type == 'incoming_call') {
      // Pas de notification locale pour l’appel entrant (push « incoming_call » désactivé côté serveur).
      // Persistance optionnelle si un ancien message FCM arrive encore.
      PendingCallIntent.setFromPayload(data, answer: true);
      await PendingCallIntent.persist();
      return;
    }
  }

  /// Premier plan / tap utilisateur : persistance + socket + demande d’offre SDP en attente.
  static Future<void> syncIncomingCallForRealtime(Map<String, String> data) async {
    if (kIsWeb) return;
    if ((data['type'] ?? '') != 'incoming_call') return;
    PendingCallIntent.setFromPayload(data, answer: true);
    await PendingCallIntent.persist();
    await WebRtcService.instance.handleIncomingCallFromNotification(data);
  }

  static FlutterLocalNotificationsPlugin? _localStatic;

  static Future<void> _ensureLocalPlugin() async {
    if (_localStatic != null) return;
    _localStatic = FlutterLocalNotificationsPlugin();
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    await _localStatic!.initialize(
      settings: const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: (NotificationResponse r) {
        unawaited(handleNotificationResponse(r));
      },
      onDidReceiveBackgroundNotificationResponse: patientNotificationBackgroundResponse,
    );
    await _ensureChannels(_localStatic!);
  }

  static Future<void> _ensureChannels(FlutterLocalNotificationsPlugin local) async {
    final android = local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _kMissedChannelId,
        'Appels manqués',
        description: 'Historique des appels manqués',
        importance: Importance.high,
      ),
    );
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _kDefaultChannelId,
        'Notifications patient',
        importance: Importance.defaultImportance,
      ),
    );
  }

  static Future<void> handleNotificationResponse(NotificationResponse response) async {
    final action = response.actionId;
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;

    if (payload.startsWith('incoming_call|')) {
      final raw = payload.substring('incoming_call|'.length);
      Map<String, String> data;
      try {
        data = Map<String, String>.from(jsonDecode(raw) as Map);
      } catch (_) {
        return;
      }
      final decline = action == 'incoming_decline';
      final answer = !decline &&
          (action == null ||
              action.isEmpty ||
              action == 'incoming_answer' ||
              response.notificationResponseType == NotificationResponseType.selectedNotification);

      if (decline) {
        final room = data['roomId'] ?? '';
        final doctor = data['fromUserId'] ?? '';
        if (room.isNotEmpty && doctor.isNotEmpty) {
          final p = await SharedPreferences.getInstance();
          await p.setString('pending_socket_reject_room', room);
          await p.setString('pending_socket_reject_to', doctor);
        }
        final rid = data['roomId'] ?? '';
        if (rid.isNotEmpty) {
          await _ensureLocalPlugin();
          await _localStatic?.cancel(id: incomingNotificationId(rid));
        }
        return;
      }

      if (answer) {
        final rid = data['roomId'] ?? '';
        if (rid.isNotEmpty) {
          await _ensureLocalPlugin();
          await _localStatic?.cancel(id: incomingNotificationId(rid));
        }
        PendingCallIntent.setFromPayload(data, answer: true);
        await PendingCallIntent.persist();
        await PushNotificationService.syncIncomingCallForRealtime(data);
        _pushChatOpener();
      }
      return;
    }

    if (payload.startsWith('missed_call|')) {
      final raw = payload.substring('missed_call|'.length);
      try {
        final data = Map<String, String>.from(jsonDecode(raw) as Map);
        PendingMissedCallIntent.setFromPayload(data);
        await PendingMissedCallIntent.persist();
        _pushChatOpener();
      } catch (_) {}
    }
  }

  static void _pushChatOpener() {
    var tries = 0;
    void go() {
      tries++;
      final nav = navigatorKey?.currentState;
      if (nav != null && nav.mounted) {
        nav.push<void>(
          MaterialPageRoute<void>(
            builder: (_) => const ChatOpenerFromPush(),
          ),
        );
        return;
      }
      if (tries >= 40) return;
      WidgetsBinding.instance.addPostFrameCallback((_) => go());
    }

    go();
  }

  // --- Instance methods (foreground init) ---

  Future<void> initializeForPatient({required String patientId}) async {
    if (kIsWeb) {
      debugPrint('[PUSH] Notifications natives indisponibles sur Web.');
      return;
    }
    if (patientId.trim().isEmpty) return;
    if (!_initialized) {
      await _bootstrap();
      _initialized = true;
    }
    await _registerCurrentToken();
    await _setupInteractedMessage();
    CallkitService.instance.listenEvents();
  }

  Future<void> _setupInteractedMessage() async {
    final messaging = _messaging;
    if (messaging == null) return;
    final initial = await messaging.getInitialMessage();
    if (initial != null) {
      await _handleOpenedRemote(initial);
    }
    FirebaseMessaging.onMessageOpenedApp.listen(_handleOpenedRemote);
  }

  Future<void> _handleOpenedRemote(RemoteMessage message) async {
    final data = message.data.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''));
    final type = data['type'] ?? '';
    if (type == 'call_missed') {
      PendingMissedCallIntent.setFromPayload(data);
      await PendingMissedCallIntent.persist();
      _pushChatOpener();
      return;
    }
    if (type == 'incoming_call') {
      PendingCallIntent.setFromPayload(data, answer: true);
      await PendingCallIntent.persist();
      await PushNotificationService.syncIncomingCallForRealtime(data);
      _pushChatOpener();
    }
  }

  Future<void> _bootstrap() async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
    } catch (e) {
      debugPrint('[PUSH] Firebase.initializeApp: $e');
    }
    try {
      _messaging = FirebaseMessaging.instance;
      _local = FlutterLocalNotificationsPlugin();
    } catch (_) {
      return;
    }
    final messaging = _messaging;
    final local = _local;
    if (messaging == null || local == null) return;
    _localStatic = local;

    await messaging.requestPermission(alert: true, badge: true, sound: true);

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    await local.initialize(
      settings: InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (r) => PushNotificationService.handleNotificationResponse(r),
      onDidReceiveBackgroundNotificationResponse: patientNotificationBackgroundResponse,
    );
    await PushNotificationService._ensureChannels(local);

    FirebaseMessaging.onMessage.listen((message) async {
      final data = message.data;
      final type = data['type'] ?? '';
      if (type == 'cancel_incoming_call') {
        final rid = data['roomId'] ?? '';
        if (rid.isNotEmpty) {
          await local.cancel(id: incomingNotificationId(rid));
        }
        return;
      }
      if (type == 'incoming_call') {
        final map = data.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''));
        final cid = (map['callId']?.trim().isNotEmpty == true ? map['callId']! : (map['roomId'] ?? '')).trim();
        if (cid.isNotEmpty && await CallkitService.instance.hasActiveCallUi(cid)) {
          return;
        }
        await PushNotificationService.syncIncomingCallForRealtime(map);
        return;
      }
      if (type == 'call_missed') {
        final n = message.notification;
        final title = n?.title ?? 'Appel manqué';
        final body = n?.body ?? '';
        final payloadMap = data.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''));
        await local.show(
          id: (payloadMap['messageId'] ?? title).hashCode & 0x3fffffff,
          title: title,
          body: body,
          notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(
              _kMissedChannelId,
              'Appels manqués',
              channelDescription: 'Historique',
              importance: Importance.high,
              priority: Priority.high,
              styleInformation: BigTextStyleInformation(body),
              icon: '@mipmap/ic_launcher',
            ),
            iOS: const DarwinNotificationDetails(),
          ),
          payload: 'missed_call|${jsonEncode(payloadMap)}',
        );
        return;
      }
      final n = message.notification;
      if (n == null) return;
      await local.show(
        id: n.hashCode & 0x3fffffff,
        title: n.title ?? 'Télémedecine',
        body: n.body ?? '',
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _kDefaultChannelId,
            'Notifications patient',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
        ),
      );
    });

    _tokenRefreshSub?.cancel();
    _tokenRefreshSub = messaging.onTokenRefresh.listen((_) async {
      await _registerCurrentToken();
    });
  }

  Future<void> _registerCurrentToken() async {
    final messaging = _messaging;
    if (messaging == null) return;
    final token = await messaging.getToken();
    if (token == null || token.trim().isEmpty) return;
    _lastToken = token;
    final platform = Platform.isAndroid ? 'android' : (Platform.isIOS ? 'ios' : 'other');
    try {
      await ApiService.registerPushDevice(token: token, platform: platform);
      debugPrint('[PUSH] Token FCM enregistré (platform=$platform).');
    } catch (e) {
      debugPrint('[PUSH] Échec enregistrement token : $e');
    }
  }

  Future<void> unregisterCurrentDevice() async {
    final messaging = _messaging;
    if (messaging == null) return;
    final token = _lastToken ?? await messaging.getToken();
    if (token == null || token.trim().isEmpty) return;
    try {
      await ApiService.unregisterPushDevice(token: token);
    } catch (_) {}
  }
}
