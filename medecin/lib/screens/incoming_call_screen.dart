import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../providers/call_provider.dart';
import '../services/call_chat_context.dart';
import '../services/permission_service.dart';
import '../services/webrtc_service.dart';
import 'active_call_screen.dart';

class IncomingCallScreen extends StatelessWidget {
  const IncomingCallScreen({
    super.key,
    required this.callProvider,
    required this.fromUserId,
    required this.displayName,
    required this.roomId,
    required this.offer,
    this.isVideoCall = false,
    this.avatarUrl,
  });

  final CallProvider callProvider;
  final String fromUserId;
  final String displayName;
  final String roomId;
  final Map<String, dynamic> offer;
  final bool isVideoCall;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    final title = isVideoCall ? 'Appel vidéo entrant' : 'Appel audio entrant';
    final subtitle = isVideoCall ? 'Appel vidéo entrant…' : 'Appel audio entrant…';
    return Scaffold(
      appBar: AppBar(title: Text(title)),
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
                      avatarUrl != null && avatarUrl!.isNotEmpty
                          ? NetworkImage(avatarUrl!)
                          : null,
                  child: avatarUrl == null || avatarUrl!.isEmpty
                      ? const Icon(Icons.person_rounded, size: 42)
                      : null,
                ),
                const SizedBox(height: 12),
                Text(
                  displayName,
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
                        callProvider.rejectIncomingCall(fromUserId);
                        if (!navigator.mounted) return;
                        CallChatContext.popCallStackWithNavigator(navigator);
                        callProvider.resetAfterCallUi();
                      },
                      child: const Icon(Icons.call_end_rounded),
                    ),
                    const SizedBox(width: 20),
                    FloatingActionButton(
                      backgroundColor: Colors.green,
                      heroTag: 'accept_call',
                      onPressed: () async {
                        late final bool ok;
                        if (isVideoCall) {
                          // ignore: use_build_context_synchronously — PermissionService vérifie mounted avant dialogs
                          ok = await PermissionService.instance.ensureCameraAndMicrophonePermissions(context);
                        } else {
                          // ignore: use_build_context_synchronously
                          ok = await PermissionService.instance.ensureMicrophonePermission(context);
                        }
                        if (!ok || !context.mounted) return;
                        final accepted = await callProvider.acceptIncomingCall(
                          fromUserId: fromUserId,
                          callRoomId: roomId,
                          offer: offer,
                          isVideo: isVideoCall,
                        );
                        if (!accepted) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Échec initialisation appel. Vérifiez micro/réseau.'),
                            ),
                          );
                          return;
                        }
                        if (!context.mounted) return;
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute<void>(
                            builder: (_) => ActiveCallScreen(
                              callProvider: callProvider,
                              displayName: displayName,
                              avatarUrl: avatarUrl,
                              isVideoCall: isVideoCall,
                            ),
                          ),
                        );
                      },
                      child: const Icon(Icons.call_rounded),
                    ),
                  ],
                ),
                if (isVideoCall && WebRtcService.instance.isLocalRendererReady)
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
