import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../services/webrtc_service.dart';

enum CallState {
  idle,
  enCours,
  sonnerie,
  enAppel,
  termine,
  refuse,
  echec,
}

class CallProvider extends ChangeNotifier {
  CallProvider({
    WebRtcService? webRtcService,
  }) : _webrtc = webRtcService ?? WebRtcService.instance {
    _webrtcSubs.add(_webrtc.callRejected.listen((_) {
      _setState(CallState.refuse);
      _stopTimer();
    }));
    _webrtcSubs.add(_webrtc.callEnded.listen((_) {
      _setState(CallState.termine);
      _stopTimer();
    }));
    _webrtcSubs.add(_webrtc.connectionStates.listen((s) {
      connectionState = s;
      debugPrint('[CALL][medecin] RTCPeerConnectionState=$s');
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        hadConnected = true;
        _setState(CallState.enAppel);
        _startTimer();
      } else if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          s == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        _setState(CallState.echec);
      }
    }));
  }

  final WebRtcService _webrtc;
  final List<StreamSubscription<void>> _webrtcSubs = [];
  Timer? _timer;

  CallState currentState = CallState.idle;
  String? remoteUserId;
  String? roomId;
  bool isMuted = false;
  Duration callDuration = Duration.zero;
  bool isCaller = false;
  bool isVideoCall = false;
  /// Au moins un état WebRTC « connecté » atteint pendant l’appel.
  bool hadConnected = false;
  bool speakerOn = false;
  bool cameraOn = false;
  RTCPeerConnectionState connectionState = RTCPeerConnectionState.RTCPeerConnectionStateNew;

  void _setState(CallState next) {
    currentState = next;
    notifyListeners();
  }

  void _startTimer() {
    _timer?.cancel();
    callDuration = Duration.zero;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      callDuration += const Duration(seconds: 1);
      notifyListeners();
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> startOutgoingCall({
    required String targetUserId,
    required String callRoomId,
    bool isVideo = false,
  }) async {
    remoteUserId = targetUserId;
    roomId = callRoomId;
    isCaller = true;
    isVideoCall = isVideo;
    cameraOn = isVideo;
    _setState(CallState.enCours);
    try {
      await _webrtc.createPeerConnection(
        roomId: callRoomId,
        isCaller: true,
        targetUserId: targetUserId,
        enableVideo: isVideo,
      );
    } catch (_) {
      _setState(CallState.echec);
    }
  }

  Future<bool> acceptIncomingCall({
    required String fromUserId,
    required String callRoomId,
    required Map<String, dynamic> offer,
    bool isVideo = false,
  }) async {
    hadConnected = false;
    remoteUserId = fromUserId;
    roomId = callRoomId;
    isCaller = false;
    isVideoCall = isVideo;
    cameraOn = isVideo;
    _setState(CallState.enCours);
    try {
      await _webrtc.createPeerConnection(
        roomId: callRoomId,
        isCaller: false,
        targetUserId: fromUserId,
        enableVideo: isVideo,
      );
      await _webrtc.setRemoteDescription(offer);
      await _webrtc.createAnswer(offer);
      return true;
    } catch (e, st) {
      debugPrint('[CALL][medecin] acceptIncomingCall error: $e');
      debugPrint('$st');
      _setState(CallState.echec);
      return false;
    }
  }

  Future<void> endCall() async {
    await _webrtc.endCall();
    _stopTimer();
    _setState(CallState.termine);
  }

  void resetAfterCallUi() {
    _stopTimer();
    hadConnected = false;
    remoteUserId = null;
    roomId = null;
    callDuration = Duration.zero;
    isCaller = false;
    isVideoCall = false;
    cameraOn = false;
    isMuted = false;
    speakerOn = false;
    connectionState = RTCPeerConnectionState.RTCPeerConnectionStateNew;
    _setState(CallState.idle);
  }

  void rejectIncomingCall(String fromUserId) {
    _webrtc.rejectCall(toUserId: fromUserId, roomId: roomId);
    _setState(CallState.refuse);
  }

  Future<void> toggleSpeaker() async {
    speakerOn = !speakerOn;
    await _webrtc.setSpeakerphone(speakerOn);
    notifyListeners();
  }

  void toggleMute() {
    isMuted = _webrtc.toggleMute();
    notifyListeners();
  }

  void toggleCamera() {
    cameraOn = _webrtc.toggleCameraEnabled();
    notifyListeners();
  }

  String formattedDuration() {
    final mm = callDuration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = callDuration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  @override
  void dispose() {
    for (final s in _webrtcSubs) {
      s.cancel();
    }
    _webrtcSubs.clear();
    _stopTimer();
    super.dispose();
  }
}
