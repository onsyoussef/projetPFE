import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'api_service.dart';

@pragma('vm:entry-point')
Future<void> doctorFirebaseBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {}
}

class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  FirebaseMessaging? _messaging;
  FlutterLocalNotificationsPlugin? _local;
  bool _initialized = false;
  StreamSubscription<String>? _tokenRefreshSub;
  String? _lastToken;

  Future<void> initializeForDoctor({required String doctorId}) async {
    if (kIsWeb || doctorId.trim().isEmpty) return;
    if (!_initialized) {
      await _bootstrap();
      _initialized = true;
    }
    await _registerCurrentToken();
  }

  Future<void> _bootstrap() async {
    try {
      await Firebase.initializeApp();
    } catch (_) {}
    try {
      _messaging = FirebaseMessaging.instance;
      _local = FlutterLocalNotificationsPlugin();
    } catch (_) {
      return;
    }
    final messaging = _messaging;
    final local = _local;
    if (messaging == null || local == null) return;

    FirebaseMessaging.onBackgroundMessage(doctorFirebaseBackgroundHandler);
    await messaging.requestPermission(alert: true, badge: true, sound: true);

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await local.initialize(settings: initSettings);

    const channel = AndroidNotificationChannel(
      'telemedecine_doctor_channel',
      'Notifications médecin',
      importance: Importance.max,
    );
    await local
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    FirebaseMessaging.onMessage.listen((message) async {
      final n = message.notification;
      if (n == null) return;
      await local.show(
        id: n.hashCode,
        title: n.title ?? 'Télémedecine',
        body: n.body ?? '',
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'telemedecine_doctor_channel',
            'Notifications médecin',
            importance: Importance.max,
            priority: Priority.high,
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
    } catch (_) {}
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
