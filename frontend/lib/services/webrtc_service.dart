import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import 'api_service.dart';
import 'pending_call_intent.dart';

class WebRtcService {
  WebRtcService._();
  static final WebRtcService instance = WebRtcService._();

  io.Socket? _socket;
  rtc.RTCPeerConnection? _peerConnection;
  rtc.MediaStream? _localStream;
  final rtc.RTCVideoRenderer _localRenderer = rtc.RTCVideoRenderer();
  final rtc.RTCVideoRenderer _remoteRenderer = rtc.RTCVideoRenderer();
  bool _remoteRendererReady = false;
  bool _localRendererReady = false;
  bool _isVideoCall = false;
  List<Map<String, dynamic>> _iceServersCache = [];
  final List<Map<String, dynamic>> _pendingIce = <Map<String, dynamic>>[];
  Map<String, dynamic>? _pendingRemoteDescription;
  bool _hasRemoteDescription = false;

  String? _selfUserId;
  String? _targetUserId;
  String? _roomId;

  final StreamController<Map<String, dynamic>> _incomingCtrl =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _rejectCtrl =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _endCtrl =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<rtc.RTCPeerConnectionState> _connStateCtrl =
      StreamController<rtc.RTCPeerConnectionState>.broadcast();
  final StreamController<Map<String, dynamic>> _consultationPatientWaitingCtrl =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _consultationPatientLeftCtrl =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<bool> _socketConnectedCtrl =
      StreamController<bool>.broadcast();
  final StreamController<Map<String, dynamic>> _consultationEventCtrl =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _callSummaryCtrl =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<String> _chatActivityConvIdCtrl =
      StreamController<String>.broadcast();
  final StreamController<Map<String, dynamic>> _teleconsultRequestDecisionCtrl =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _teleconsultFormDecisionCtrl =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _patientRdvNotificationCtrl =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _patientDoctorRepliedFormCtrl =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _patientChatSessionClosedCtrl =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _chatSessionClosedCtrl =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _chatSessionReopenedCtrl =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _patientChatSessionReopenedCtrl =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _chatTypingCtrl =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _chatMessagesReadCtrl =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _patientInboxNewMessageCtrl =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _doctorStatusUpdatedCtrl =
      StreamController<Map<String, dynamic>>.broadcast();

  String? _joinedConversationId;

  Stream<Map<String, dynamic>> get incomingCalls => _incomingCtrl.stream;
  Stream<Map<String, dynamic>> get callRejected => _rejectCtrl.stream;
  Stream<Map<String, dynamic>> get callEnded => _endCtrl.stream;
  Stream<rtc.RTCPeerConnectionState> get connectionStates => _connStateCtrl.stream;
  /// Médecin : patient entré en salle d’attente.
  Stream<Map<String, dynamic>> get consultationPatientWaiting =>
      _consultationPatientWaitingCtrl.stream;
  Stream<Map<String, dynamic>> get consultationPatientLeftWaiting =>
      _consultationPatientLeftCtrl.stream;
  Stream<bool> get socketConnected => _socketConnectedCtrl.stream;
  /// Événements téléconsult : `scheduled`, `updated`, `cancelled` (clé `event`).
  Stream<Map<String, dynamic>> get consultationEvents => _consultationEventCtrl.stream;
  /// Message d’appel enregistré côté serveur (`chat:call_summary`).
  Stream<Map<String, dynamic>> get callSummaryEvents => _callSummaryCtrl.stream;
  /// `conversationId` quand un message est posté ou une décision demande est prise (rafraîchir le chat).
  Stream<String> get chatActivityConversationIds => _chatActivityConvIdCtrl.stream;
  /// Décision médecin sur une demande de téléconsultation (notification type « push » in-app).
  Stream<Map<String, dynamic>> get teleconsultRequestDecisions =>
      _teleconsultRequestDecisionCtrl.stream;
  Stream<Map<String, dynamic>> get teleconsultFormDecisions =>
      _teleconsultFormDecisionCtrl.stream;
  Stream<Map<String, dynamic>> get patientRdvNotifications =>
      _patientRdvNotificationCtrl.stream;
  Stream<Map<String, dynamic>> get patientDoctorRepliedFormEvents =>
      _patientDoctorRepliedFormCtrl.stream;
  Stream<Map<String, dynamic>> get patientChatSessionClosedEvents =>
      _patientChatSessionClosedCtrl.stream;
  Stream<Map<String, dynamic>> get chatSessionClosedEvents =>
      _chatSessionClosedCtrl.stream;
  Stream<Map<String, dynamic>> get chatSessionReopenedEvents =>
      _chatSessionReopenedCtrl.stream;
  Stream<Map<String, dynamic>> get patientChatSessionReopenedEvents =>
      _patientChatSessionReopenedCtrl.stream;
  Stream<Map<String, dynamic>> get chatTypingEvents => _chatTypingCtrl.stream;
  Stream<Map<String, dynamic>> get chatMessagesReadEvents =>
      _chatMessagesReadCtrl.stream;
  Stream<Map<String, dynamic>> get patientInboxNewMessageEvents =>
      _patientInboxNewMessageCtrl.stream;
  Stream<Map<String, dynamic>> get doctorStatusUpdatedEvents =>
      _doctorStatusUpdatedCtrl.stream;

