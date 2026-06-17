import 'package:socket_io_client/socket_io_client.dart' as io;
import 'api_service.dart';

class RealtimeCallService {
  RealtimeCallService._();
  static final RealtimeCallService instance = RealtimeCallService._();

  io.Socket? _socket;
  String? _joinedConversationId;

  String get _baseUrl => ApiService.baseUrl;

  void connect() {
    if (_socket != null) return;
    final socket = io.io(
      _baseUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .enableReconnection()
          .build(),
    );
    socket.connect();
    _socket = socket;
  }

  void disconnect() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _joinedConversationId = null;
  }

  void joinConversation(String conversationId) {
    if (conversationId.isEmpty) return;
    connect();
    if (_joinedConversationId == conversationId) return;
    if (_joinedConversationId != null) {
      _socket?.emit('call:leave-room', {'conversationId': _joinedConversationId});
    }
    _joinedConversationId = conversationId;
    _socket?.emit('call:join-room', {'conversationId': conversationId});
  }

  void emitRing({
    required String conversationId,
    required String fromType,
    required String fromName,
  }) {
    _socket?.emit('call:ring', {
      'conversationId': conversationId,
      'fromType': fromType,
      'fromName': fromName,
      'ts': DateTime.now().toIso8601String(),
    });
  }

  void emitAccept({required String conversationId}) {
    _socket?.emit('call:accept', {
      'conversationId': conversationId,
      'ts': DateTime.now().toIso8601String(),
    });
  }

  void emitReject({required String conversationId}) {
    _socket?.emit('call:reject', {
      'conversationId': conversationId,
      'ts': DateTime.now().toIso8601String(),
    });
  }

  void emitEnd({required String conversationId}) {
    _socket?.emit('call:end', {
      'conversationId': conversationId,
      'ts': DateTime.now().toIso8601String(),
    });
  }

  void onRing(void Function(Map<String, dynamic>) handler) {
    _socket?.off('call:ring');
    _socket?.on('call:ring', (data) {
      if (data is Map) handler(Map<String, dynamic>.from(data));
    });
  }

  void onAccept(void Function(Map<String, dynamic>) handler) {
    _socket?.off('call:accept');
    _socket?.on('call:accept', (data) {
      if (data is Map) handler(Map<String, dynamic>.from(data));
    });
  }

  void onReject(void Function(Map<String, dynamic>) handler) {
    _socket?.off('call:reject');
    _socket?.on('call:reject', (data) {
      if (data is Map) handler(Map<String, dynamic>.from(data));
    });
  }

  void onEnd(void Function(Map<String, dynamic>) handler) {
    _socket?.off('call:end');
    _socket?.on('call:end', (data) {
      if (data is Map) handler(Map<String, dynamic>.from(data));
    });
  }

  void emitOffer({
    required String conversationId,
    required Map<String, dynamic> sdp,
  }) {
    _socket?.emit('webrtc:offer', {
      'conversationId': conversationId,
      'sdp': sdp,
      'ts': DateTime.now().toIso8601String(),
    });
  }

  void emitAnswer({
    required String conversationId,
    required Map<String, dynamic> sdp,
  }) {
    _socket?.emit('webrtc:answer', {
      'conversationId': conversationId,
      'sdp': sdp,
      'ts': DateTime.now().toIso8601String(),
    });
  }

  void emitIceCandidate({
    required String conversationId,
    required Map<String, dynamic> candidate,
  }) {
    _socket?.emit('webrtc:ice-candidate', {
      'conversationId': conversationId,
      'candidate': candidate,
      'ts': DateTime.now().toIso8601String(),
    });
  }

  void onOffer(void Function(Map<String, dynamic>) handler) {
    _socket?.off('webrtc:offer');
    _socket?.on('webrtc:offer', (data) {
      if (data is Map) handler(Map<String, dynamic>.from(data));
    });
  }

  void onAnswer(void Function(Map<String, dynamic>) handler) {
    _socket?.off('webrtc:answer');
    _socket?.on('webrtc:answer', (data) {
      if (data is Map) handler(Map<String, dynamic>.from(data));
    });
  }

  void onIceCandidate(void Function(Map<String, dynamic>) handler) {
    _socket?.off('webrtc:ice-candidate');
    _socket?.on('webrtc:ice-candidate', (data) {
      if (data is Map) handler(Map<String, dynamic>.from(data));
    });
  }
}
