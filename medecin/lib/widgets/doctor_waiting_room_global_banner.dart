import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../chat_medecin_page.dart';
import '../headsapp_theme.dart';
import '../services/call_chat_context.dart';
import '../services/webrtc_service.dart';
import '../session_keys.dart';
import '../utils/doctor_ui_utils.dart';

/// Bannière globale : patient en salle d’attente (hors écran chat concerné).
class DoctorWaitingRoomGlobalBanner extends StatefulWidget {
  const DoctorWaitingRoomGlobalBanner({super.key, required this.navigatorKey});

  final GlobalKey<NavigatorState> navigatorKey;

  @override
  State<DoctorWaitingRoomGlobalBanner> createState() =>
      _DoctorWaitingRoomGlobalBannerState();
}

class _PendingWaiting {
  _PendingWaiting({
    required this.conversationId,
    required this.patientId,
    required this.patientName,
  });

  final String conversationId;
  final String patientId;
  final String patientName;
  Timer? autoDismiss;
}

class _DoctorWaitingRoomGlobalBannerState
    extends State<DoctorWaitingRoomGlobalBanner> {
  StreamSubscription<Map<String, dynamic>>? _waitingSub;
  StreamSubscription<Map<String, dynamic>>? _leftSub;
  _PendingWaiting? _visible;

  @override
  void initState() {
    super.initState();
    _waitingSub = WebRtcService.instance.consultationPatientWaiting.listen(
      _onWaiting,
    );
    _leftSub = WebRtcService.instance.consultationPatientLeftWaiting.listen(
      _onLeft,
    );
  }

  void _onWaiting(Map<String, dynamic> data) {
    final cid = data['conversationId']?.toString() ?? '';
    final pid = data['patientId']?.toString() ?? '';
    final name = data['patientName']?.toString().trim().isNotEmpty == true
        ? readablePatientName(data['patientName']?.toString())
        : 'Patient';
    if (cid.isEmpty || pid.isEmpty) return;

    final inSameChat =
        !CallChatContext.isPatientSide &&
        CallChatContext.conversationId != null &&
        CallChatContext.conversationId == cid;
    if (inSameChat) return;

    _visible?.autoDismiss?.cancel();
    setState(() {
      _visible = _PendingWaiting(
        conversationId: cid,
        patientId: pid,
        patientName: name,
      );
    });
    _visible!.autoDismiss = Timer(const Duration(seconds: 10), () {
      if (!mounted) return;
      if (_visible?.conversationId == cid) {
        setState(() => _visible = null);
      }
    });
  }

  void _onLeft(Map<String, dynamic> data) {
    final cid = data['conversationId']?.toString() ?? '';
    if (cid.isEmpty) return;
    if (_visible?.conversationId != cid) return;
    _visible?.autoDismiss?.cancel();
    if (mounted) setState(() => _visible = null);
  }

  Future<void> _openChat() async {
    final v = _visible;
    if (v == null) return;
    final prefs = await SharedPreferences.getInstance();
    final doctorId = prefs.getString(kSessionDoctorIdKey) ?? '';
    if (doctorId.isEmpty) return;
    v.autoDismiss?.cancel();
    if (!mounted) return;
    setState(() => _visible = null);
    final nav = widget.navigatorKey.currentState;
    if (nav == null || !nav.mounted) return;
    await nav.push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ChatMedecinPage(
          conversationId: v.conversationId,
          patientId: v.patientId,
          patientName: v.patientName,
          doctorId: doctorId,
          patientPhotoPath: null,
        ),
      ),
    );
  }

  void _dismiss() {
    _visible?.autoDismiss?.cancel();
    setState(() => _visible = null);
  }

  @override
  void dispose() {
    _visible?.autoDismiss?.cancel();
    _waitingSub?.cancel();
    _leftSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = _visible;
    if (v == null) return const SizedBox();

    final padTop = MediaQuery.paddingOf(context).top + 8;
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, padTop, 12, 0),
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(14),
          color: HeadsAppColors.textPrimary,
          child: InkWell(
            onTap: _dismiss,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: HeadsAppColors.success.withValues(
                      alpha: 0.18,
                    ),
                    child: const Icon(
                      Icons.person_rounded,
                      color: HeadsAppColors.success,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          v.patientName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'attend dans la salle d\'attente',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: _openChat,
                    style: TextButton.styleFrom(
                      foregroundColor: HeadsAppColors.brandAccent,
                    ),
                    child: const Text('Ouvrir le chat'),
                  ),
                  IconButton(
                    onPressed: _dismiss,
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.white70,
                    ),
                    tooltip: 'Fermer',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
