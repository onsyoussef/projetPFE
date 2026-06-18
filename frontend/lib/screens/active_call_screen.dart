import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../providers/call_provider.dart';
import '../services/api_service.dart';
import '../services/call_chat_context.dart';
import '../services/webrtc_service.dart';
import '../utils/patient_ui_utils.dart';

class ActiveCallScreen extends StatefulWidget {
  const ActiveCallScreen({
    super.key,
    required this.callProvider,
    required this.displayName,
    this.isVideoCall = false,
    this.avatarUrl,
    this.specialty,
  });

  final CallProvider callProvider;
  final String displayName;
  final bool isVideoCall;
  final String? avatarUrl;
  final String? specialty;

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

  String _doctorDisplayName() {
    return readableDoctorName(widget.displayName);
  }

  String? _resolvedAvatarUrl() {
    return ApiService.resolveMediaUrlOrNull(widget.avatarUrl);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isVideoCall) {
      return _buildAudioCallScaffold(context);
    }
    return _buildVideoCallScaffold(context);
  }

  Widget _buildAudioCallScaffold(BuildContext context) {
    final provider = widget.callProvider;
    final doctorName = _doctorDisplayName();
    final specialty = readableDecryptedField(widget.specialty?.toString());
    final photoUrl = _resolvedAvatarUrl();

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 28),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFE3F2FD),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                'APPEL EN COURS',
                style: TextStyle(
                  color: Color(0xFF1A458B),
                  fontWeight: FontWeight.w800,
                  fontSize: 11.5,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              doctorName,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: Color(0xFF111827),
                letterSpacing: -0.3,
              ),
            ),
            if (specialty.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                specialty,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF6B7280),
                ),
              ),
            ],
            const Spacer(),
            _AudioCallAvatar(
              photoUrl: photoUrl,
              timerLabel: provider.formattedDuration(),
            ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _CallControlButton(
                  icon: provider.isMuted
                      ? Icons.mic_off_rounded
                      : Icons.mic_rounded,
                  label: 'MUET',
                  active: false,
                  onPressed: provider.toggleMute,
                ),
                const SizedBox(width: 28),
                _CallControlButton(
                  icon: provider.speakerOn
                      ? Icons.volume_up_rounded
                      : Icons.volume_up_outlined,
                  label: 'HAUT-PARLEUR',
                  active: provider.speakerOn,
                  onPressed: () => provider.toggleSpeaker(),
                ),
                const SizedBox(width: 28),
                const _CallControlButton(
                  icon: Icons.videocam_rounded,
                  label: 'VIDEO',
                  active: false,
                  onPressed: null,
                ),
              ],
            ),
            const SizedBox(height: 36),
            Material(
              color: const Color(0xFFC82333),
              elevation: 6,
              shadowColor: const Color(0xFFC82333).withValues(alpha: 0.45),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () async {
                  await provider.endCall();
                },
                child: const SizedBox(
                  width: 72,
                  height: 72,
                  child: Icon(
                    Icons.call_end_rounded,
                    color: Colors.white,
                    size: 34,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.shield_outlined,
                  size: 14,
                  color: Colors.grey.shade500,
                ),
                const SizedBox(width: 6),
                Text(
                  'APPEL SÉCURISÉ DE BOUT EN BOUT',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.6,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (WebRtcService.instance.isRemoteRendererReady)
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
    );
  }

  Widget _buildVideoCallScaffold(BuildContext context) {
    final provider = widget.callProvider;
    final doctorName = _doctorDisplayName();
    final hasRemoteRenderer = WebRtcService.instance.isRemoteRendererReady;
    final hasLocalRenderer = WebRtcService.instance.isLocalRendererReady;
    final hasRemoteStream =
        hasRemoteRenderer &&
        WebRtcService.instance.remoteRenderer.srcObject != null;
    final hasLocalStream =
        hasLocalRenderer &&
        WebRtcService.instance.localRenderer.srcObject != null;
    final quality = provider.connectionState;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: hasRemoteStream
                ? RTCVideoView(
                    WebRtcService.instance.remoteRenderer,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    mirror: false,
                  )
                : Container(
                    color: const Color(0xFF0F172A),
                    alignment: Alignment.center,
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.videocam_off_rounded,
                          color: Colors.white70,
                          size: 40,
                        ),
                        SizedBox(height: 10),
                        Text(
                          'En attente de la vidéo du médecin…',
                          style: TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 140,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.55),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Stack(
              children: [
                Positioned(
                  top: 8,
                  left: 16,
                  right: 12,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 9,
                                  height: 9,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFEF4444),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    doctorName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 17,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Padding(
                              padding: const EdgeInsets.only(left: 17),
                              child: Text(
                                'EN DIRECT • ${provider.formattedDuration()}',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.88),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Material(
                        color: Colors.white.withValues(alpha: 0.16),
                        shape: const CircleBorder(),
                        child: PopupMenuButton<String>(
                          padding: EdgeInsets.zero,
                          icon: const Icon(
                            Icons.more_vert_rounded,
                            color: Colors.white,
                          ),
                          color: Colors.white,
                          onSelected: (_) {},
                          itemBuilder: (ctx) => [
                            PopupMenuItem(
                              enabled: false,
                              child: Text(
                                'Qualité : ${_qualityLabel(quality)}',
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (hasLocalStream)
                  Positioned(
                    right: 16,
                    bottom: 118,
                    child: _PatientVideoPiP(
                      videoEnabled: provider.videoEnabled,
                    ),
                  ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16,
                  child: _VideoCallControlBar(
                    isMuted: provider.isMuted,
                    videoEnabled: provider.videoEnabled,
                    onToggleMute: provider.toggleMute,
                    onToggleVideo: provider.toggleVideo,
                    onEndCall: () async {
                      await provider.endCall();
                    },
                    onOpenMessages: () {
                      Navigator.of(context).pop();
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
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
}

class _PatientVideoPiP extends StatelessWidget {
  const _PatientVideoPiP({required this.videoEnabled});

  final bool videoEnabled;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: 108,
        height: 156,
        decoration: BoxDecoration(
          color: const Color(0xFF1F2937),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.35),
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (videoEnabled)
              RTCVideoView(
                WebRtcService.instance.localRenderer,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                mirror: true,
              )
            else
              const Center(
                child: Icon(
                  Icons.videocam_off_rounded,
                  color: Colors.white70,
                  size: 32,
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 6),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.65),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: const Text(
                  'Vous',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoCallControlBar extends StatelessWidget {
  const _VideoCallControlBar({
    required this.isMuted,
    required this.videoEnabled,
    required this.onToggleMute,
    required this.onToggleVideo,
    required this.onEndCall,
    required this.onOpenMessages,
  });

  final bool isMuted;
  final bool videoEnabled;
  final VoidCallback onToggleMute;
  final VoidCallback onToggleVideo;
  final Future<void> Function() onEndCall;
  final VoidCallback onOpenMessages;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.42),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.12),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _VideoOverlayControlButton(
                icon: isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                label: 'MUET',
                onPressed: onToggleMute,
              ),
              _VideoOverlayControlButton(
                icon: videoEnabled
                    ? Icons.videocam_rounded
                    : Icons.videocam_off_rounded,
                label: 'CAMÉRA',
                onPressed: onToggleVideo,
              ),
              _VideoOverlayControlButton(
                icon: Icons.call_end_rounded,
                label: 'QUITTER',
                isDestructive: true,
                size: 58,
                onPressed: () => onEndCall(),
              ),
              _VideoOverlayControlButton(
                icon: Icons.chat_bubble_outline_rounded,
                label: 'MESSAGES',
                onPressed: onOpenMessages,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VideoOverlayControlButton extends StatelessWidget {
  const _VideoOverlayControlButton({
    required this.icon,
    required this.label,
    this.onPressed,
    this.isDestructive = false,
    this.size = 48,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool isDestructive;
  final double size;

  @override
  Widget build(BuildContext context) {
    final bg = isDestructive
        ? const Color(0xFFEF4444)
        : Colors.white.withValues(alpha: 0.14);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: bg,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: SizedBox(
              width: size,
              height: size,
              child: Icon(
                icon,
                color: Colors.white,
                size: isDestructive ? 28 : 22,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.92),
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.35,
          ),
        ),
      ],
    );
  }
}

class _AudioCallAvatar extends StatelessWidget {
  const _AudioCallAvatar({
    required this.photoUrl,
    required this.timerLabel,
  });

  final String? photoUrl;
  final String timerLabel;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      height: 220,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFFE5E7EB),
                width: 2,
              ),
            ),
          ),
          Container(
            width: 168,
            height: 168,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFE8F0FE),
              border: Border.all(color: Colors.white, width: 5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
              image: photoUrl != null
                  ? DecorationImage(
                      image: NetworkImage(photoUrl!),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: photoUrl == null
                ? const Icon(
                    Icons.person_rounded,
                    size: 72,
                    color: Color(0xFF1A458B),
                  )
                : null,
          ),
          Positioned(
            bottom: 18,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(999),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Text(
                timerLabel,
                style: const TextStyle(
                  color: Color(0xFF1A458B),
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CallControlButton extends StatelessWidget {
  const _CallControlButton({
    required this.icon,
    required this.label,
    required this.active,
    this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final iconColor = active
        ? const Color(0xFF1A458B)
        : const Color(0xFF6B7280);
    final labelColor = active
        ? const Color(0xFF1A458B)
        : const Color(0xFF6B7280);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.white,
          elevation: 3,
          shadowColor: Colors.black.withValues(alpha: 0.12),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: SizedBox(
              width: 58,
              height: 58,
              child: Icon(icon, color: iconColor, size: 26),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
            color: labelColor,
          ),
        ),
      ],
    );
  }
}