  bool _socketConnected = false;
  bool get isSocketConnected => _socketConnected;
  /// Conversation `conv:` actuellement suivie (patient dans le chat).
  String? get joinedConversationId => _joinedConversationId;

  rtc.RTCVideoRenderer get localRenderer => _localRenderer;
  rtc.RTCVideoRenderer get remoteRenderer => _remoteRenderer;
  bool get isRemoteRendererReady => _remoteRendererReady;
  bool get isLocalRendererReady => _localRendererReady;
  bool get isVideoCall => _isVideoCall;

  String get _baseUrl => ApiService.baseUrl;
  static const String _turnUrl = String.fromEnvironment('TURN_URL', defaultValue: '');
  static const String _turnUsername = String.fromEnvironment('TURN_USERNAME', defaultValue: '');
  static const String _turnCredential = String.fromEnvironment('TURN_CREDENTIAL', defaultValue: '');

  List<Map<String, dynamic>> _buildIceServers() {
    final servers = <Map<String, dynamic>>[
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ];
    if (_turnUrl.isNotEmpty && _turnUsername.isNotEmpty && _turnCredential.isNotEmpty) {
      servers.add({
        'urls': _turnUrl,
        'username': _turnUsername,
        'credential': _turnCredential,
      });
      debugPrint('[WEBRTC][frontend] TURN enabled: $_turnUrl');
    }
    return servers;
  }

  Future<List<Map<String, dynamic>>> _resolveIceServers() async {
    if (_iceServersCache.isNotEmpty) return _iceServersCache;
    final uid = (_selfUserId ?? '').toString().trim();
    if (uid.isNotEmpty) {
      try {
        final uri = Uri.parse(
          '${ApiService.baseUrl}/webrtc/ice-config?userId=${Uri.encodeComponent(uid)}',
        );
        final response = await http.get(uri, headers: {
          if ((ApiService.jwtToken ?? '').isNotEmpty)
            'Authorization': 'Bearer ${ApiService.jwtToken}',
        });
        final data = jsonDecode(response.body);
        if (response.statusCode >= 200 && response.statusCode < 300) {
          final list = (data as Map<String, dynamic>)['iceServers'];
          if (list is List) {
            _iceServersCache = List<Map<String, dynamic>>.from(
              list.map((e) => Map<String, dynamic>.from(e as Map)),
            );
            if (_iceServersCache.isNotEmpty) return _iceServersCache;
          }
        }
      } catch (_) {}
    }
    _iceServersCache = _buildIceServers();
    return _iceServersCache;
  }

  /// À appeler depuis l’UI patient (premier plan / arrière-plan) pour ne pas envoyer de FCM inutile.
  void emitPatientAppLifecycle(bool inForeground) {
    _emitWhenConnected('patient:app_lifecycle', {'inForeground': inForeground});
  }

  String? _pendingRequestOfferRoomId;
  int _pendingRequestOfferAttempt = 0;
  String? _debouncePendingOfferRoom;
  DateTime? _debouncePendingOfferAt;

