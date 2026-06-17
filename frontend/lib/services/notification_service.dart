import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart' show FirebaseMessaging, RemoteMessage;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'callkit_service.dart';
import 'pending_call_intent.dart';
import 'push_notification_service.dart';

/// Handler FCM en isolate séparé (app terminée / arrière-plan). Doit rester une fonction de premier niveau.
@pragma('vm:entry-point')
Future<void> patientCallFcmBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  } catch (_) {}
  final raw = message.data.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''));
  final type = raw['type'] ?? '';
  if (type == 'incoming_call') {
    await PendingCallIntent.loadFromPrefs();
    PendingCallIntent.setFromPayload(raw, answer: true);
    await PendingCallIntent.persist();
    await CallkitService.instance.showIncomingCall(raw);
    return;
  }
  await PushNotificationService.handleRemoteDataMessage(
    Map<String, dynamic>.from(message.data),
  );
}

/// Orchestration FCM + CallKit (WhatsApp-like).
class NotificationService {
  NotificationService._();

  /// À appeler une seule fois au démarrage (avant [runApp]) pour les messages data en arrière-plan.
  static void registerBackgroundHandler() {
    if (kIsWeb) return;
    FirebaseMessaging.onBackgroundMessage(patientCallFcmBackgroundHandler);
  }

}
