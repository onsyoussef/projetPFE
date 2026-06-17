import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../providers/call_provider.dart';
import '../screens/incoming_call_screen.dart';
import '../services/api_service.dart';
import '../services/pending_call_intent.dart';
import '../services/webrtc_service.dart';

class PatientIncomingCallHost extends StatefulWidget {
  const PatientIncomingCallHost({
    super.key,
    required this.patientId,
    required this.child,
  });

  final String patientId;
  final Widget child;

  @override
  State<PatientIncomingCallHost> createState() => _PatientIncomingCallHostState();
}

class _PatientIncomingCallHostState extends State<PatientIncomingCallHost>
    with WidgetsBindingObserver {
  late final CallProvider _callProvider;
  StreamSubscription<Map<String, dynamic>>? _incomingSub;
  bool _dialogVisible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _callProvider = CallProvider(webRtcService: WebRtcService.instance);
    WebRtcService.instance.connectSocket(
      selfUserId: widget.patientId,
      jwtToken: ApiService.jwtToken,
    );
    _incomingSub = WebRtcService.instance.incomingCalls.listen(_handleIncomingCall);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      WebRtcService.instance.emitPatientAppLifecycle(true);
      await _consumePendingCallIntent();
    });
  }

  Future<void> _consumePendingCallIntent() async {
    await PendingCallIntent.loadFromPrefs();
    final roomId = PendingCallIntent.roomId?.trim() ?? '';
    if (!PendingCallIntent.hasPending || !PendingCallIntent.wantsAnswer || roomId.isEmpty) {
      return;
    }
    final conv = PendingCallIntent.conversationId?.trim() ?? '';
    if (conv.isNotEmpty) {
      WebRtcService.instance.joinConversationRoom(conv);
    }
    WebRtcService.instance.ensureSocketConnected(
      selfUserId: widget.patientId,
      jwtToken: ApiService.jwtToken,
    );
    WebRtcService.instance.requestPendingOffer(roomId);
    await PendingCallIntent.clear();
  }

  Future<void> _handleIncomingCall(Map<String, dynamic> data) async {
    if (!mounted) return;
    final roomId = data['roomId']?.toString() ?? '';
    // Ne pas utiliser `from` (socket id) — seul `fromUserId` est valide pour call:answer / ICE.
    final fromUserId = data['fromUserId']?.toString().trim() ?? '';
    final sdp = _coerceOfferSdp(data['sdp']);
    if (roomId.isEmpty || fromUserId.isEmpty || sdp == null || sdp.isEmpty) {
      debugPrint(
        '[PatientIncomingCallHost] appel entrant ignoré roomId=$roomId fromUserId=$fromUserId '
        'sdpType=${data['sdp']?.runtimeType}',
      );
      return;
    }
    if (_dialogVisible) return;

    final mediaType = data['mediaType']?.toString() ?? 'audio';
    final callerInfo = Map<String, dynamic>.from((data['callerInfo'] as Map?) ?? const {});
    _dialogVisible = true;

    await Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => IncomingCallScreen(
          callProvider: _callProvider,
          fromUserId: fromUserId,
          displayName: callerInfo['name']?.toString() ?? 'Médecin',
          avatarUrl: callerInfo['avatarUrl']?.toString(),
          roomId: roomId,
          offer: Map<String, dynamic>.from(sdp),
          isVideoCall: mediaType == 'video',
        ),
      ),
    );

    _dialogVisible = false;
    _callProvider.resetAfterCallUi();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final inForeground = state == AppLifecycleState.resumed;
    WebRtcService.instance.emitPatientAppLifecycle(inForeground);
    if (inForeground) {
      unawaited(_consumePendingCallIntent());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _incomingSub?.cancel();
    WebRtcService.instance.emitPatientAppLifecycle(false);
    _callProvider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

/// Normalise l’offre SDP (Map, parfois JSON string selon la couche socket).
Map<String, dynamic>? _coerceOfferSdp(dynamic raw) {
  if (raw == null) return null;
  if (raw is Map) {
    final m = <String, dynamic>{};
    raw.forEach((k, v) {
      m[k.toString()] = v;
    });
    final t = m['type']?.toString() ?? '';
    final s = m['sdp']?.toString() ?? '';
    if (t.isEmpty || s.isEmpty) return null;
    return m;
  }
  if (raw is String) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    try {
      final d = jsonDecode(t);
      if (d is Map) return _coerceOfferSdp(d);
    } catch (_) {}
  }
  return null;
}
