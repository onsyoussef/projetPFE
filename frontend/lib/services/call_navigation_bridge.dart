import 'package:flutter/material.dart';

import '../screens/chat_opener_from_push.dart';

/// Évite les imports circulaires entre CallKit et [PushNotificationService].
class CallNavigationBridge {
  CallNavigationBridge._();

  static GlobalKey<NavigatorState>? navigatorKey;

  /// Après acceptation depuis l’UI native — ouvre le flux chat + WebRTC (comme un tap notification).
  static void openChatAfterCallAccepted() {
    final nav = navigatorKey?.currentState;
    if (nav == null || !nav.mounted) return;
    nav.push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const ChatOpenerFromPush(),
      ),
    );
  }
}
