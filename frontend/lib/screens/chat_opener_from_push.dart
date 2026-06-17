import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../chat_page.dart';
import '../services/api_service.dart';
import '../services/pending_call_intent.dart';
import '../services/webrtc_service.dart';
import '../utils/patient_ui_utils.dart';

/// Ouvre le chat patient↔médecin après un tap sur une notification (appel entrant / manqué).
class ChatOpenerFromPush extends StatefulWidget {
  const ChatOpenerFromPush({super.key});

  @override
  State<ChatOpenerFromPush> createState() => _ChatOpenerFromPushState();
}

class _ChatOpenerFromPushState extends State<ChatOpenerFromPush> {
  Widget? _page;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await PendingCallIntent.loadFromPrefs();
    await PendingMissedCallIntent.loadFromPrefs();
    final prefs = await SharedPreferences.getInstance();
    final patientId = prefs.getString('patientId') ?? '';
    if (!mounted || patientId.isEmpty) {
      if (mounted) Navigator.of(context).pop();
      return;
    }

    if (PendingCallIntent.hasPending && PendingCallIntent.wantsAnswer) {
      final did = PendingCallIntent.doctorId ?? '';
      final dname = readableDoctorName(PendingCallIntent.doctorName);
      final room = PendingCallIntent.roomId;
      if (did.isNotEmpty) {
        setState(() {
          _page = ChatPage(
            patientId: patientId,
            doctorId: did,
            doctorName: dname,
          );
        });
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (room != null && room.isNotEmpty) {
            final payload = <String, String>{
              'type': 'incoming_call',
              'roomId': room,
              if ((PendingCallIntent.doctorId ?? '').isNotEmpty) 'doctorId': PendingCallIntent.doctorId!,
              if ((PendingCallIntent.doctorName ?? '').isNotEmpty) 'doctorName': PendingCallIntent.doctorName!,
              if ((PendingCallIntent.conversationId ?? '').isNotEmpty)
                'conversationId': PendingCallIntent.conversationId!,
              if ((PendingCallIntent.fromUserId ?? '').isNotEmpty) 'fromUserId': PendingCallIntent.fromUserId!,
              'mediaType': PendingCallIntent.isVideo ? 'video' : 'audio',
            };
            WebRtcService.instance.ensureSocketConnected(
              selfUserId: patientId,
              jwtToken: ApiService.jwtToken,
            );
            await WebRtcService.instance.handleIncomingCallFromNotification(payload);
          }
          await PendingCallIntent.clear();
        });
        return;
      }
    }

    if (PendingMissedCallIntent.hasPending) {
      final did = PendingMissedCallIntent.doctorId ?? '';
      final dname = readableDoctorName(PendingMissedCallIntent.doctorName);
      if (did.isNotEmpty) {
        setState(() {
          _page = ChatPage(
            patientId: patientId,
            doctorId: did,
            doctorName: dname,
          );
        });
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          await PendingMissedCallIntent.clear();
        });
        return;
      }
    }

    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return _page ??
        const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
  }
}
