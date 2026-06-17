import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../providers/call_provider.dart';
import '../services/call_chat_context.dart';
import '../services/webrtc_service.dart';

class ActiveCallScreen extends StatefulWidget {
  const ActiveCallScreen({
    super.key,
    required this.callProvider,
    required this.displayName,
    this.isVideoCall = false,
    this.avatarUrl,
  });

  final CallProvider callProvider;
  final String displayName;
  final bool isVideoCall;
  final String? avatarUrl;

  @override
  State<ActiveCallScreen> createState() => _ActiveCallScreenState();
}

class _ActiveCallScreenState extends State<ActiveCallScreen> {
  bool _done = false;

  @override
  void initState() {
    super.initState();
    widget.callProvider.addListener(_onProviderUpdateSync);
  }

  @override
  void dispose() {
    widget.callProvider.removeListener(_onProviderUpdateSync);
    super.dispose();
  }

  void _onProviderUpdateSync() {
    unawaited(_onProviderUpdateAsync());
  }

  Future<void> _onProviderUpdateAsync() async {
    if (!mounted || _done) return;
    final s = widget.callProvider.currentState;
    if (s == CallState.termine ||
        s == CallState.refuse ||
        s == CallState.echec) {
      _done = true;
      final p = widget.callProvider;
      final navigator = Navigator.of(context);
      if (!navigator.mounted) return;
      CallChatContext.popCallStackWithNavigator(navigator);
      p.resetAfterCallUi();
    } else {
      setState(() {});
    }
  }

  String _qualityLabel(RTCPeerConnectionState s) {
    switch (s) {
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        return 'Connecté';
      case RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
        return 'Connexion...';
      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
        return 'Signal faible';
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        return 'Échec';
      default:
        return 'Connexion...';
    }
  }

  Color _qualityColor(RTCPeerConnectionState s) {
    switch (s) {
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        return Colors.green;
      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
        return Colors.orange;
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        return Colors.red;
      default:
        return Colors.blueGrey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = widget.callProvider;
    final quality = provider.connectionState;
    final appBarTitle = widget.isVideoCall ? 'Appel vidéo' : 'Appel audio';
    final hasRemoteRenderer =
        widget.isVideoCall && WebRtcService.instance.isRemoteRendererReady;
    final hasLocalRenderer =
        widget.isVideoCall && WebRtcService.instance.isLocalRendererReady;
    final hasRemoteStream =
        hasRemoteRenderer &&
        WebRtcService.instance.remoteRenderer.srcObject != null;
    final hasLocalStream =
        hasLocalRenderer &&
        WebRtcService.instance.localRenderer.srcObject != null;
    return Scaffold(
      appBar: AppBar(title: Text(appBarTitle)),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.isVideoCall)
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: hasRemoteStream
                                  ? RTCVideoView(
                                      WebRtcService.instance.remoteRenderer,
                                      objectFit: RTCVideoViewObjectFit
                                          .RTCVideoViewObjectFitCover,
                                      mirror: false,
                                    )
                                  : const Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.videocam_off_rounded,
                                            color: Colors.white70,
                                            size: 34,
                                          ),
                                          SizedBox(height: 8),
                                          Text(
                                            'En attente de la vidéo distante...',
                                            style: TextStyle(
                                              color: Colors.white70,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                            ),
                          ),
                        ),
                        if (hasLocalStream)
                          Positioned(
                            top: 12,
                            right: 12,
                            child: SizedBox(
                              width: 110,
                              height: 150,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: RTCVideoView(
                                  WebRtcService.instance.localRenderer,
                                  objectFit:
                                      RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                                  mirror: true,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                if (!widget.isVideoCall) ...[
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
                ],
                if (widget.isVideoCall) const SizedBox(height: 12),
                Text(
                  widget.displayName,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  provider.formattedDuration(),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.circle, size: 10, color: _qualityColor(quality)),
                    const SizedBox(width: 6),
                    Text(_qualityLabel(quality)),
                  ],
                ),
                const SizedBox(height: 28),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton.filledTonal(
                      onPressed: provider.toggleMute,
                      icon: Icon(provider.isMuted
                          ? Icons.mic_off_rounded
                          : Icons.mic_rounded),
                    ),
                    const SizedBox(width: 16),
                    IconButton.filledTonal(
                      onPressed: () => provider.toggleSpeaker(),
                      icon: Icon(provider.speakerOn
                          ? Icons.volume_up_rounded
                          : Icons.hearing_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 26),
                FloatingActionButton(
                  backgroundColor: Colors.red,
                  onPressed: () async {
                    await provider.endCall();
                  },
                  child: const Icon(Icons.call_end_rounded),
                ),
                if (!widget.isVideoCall && WebRtcService.instance.isRemoteRendererReady)
                  SizedBox(
                    width: 1,
                    height: 1,
                    child: RTCVideoView(
                      WebRtcService.instance.remoteRenderer,
                      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                      mirror: false,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
