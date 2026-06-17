import 'package:flutter/material.dart';

import 'api_service.dart';

/// Données de conversation pour les messages système liés aux appels WebRTC.
class CallChatContext {
  CallChatContext._();

  static String? conversationId;
  static String? doctorId;
  static String? patientId;
  static bool isPatientSide = false;
  /// Patient : [WaitingRoomScreen] est sous la pile d’appel.
  static bool waitingRoomRouteActive = false;

  static Future<void> Function()? onReloadMessages;

  static void register({
    String? conversationId,
    required String doctorId,
    required String patientId,
    required bool isPatientSide,
    Future<void> Function()? onReloadMessages,
  }) {
    CallChatContext.conversationId = conversationId;
    CallChatContext.doctorId = doctorId;
    CallChatContext.patientId = patientId;
    CallChatContext.isPatientSide = isPatientSide;
    CallChatContext.onReloadMessages = onReloadMessages;
  }

  static void updateConversationId(String? id) {
    conversationId = id;
  }

  static void unregister() {
    conversationId = null;
    doctorId = null;
    patientId = null;
    isPatientSide = false;
    waitingRoomRouteActive = false;
    onReloadMessages = null;
  }

  /// L’historique d’appel (terminé / refusé) est enregistré côté serveur sur `call:end` / `call:reject`.
  static Future<void> sendCallEnded({
    required Duration duration,
    required String roomId,
    required bool hadConnected,
  }) async {}

  /// Idem : le serveur persiste au `call:reject`.
  static Future<void> sendCallRejectedByPatient() async {}

  /// Appel sans réponse (timeout côté médecin) : pas d’événement socket dédié, envoi REST conservé.
  static Future<void> sendCallMissed({bool isVideo = false}) async {
    if (isPatientSide || conversationId == null) return;
    final mt = isVideo ? 'video' : 'audio';
    await ApiService.sendMessage(
      conversationId: conversationId!,
      fromType: 'system',
      type: 'call_event',
      content: isVideo ? 'Appel vidéo manqué' : 'Appel manqué',
      payload: {
        'kind': 'call_log',
        'mediaType': mt,
        'outcome': 'missed',
        'durationSeconds': 0,
      },
    );
    await onReloadMessages?.call();
  }

  /// Revient au chat : un pop pour l’appel, un second si la salle d’attente est encore sous-jacente.
  static void popCallStack(BuildContext context) {
    popCallStackWithNavigator(Navigator.of(context));
  }

  /// À utiliser après un `await` : capturer [Navigator.of] avant l’asynchrone, puis vérifier [NavigatorState.mounted].
  static void popCallStackWithNavigator(NavigatorState nav) {
    final extra = waitingRoomRouteActive;
    if (nav.canPop()) nav.pop();
    if (extra && nav.canPop()) nav.pop();
    waitingRoomRouteActive = false;
  }
}
