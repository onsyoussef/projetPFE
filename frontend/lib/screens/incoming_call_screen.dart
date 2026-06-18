import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../providers/call_provider.dart';
import '../services/call_chat_context.dart';
import '../services/permission_service.dart';
import '../services/webrtc_service.dart';
import 'active_call_screen.dart';

class IncomingCallScreen extends StatefulWidget {
  const IncomingCallScreen({
    super.key,
    required this.callProvider,
    required this.fromUserId,
    required this.displayName,
    required this.roomId,
    required this.offer,
    this.isVideoCall = false,
    this.avatarUrl,
    this.specialty,
  });

  final CallProvider callProvider;
  final String fromUserId;
  final String displayName;
  final String roomId;
  final Map<String, dynamic> offer;
  final bool isVideoCall;
  final String? avatarUrl;
  final String? specialty;

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen> {
  static const String _ringtoneUrl =
      'https://actions.google.com/sounds/v1/alarms/beep_short.ogg';

  late final AudioPlayer _player;
  StreamSubscription<Map<String, dynamic>>? _endedSub;
  StreamSubscription<Map<String, dynamic>>? _rejectedSub;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    unawaited(_player.setReleaseMode(ReleaseMode.loop));
    unawaited(_player.play(UrlSource(_ringtoneUrl)));
    _endedSub = WebRtcService.instance.callEnded.listen((data) {
      if ((data['roomId']?.toString() ?? '') != widget.roomId) return;
      _closeIncomingScreen();
    });
    _rejectedSub = WebRtcService.instance.callRejected.listen((data) {
      if ((data['roomId']?.toString() ?? '') != widget.roomId) return;
      _closeIncomingScreen();
    });
  }

  Future<void> _stopRingtone() async {
    try {
      await _player.stop();
    } catch (_) {}
  }

  void _closeIncomingScreen() {
    if (_closing || !mounted) return;
    _closing = true;
    unawaited(_stopRingtone());
    Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    _endedSub?.cancel();
    _rejectedSub?.cancel();
    unawaited(_stopRingtone());
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = widget.isVideoCall ? 'Appel vidéo entrant...' : 'Appel audio entrant...';
    return Scaffold(
      appBar: AppBar(title: const Text('Appel entrant')),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 46,
                  backgroundImage:
                      widget.avatarUrl != null && widget.avatarUrl!.isNotEmpty
                          ? NetworkImage(widget.avatarUrl!)
                          : null,
                  child: widget.avatarUrl == null || widget.avatarUrl!.isEmpty
                      ? const Icon(Icons.person_rounded, size: 42)
                      : null,
                ),
                const SizedBox(height: 12),
                Text(
                  widget.displayName,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(subtitle),
                const SizedBox(height: 30),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FloatingActionButton(
                      backgroundColor: Colors.red,
                      heroTag: 'reject_call',
                      onPressed: () async {
                        final navigator = Navigator.of(context);
                        await _stopRingtone();
                        widget.callProvider.rejectIncomingCall(
                          widget.fromUserId,
                          callRoomId: widget.roomId,
                        );
                        if (!navigator.mounted) return;
                        CallChatContext.popCallStackWithNavigator(navigator);
                        widget.callProvider.resetAfterCallUi();
                      },
                      child: const Icon(Icons.call_end_rounded),
                    ),
                    const SizedBox(width: 20),
                    FloatingActionButton(
                      backgroundColor: Colors.green,
                      heroTag: 'accept_call',
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final navigator = Navigator.of(context);
                        await _stopRingtone();
                        late final bool ok;
                        if (widget.isVideoCall) {
                          // ignore: use_build_context_synchronously — PermissionService vérifie mounted avant dialogs
                          ok = await PermissionService.instance.ensureCameraAndMicrophonePermissions(context);
                        } else {
                          // ignore: use_build_context_synchronously
                          ok = await PermissionService.instance.ensureMicrophonePermission(context);
                        }
                        if (!ok || !context.mounted) return;
                        final accepted = await widget.callProvider.acceptIncomingCall(
                          fromUserId: widget.fromUserId,
                          callRoomId: widget.roomId,
                          offer: widget.offer,
                          isVideo: widget.isVideoCall,
                        );
                        if (!accepted) {
                          if (!navigator.mounted) return;
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text('Échec initialisation appel. Vérifiez micro/réseau.'),
                            ),
                          );
                          return;
                        }
                        if (!navigator.mounted) return;
                        navigator.pushReplacement(
                          MaterialPageRoute<void>(
                            builder: (_) => ActiveCallScreen(
                              callProvider: widget.callProvider,
                              displayName: widget.displayName,
                              avatarUrl: widget.avatarUrl,
                              specialty: widget.specialty,
                              isVideoCall: widget.isVideoCall,
                            ),
                          ),
                        );
                      },
                      child: const Icon(Icons.call_rounded),
                    ),
                  ],
                ),
                if (widget.isVideoCall && WebRtcService.instance.isLocalRendererReady)
                  SizedBox(
                    width: 1,
                    height: 1,
                    child: RTCVideoView(WebRtcService.instance.localRenderer, mirror: true),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
