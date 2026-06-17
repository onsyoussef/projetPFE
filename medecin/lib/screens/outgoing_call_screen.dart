import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../providers/call_provider.dart';
import '../services/call_chat_context.dart';
import '../services/webrtc_service.dart';
import 'active_call_screen.dart';

class OutgoingCallScreen extends StatefulWidget {
  const OutgoingCallScreen({
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
  State<OutgoingCallScreen> createState() => _OutgoingCallScreenState();
}

class _OutgoingCallScreenState extends State<OutgoingCallScreen> {
  Timer? _dotsTimer;
  Timer? _missTimer;
  int _dots = 0;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    widget.callProvider.addListener(_onStateChangedSync);
    _dotsTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      setState(() => _dots = (_dots + 1) % 4);
    });
    _missTimer = Timer(const Duration(seconds: 30), _onMissedTimeout);
  }

  Future<void> _onMissedTimeout() async {
    if (_finished || !mounted) return;
    final p = widget.callProvider;
    if (p.currentState == CallState.enAppel || p.hadConnected) return;
    _finished = true;
    _missTimer?.cancel();
    final navigator = Navigator.of(context);
    await p.endCall();
    await CallChatContext.sendCallMissed(isVideo: widget.isVideoCall);
    if (!navigator.mounted) return;
    CallChatContext.popCallStackWithNavigator(navigator);
    p.resetAfterCallUi();
  }

  @override
  void dispose() {
    _missTimer?.cancel();
    _dotsTimer?.cancel();
    widget.callProvider.removeListener(_onStateChangedSync);
    super.dispose();
  }

  void _markFinished() {
    if (_finished) return;
    _finished = true;
    _missTimer?.cancel();
  }

  void _onStateChangedSync() {
    unawaited(_onStateChangedAsync());
  }

  Future<void> _onStateChangedAsync() async {
    if (!mounted || _finished) return;
    final state = widget.callProvider.currentState;
    final p = widget.callProvider;

    if (state == CallState.enAppel) {
      _missTimer?.cancel();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => ActiveCallScreen(
            callProvider: p,
            displayName: widget.displayName,
            avatarUrl: widget.avatarUrl,
            isVideoCall: widget.isVideoCall,
          ),
        ),
      );
      return;
    }

    if (state == CallState.refuse) {
      _markFinished();
      final navigator = Navigator.of(context);
      await CallChatContext.onReloadMessages?.call();
      if (!navigator.mounted) return;
      CallChatContext.popCallStackWithNavigator(navigator);
      p.resetAfterCallUi();
      return;
    }

    if (state == CallState.termine || state == CallState.echec) {
      _markFinished();
      final navigator = Navigator.of(context);
      if (!navigator.mounted) return;
      CallChatContext.popCallStackWithNavigator(navigator);
      p.resetAfterCallUi();
    }
  }

  @override
  Widget build(BuildContext context) {
    final dots = '.' * _dots;
    final title = widget.isVideoCall
        ? 'Appel vidéo sortant'
        : 'Appel audio sortant';
    final statusLine = widget.isVideoCall
        ? 'Appel vidéo en cours$dots'
        : 'Appel audio en cours$dots';
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
                  radius: 44,
                  backgroundImage:
                      widget.avatarUrl != null && widget.avatarUrl!.isNotEmpty
                          ? NetworkImage(widget.avatarUrl!)
                          : null,
                  child: widget.avatarUrl == null || widget.avatarUrl!.isEmpty
                      ? const Icon(Icons.person_rounded, size: 40)
                      : null,
                ),
                const SizedBox(height: 12),
                Text(
                  widget.displayName,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(statusLine),
                const SizedBox(height: 30),
                FloatingActionButton(
                  backgroundColor: Colors.red,
                  onPressed: () async {
                    _markFinished();
                    final navigator = Navigator.of(context);
                    await widget.callProvider.endCall();
                    final p = widget.callProvider;
                    if (!navigator.mounted) return;
                    CallChatContext.popCallStackWithNavigator(navigator);
                    p.resetAfterCallUi();
                  },
                  child: const Icon(Icons.call_end_rounded),
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