  /// Redemande l’offre SDP au serveur (ex. tap « Répondre » sur la notification).
  /// Délai après connexion pour que `auth:bind` soit traité avant `call:request_pending_offer`.
  void requestPendingOffer(String roomId) {
    final r = roomId.trim();
    if (r.isEmpty) return;
    final now = DateTime.now();
    if (_debouncePendingOfferRoom == r &&
        _debouncePendingOfferAt != null &&
        now.difference(_debouncePendingOfferAt!) < const Duration(milliseconds: 350)) {
      return;
    }
    _debouncePendingOfferRoom = r;
    _debouncePendingOfferAt = now;
    _pendingRequestOfferRoomId = r;
    _pendingRequestOfferAttempt = 0;
    _scheduleEmitPendingOfferRequest();
  }

  /// Appelée après FCM / retour au premier plan : reconnecte le socket si besoin,
  /// rejoint la conversation, puis redemande l’offre SDP stockée côté serveur.
  Future<void> handleIncomingCallFromNotification(Map<String, String> data) async {
    final roomId = (data['roomId'] ?? '').trim();
    final convId = (data['conversationId'] ?? '').trim();
    if (convId.isNotEmpty) {
      joinConversationRoom(convId);
    }
    if (roomId.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final patientId = (prefs.getString('patientId') ?? '').trim();
    if (patientId.isEmpty) {
      debugPrint('[WEBRTC][frontend] handleIncomingCallFromNotification: pas de patientId');
      return;
    }

    ensureSocketConnected(selfUserId: patientId, jwtToken: ApiService.jwtToken);
    requestPendingOffer(roomId);
  }

  /// Garantit une session Socket.IO utilisable (reconnexion si l’instance existe mais est coupée).
  void ensureSocketConnected({required String selfUserId, String? jwtToken}) {
    connectSocket(selfUserId: selfUserId, jwtToken: jwtToken);
  }

  void _scheduleEmitPendingOfferRequest() {
    final s = _socket;
    final rid = _pendingRequestOfferRoomId;
    if (rid == null || rid.isEmpty) return;
    if (s == null) return;
    void emitDelayed() {
      Future<void>.delayed(const Duration(milliseconds: 650), () {
        if (_pendingRequestOfferRoomId != rid) return;
        final s2 = _socket;
        if (s2 == null || !s2.connected) return;
        s2.emit('call:request_pending_offer', {'roomId': rid});
        _pendingRequestOfferAttempt++;
        debugPrint('[WEBRTC][frontend] call:request_pending_offer roomId=$rid');
        if (_pendingRequestOfferRoomId != rid) return;
        if (_pendingRequestOfferAttempt < 4) {
          Future<void>.delayed(const Duration(milliseconds: 900), () {
            if (_pendingRequestOfferRoomId == rid) {
              _scheduleEmitPendingOfferRequest();
            }
          });
        } else {
          _pendingRequestOfferRoomId = null;
          _pendingRequestOfferAttempt = 0;
        }
      });
    }

    if (s.connected) {
      emitDelayed();
    } else {
      s.once('connect', (_) => emitDelayed());
    }
  }

  Future<void> _flushPendingRejectFromPrefs() async {
    try {
      final p = await SharedPreferences.getInstance();
      final room = p.getString('pending_socket_reject_room');
      final to = p.getString('pending_socket_reject_to');
      if (room == null || to == null || room.isEmpty || to.isEmpty) return;
      await p.remove('pending_socket_reject_room');
      await p.remove('pending_socket_reject_to');
      rejectCall(toUserId: to, roomId: room);
    } catch (_) {}
  }

  /// Après connexion / reconnexion : si un intent FCM a été persisté, redemander l’offre.
  Future<void> _retryPendingCallIntentAfterConnect() async {
    try {
      await PendingCallIntent.loadFromPrefs();
      final room = PendingCallIntent.roomId?.trim() ?? '';
      if (room.isEmpty || !PendingCallIntent.wantsAnswer) return;
      requestPendingOffer(room);
    } catch (_) {}
  }

  void _emitWhenConnected(String event, Map<String, dynamic> payload) {
    final s = _socket;
    if (s == null) return;
    if (s.connected) {
      s.emit(event, payload);
      return;
    }
    s.once('connect', (_) {
      s.emit(event, payload);
    });
  }

  /// Le serveur envoie `from` (socket id) et `fromUserId` — pour `call:ice` / `to:` il faut l’user id.
  void _setPeerUserIdFromPayload(Map<String, dynamic> payload) {
    final uid = payload['fromUserId']?.toString().trim();
    if (uid != null && uid.isNotEmpty) {
      _targetUserId = uid;
      return;
    }
    final sid = payload['from']?.toString().trim();
    if (sid != null && sid.isNotEmpty) {
      _targetUserId = sid;
    }
  }

  void connectSocket({
    required String selfUserId,
    String? jwtToken,
  }) {
    _selfUserId = selfUserId;
    if (_socket != null) {
      final s = _socket!;
      if (!s.connected) {
        try {
          s.connect();
        } catch (e) {
          debugPrint('[WEBRTC][frontend] socket.connect() erreur: $e');
        }
      }
      void bindAfterAuth() {
        s.emit('auth:bind', {'userId': selfUserId});
        final cid = _joinedConversationId;
        if (cid != null && cid.isNotEmpty) {
          s.emit('call:join-room', {'conversationId': cid});
        }
      }

      if (s.connected) {
        bindAfterAuth();
      } else {
        s.once('connect', (_) => bindAfterAuth());
      }
      return;
    }

    final socket = io.io(
      _baseUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .setAuth(<String, dynamic>{
            'token': jwtToken ?? '',
            'userId': selfUserId,
          })
          .enableReconnection()
          .build(),
    );

    void onSocketReady() {
      socket.emit('auth:bind', {'userId': selfUserId});
      final cid = _joinedConversationId;
      if (cid != null && cid.isNotEmpty) {
        socket.emit('call:join-room', {'conversationId': cid});
      }
      _socketConnected = true;
      _socketConnectedCtrl.add(true);
      debugPrint('[WEBRTC][frontend] connected socket=${socket.id} userId=$selfUserId');
      unawaited(_flushPendingRejectFromPrefs());
      unawaited(_retryPendingCallIntentAfterConnect());
    }

    socket.onConnect((_) async {
      onSocketReady();
    });
    socket.on('reconnect', (_) {
      debugPrint('[WEBRTC][frontend] socket reconnect userId=$selfUserId');
      onSocketReady();
      final rid = PendingCallIntent.roomId?.trim() ?? '';
      if (rid.isNotEmpty && (PendingCallIntent.wantsAnswer)) {
        requestPendingOffer(rid);
      } else if (_pendingRequestOfferRoomId != null &&
          _pendingRequestOfferRoomId!.isNotEmpty) {
        requestPendingOffer(_pendingRequestOfferRoomId!);
      }
    });
    socket.on('consultation:patient_waiting', (data) {
      if (data is Map) {
        _consultationPatientWaitingCtrl.add(Map<String, dynamic>.from(data));
      }
    });
    socket.on('consultation:patient_left_waiting', (data) {
      if (data is Map) {
        _consultationPatientLeftCtrl.add(Map<String, dynamic>.from(data));
      }
    });
    void forwardConsult(dynamic data, String event) {
      if (data is Map) {
        final m = Map<String, dynamic>.from(data);
        m['event'] = event;
        _consultationEventCtrl.add(m);
      }
    }

    socket.on('consultation:scheduled', (data) => forwardConsult(data, 'scheduled'));
    socket.on('consultation:updated', (data) => forwardConsult(data, 'updated'));
    socket.on('consultation:cancelled', (data) => forwardConsult(data, 'cancelled'));
    socket.on('chat:call_summary', (data) {
      if (data is Map) {
        _callSummaryCtrl.add(Map<String, dynamic>.from(data));
      }
    });
    socket.on('chat:new_activity', (data) {
      if (data is Map) {
        final cid = data['conversationId']?.toString() ?? '';
        if (cid.isNotEmpty) {
          _chatActivityConvIdCtrl.add(cid);
        }
      }
    });
    socket.on('patient:teleconsult_request_decision', (data) {
      if (data is Map) {
        _teleconsultRequestDecisionCtrl.add(Map<String, dynamic>.from(data));
      }
    });
    socket.on('patient:teleconsult_form_decision', (data) {
      if (data is Map) {
        _teleconsultFormDecisionCtrl.add(Map<String, dynamic>.from(data));
      }
    });
    socket.on('patient:rdv_notification', (data) {
      if (data is Map) {
        _patientRdvNotificationCtrl.add(Map<String, dynamic>.from(data));
      }
    });
    socket.on('patient:doctor_replied_form', (data) {
      if (data is Map) {
        _patientDoctorRepliedFormCtrl.add(Map<String, dynamic>.from(data));
      }
    });
    socket.on('patient:chat_session_closed', (data) {
      if (data is Map) {
        _patientChatSessionClosedCtrl.add(Map<String, dynamic>.from(data));
      }
    });
    socket.on('chat:session_closed', (data) {
      if (data is Map) {
        _chatSessionClosedCtrl.add(Map<String, dynamic>.from(data));
      }
    });
    socket.on('chat:session_reopened', (data) {
      if (data is Map) {
        _chatSessionReopenedCtrl.add(Map<String, dynamic>.from(data));
      }
    });
    socket.on('patient:chat_session_reopened', (data) {
      if (data is Map) {
        _patientChatSessionReopenedCtrl.add(Map<String, dynamic>.from(data));
      }
    });
    socket.on('chat:typing', (data) {
      if (data is Map) {
        _chatTypingCtrl.add(Map<String, dynamic>.from(data));
      }
    });
    socket.on('chat:messages_read', (data) {
      if (data is Map) {
        _chatMessagesReadCtrl.add(Map<String, dynamic>.from(data));
      }
    });
    socket.on('patient:inbox_new_message', (data) {
      if (data is Map) {
        _patientInboxNewMessageCtrl.add(Map<String, dynamic>.from(data));
      }
    });
    socket.on('doctor:status_updated', (data) {
      if (data is Map) {
        _doctorStatusUpdatedCtrl.add(Map<String, dynamic>.from(data));
      }
    });
    socket.on('auth:error', (data) {
      debugPrint('[WEBRTC][frontend] auth:error $data — vérifier patient_jwt / auth:bind');
    });
    socket.on('call:incoming', (data) {
      debugPrint('[WEBRTC][frontend] call:incoming ${data.runtimeType}');
      if (data is Map) {
        final payload = Map<String, dynamic>.from(data);
        final rid = payload['roomId']?.toString() ?? '';
        if (rid.isNotEmpty && _pendingRequestOfferRoomId == rid) {
          _pendingRequestOfferRoomId = null;
          _pendingRequestOfferAttempt = 0;
        }
        _incomingCtrl.add(payload);
      }
    });
    socket.on('call:offer', (_) {
      // L'offre est traitée via call:incoming + écran d'acceptation explicite.
    });
    socket.on('call:answer', (data) async {
      if (data is! Map) return;
      final payload = Map<String, dynamic>.from(data);
      _setPeerUserIdFromPayload(payload);
      final from = payload['from']?.toString();
      debugPrint('[WEBRTC][frontend] call:answer roomId=${payload['roomId']} from=$from');
      final sdp = Map<String, dynamic>.from((payload['sdp'] as Map?) ?? {});
      await setRemoteDescription(sdp);
    });
    socket.on('call:ice', (data) async {
      if (data is! Map) return;
      final payload = Map<String, dynamic>.from(data);
      _setPeerUserIdFromPayload(payload);
      final from = payload['from']?.toString();
      debugPrint('[WEBRTC][frontend] call:ice roomId=${payload['roomId']} from=$from');
      final candidate = Map<String, dynamic>.from((payload['candidate'] as Map?) ?? {});
      await addIceCandidate(candidate);
    });
    socket.on('call:end', (data) async {
      if (data is Map) _endCtrl.add(Map<String, dynamic>.from(data));
      await endCall(notifyRemote: false);
    });
    socket.on('call:reject', (data) async {
      if (data is Map) _rejectCtrl.add(Map<String, dynamic>.from(data));
      await endCall(notifyRemote: false);
    });
    socket.onDisconnect((_) async {
      _socketConnected = false;
      _socketConnectedCtrl.add(false);
      await endCall(notifyRemote: false);
    });

    socket.connect();
    _socket = socket;
  }

  Future<void> initializeLocalStream({required bool enableVideo}) async {
    if (_localStream != null && _isVideoCall == enableVideo) return;
    if (_localStream != null) {
      for (final t in _localStream!.getTracks()) {
        await t.stop();
      }
      await _localStream!.dispose();
      _localStream = null;
    }
    _isVideoCall = enableVideo;
    try {
      _localStream = await rtc.navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': enableVideo,
      });
    } catch (e) {
      // Cas fréquent Web: caméra/micro déjà occupés dans un autre onglet.
      if (enableVideo) {
        if (kDebugMode) {
          debugPrint(
            '[WEBRTC][frontend] caméra indisponible, appel audio seul',
          );
        }
        _isVideoCall = false;
        _localStream = await rtc.navigator.mediaDevices.getUserMedia({
          'audio': true,
          'video': false,
        });
      } else {
        rethrow;
      }
    }
    if (enableVideo && _localRendererReady) {
      _localRenderer.srcObject = _localStream;
    }
    if (!_remoteRendererReady) {
      await _remoteRenderer.initialize();
      _remoteRendererReady = true;
    }
    if (!_localRendererReady) {
      await _localRenderer.initialize();
      _localRendererReady = true;
    }
    if (enableVideo) {
      _localRenderer.srcObject = _localStream;
    } else {
      _localRenderer.srcObject = null;
    }
  }

  Future<void> createPeerConnection({
    required String roomId,
    required bool isCaller,
    required String targetUserId,
    bool enableVideo = false,
  }) async {
    _roomId = roomId;
    _targetUserId = targetUserId;
    _hasRemoteDescription = false;
    await initializeLocalStream(enableVideo: enableVideo);

    _peerConnection = await rtc.createPeerConnection({
      'iceServers': await _resolveIceServers(),
      'sdpSemantics': 'unified-plan',
    });

    for (final track in _localStream!.getTracks()) {
      await _peerConnection!.addTrack(track, _localStream!);
    }

    _peerConnection!.onIceCandidate = (rtc.RTCIceCandidate candidate) {
      final to = _targetUserId;
      if (to == null || to.isEmpty) return;
      _emitWhenConnected('call:ice', {
        'to': to,
        'roomId': _roomId,
        'candidate': {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        },
      });
    };
    _peerConnection!.onConnectionState = (state) {
      debugPrint('[WEBRTC][frontend] pc.state=$state');
      _connStateCtrl.add(state);
    };
    _peerConnection!.onIceConnectionState = (state) {
      debugPrint('[WEBRTC][frontend] ice.state=$state');
    };
    _peerConnection!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        _remoteRenderer.srcObject = event.streams.first;
        debugPrint('[WEBRTC][frontend] remote track attached');
      }
    };

    if (_pendingRemoteDescription != null) {
      final sdp = _pendingRemoteDescription!;
      _pendingRemoteDescription = null;
      await setRemoteDescription(sdp);
    }

    if (isCaller) {
      await createOffer();
    }
  }

  Future<void> createOffer() async {
    final pc = _peerConnection;
    final to = _targetUserId;
    if (pc == null || to == null || to.isEmpty) return;
    final offer = await pc.createOffer({'offerToReceiveAudio': true, 'offerToReceiveVideo': false});
    await pc.setLocalDescription(offer);
    _emitWhenConnected('call:offer', {
      'to': to,
      'roomId': _roomId,
      'from': _selfUserId,
      'mediaType': _isVideoCall ? 'video' : 'audio',
      'sdp': {'type': offer.type, 'sdp': offer.sdp},
    });
  }

  Future<void> createAnswer(Map<String, dynamic> offer) async {
    final pc = _peerConnection;
    final to = _targetUserId;
    if (pc == null || to == null || to.isEmpty) return;
    final answer = await pc.createAnswer({'offerToReceiveAudio': true, 'offerToReceiveVideo': false});
    await pc.setLocalDescription(answer);
    _emitWhenConnected('call:answer', {
      'to': to,
      'roomId': _roomId,
      'from': _selfUserId,
      'mediaType': _isVideoCall ? 'video' : 'audio',
      'sdp': {'type': answer.type, 'sdp': answer.sdp},
    });
  }

  Future<void> setRemoteDescription(Map<String, dynamic> sdp) async {
    final pc = _peerConnection;
    if (pc == null) {
      _pendingRemoteDescription = Map<String, dynamic>.from(sdp);
      return;
    }
    final type = sdp['type']?.toString() ?? '';
    final value = sdp['sdp']?.toString() ?? '';
    if (type.isEmpty || value.isEmpty) return;
    debugPrint('[WEBRTC][frontend] setRemoteDescription type=$type');
    await pc.setRemoteDescription(rtc.RTCSessionDescription(value, type));
    _hasRemoteDescription = true;
    if (_pendingIce.isNotEmpty) {
      final queued = List<Map<String, dynamic>>.from(_pendingIce);
      _pendingIce.clear();
      for (final c in queued) {
        await addIceCandidate(c);
      }
    }
  }

  Future<void> addIceCandidate(Map<String, dynamic> candidate) async {
    final pc = _peerConnection;
    if (pc == null || !_hasRemoteDescription) {
      _pendingIce.add(candidate);
      return;
    }
    final value = candidate['candidate']?.toString() ?? '';
    if (value.isEmpty) return;
    final lineIndexRaw = candidate['sdpMLineIndex'];
    final lineIndex = lineIndexRaw is int
        ? lineIndexRaw
        : lineIndexRaw is num
            ? lineIndexRaw.toInt()
            : null;
    await pc.addCandidate(
      rtc.RTCIceCandidate(
        value,
        candidate['sdpMid']?.toString(),
        lineIndex,
      ),
    );
  }

  bool toggleMute() {
    final tracks = _localStream?.getAudioTracks() ?? const [];
    if (tracks.isEmpty) return false;
    final nextEnabled = !tracks.first.enabled;
    for (final t in tracks) {
      t.enabled = nextEnabled;
    }
    return !nextEnabled;
  }

  bool toggleVideo() {
    final tracks = _localStream?.getVideoTracks() ?? const [];
    if (tracks.isEmpty) return false;
    final nextEnabled = !tracks.first.enabled;
    for (final t in tracks) {
      t.enabled = nextEnabled;
    }
    return nextEnabled;
  }

  Future<void> setSpeakerphone(bool enabled) async {
    await rtc.Helper.setSpeakerphoneOn(enabled);
  }

  Future<void> endCall({bool notifyRemote = true}) async {
    if (notifyRemote && _targetUserId != null && _targetUserId!.isNotEmpty) {
      _emitWhenConnected('call:end', {
        'to': _targetUserId,
        'roomId': _roomId,
        'from': _selfUserId,
      });
    }
    await _peerConnection?.close();
    _peerConnection = null;
    final local = _localStream;
    if (local != null) {
      for (final t in local.getTracks()) {
        await t.stop();
      }
      await local.dispose();
    }
    _localStream = null;
    _localRenderer.srcObject = null;
    _remoteRenderer.srcObject = null;
    _roomId = null;
    _targetUserId = null;
    _hasRemoteDescription = false;
    _pendingIce.clear();
    _pendingRemoteDescription = null;
    _isVideoCall = false;
  }

  void rejectCall({
    required String toUserId,
    String? roomId,
  }) {
    final payload = <String, dynamic>{
      'to': toUserId,
      'from': _selfUserId,
    };
    final r = roomId ?? _roomId;
    if (r != null && r.isNotEmpty) payload['roomId'] = r;
    _emitWhenConnected('call:reject', payload);
  }

  void notifyPatientEnteredWaitingRoom({
    required String conversationId,
    required String patientId,
    required String doctorId,
    required String patientName,
  }) {
    _emitWhenConnected('patient:entered_waiting_room', {
      'conversationId': conversationId,
      'patientId': patientId,
      'doctorId': doctorId,
      'patientName': patientName,
    });
  }

  void notifyPatientLeftWaitingRoom({
    required String conversationId,
    required String patientId,
    required String doctorId,
  }) {
    _emitWhenConnected('patient:left_waiting_room', {
      'conversationId': conversationId,
      'patientId': patientId,
      'doctorId': doctorId,
    });
  }

  void emitChatTyping({
    required String conversationId,
    required bool typing,
    required String role,
  }) {
    _emitWhenConnected('chat:typing', {
      'conversationId': conversationId,
      'typing': typing,
      'role': role,
    });
  }

  /// Rejoindre la room Socket.IO `conv:` pour recevoir `consultation:*` (patient / médecin).
  /// Passer `null` ou `''` réinitialise l’id (ex. sortie du chat).
  void joinConversationRoom(String? conversationId) {
    final c = conversationId?.trim() ?? '';
    if (c.isEmpty) {
      _joinedConversationId = null;
      return;
    }
    _joinedConversationId = c;
    final s = _socket;
    if (s == null) return;
    if (s.connected) {
      s.emit('call:join-room', {'conversationId': c});
      return;
    }
    s.once('connect', (_) {
      s.emit('call:join-room', {'conversationId': c});
    });
  }
}
