import 'dart:async';

import 'package:flutter/material.dart';

import '../providers/call_provider.dart';
import '../services/api_service.dart';
import '../services/pending_call_intent.dart';
import '../services/webrtc_service.dart';
import '../utils/incoming_call_utils.dart';

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
    await showPatientIncomingCallScreen(
      callProvider: _callProvider,
      data: data,
      fallbackDoctorName: 'Médecin',
    );
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
