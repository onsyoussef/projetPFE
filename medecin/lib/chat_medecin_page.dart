import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'headsapp_theme.dart';
import 'providers/call_provider.dart' show CallProvider, CallState;
import 'screens/doctor_prescription_pdf_viewer_screen.dart';
import 'prescription_history/doctor_prescription_history_bottom_sheet.dart';
import 'prescription_history/prescription_history_strings.dart';
import 'screens/incoming_call_screen.dart';
import 'screens/outgoing_call_screen.dart';
import 'services/api_service.dart';
import 'services/call_chat_context.dart';
import 'services/permission_service.dart';
import 'services/webrtc_service.dart';
import 'session_keys.dart';
import 'teleconsult_first_request_letter.dart';
import 'utils/chat_attachment_open.dart';
import 'utils/doctor_ui_utils.dart';
import 'widgets/call_log_bubble.dart';
import 'widgets/chat_session_status_chip.dart';
import 'widgets/doctor_chat_ui.dart';
import 'widgets/prescription_form_sheet.dart';

/// Niveau visuel médecin : `urgency` serveur ou repli sur `importance` (très important / important / normal).
String doctorTextUrgencyFromPayload(Map<String, dynamic> payload) {
  final u = (payload['urgency']?.toString() ?? '').trim();
  if (u == 'urgent' || u == 'medium' || u == 'normal') return u;
  switch (payload['importance']?.toString()) {
    case 'very_important':
      return 'urgent';
    case 'important':
      return 'medium';
    case 'normal':
      return 'normal';
    default:
      return 'normal';
  }
}

String _doctorBubbleDisplayName(String fullName) {
  final trimmed = fullName.trim();
  if (trimmed.isEmpty) return 'Dr. —';
  final lower = trimmed.toLowerCase();
  if (lower.startsWith('dr.') || lower.startsWith('dr ')) return trimmed;
  return 'Dr. $trimmed';
}

/// Chat médecin ↔ patient : texte (importance à l’envoi), pièces jointes, vocal,
/// affichage des messages métier (formulaire, créneau, appels). Pas d’actions
/// « téléconsultation » / « répondre par message » / clôture ici.
class ChatMedecinPage extends StatefulWidget {
  const ChatMedecinPage({
    super.key,
    required this.conversationId,
    required this.patientId,
    required this.patientName,
    required this.doctorId,
    this.patientPhotoPath,
    this.autoStartAudioCall = false,
  });

  final String conversationId;
  final String patientId;
  final String patientName;
  final String doctorId;
  final String? patientPhotoPath;
  final bool autoStartAudioCall;

  @override
  State<ChatMedecinPage> createState() => _ChatMedecinPageState();
}

class _ChatMedecinPageState extends State<ChatMedecinPage>
    with TickerProviderStateMixin {
  static const Color _skyBlue = HeadsAppColors.brandPrimary;
  static const Color _headerNavy = Color(0xFF1A3D5F);
  static const Color _onlineGreen = Color(0xFF22C55E);

  final List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  String? _error;
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String _messageImportance = 'normal';
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  _MessageUrgency _messageUrgency = _MessageUrgency.normal;
  PlatformFile? _pendingVoiceFile;
  PlatformFile? _pendingAttachmentFile;
  final LayerLink _sendButtonLayerLink = LayerLink();
  final GlobalKey _sendButtonKey = GlobalKey();
  OverlayEntry? _sendImportanceOverlay;
  Timer? _messagePollTimer;
  bool _pollInFlight = false;
  bool _textSendInFlight = false;
  static const Duration _pollInterval = Duration(milliseconds: 700);
  bool _autoCallTriggered = false;
  late final CallProvider _callProvider;
  StreamSubscription<Map<String, dynamic>>? _callSummarySocketSub;
  StreamSubscription<Map<String, dynamic>>? _incomingCallSub;
  StreamSubscription<Map<String, dynamic>>? _patientWaitingSub;
  StreamSubscription<Map<String, dynamic>>? _patientLeftSub;
  Timer? _waitingUiTick;
  Timer? _rdvPollTimer;
  Timer? _rdvBoundaryTick;
  Timer? _patientLeftFadeTimer;
  DateTime? _patientWaitingSince;

  /// Prochain créneau agenda (patient courant) dans la fenêtre « ≤10 min avant ».
  DateTime? _nextRendezVousStart;
  bool _showPatientLeftNotice = false;
  late AnimationController _callIconsPulse;

  bool _sessionClosed = false;
  bool _peerTyping = false;
  Timer? _typingPauseTimer;
  Timer? _typingEmitEndTimer;
  StreamSubscription<Map<String, dynamic>>? _chatSessionClosedSub;
  StreamSubscription<Map<String, dynamic>>? _chatSessionReopenedSub;
  StreamSubscription<Map<String, dynamic>>? _chatTypingSub;
  StreamSubscription<Map<String, dynamic>>? _chatMessagesReadSub;

  String _doctorDisplayName = 'Médecin';

  static const Color _clotureRed = HeadsAppColors.danger;
  static const Color _rouvrirGreen = HeadsAppColors.success;
  static const Color _sessionClosedBannerGreenBg = HeadsAppColors.surfaceSoft;
  static const Color _sessionClosedBannerGreenFg = HeadsAppColors.success;

  static const Color _inputPlusBlue = Color(0xFF3B67A1);
  static const Color _inputSendBlue = Color(0xFF204B9B);
  static const Color _inputHintGrey = Color(0xFF7A8C9F);
  static const Color _inputLockRed = Color(0xFFD65D66);

  bool get _doctorInActiveCall {
    final s = _callProvider.currentState;
    return s == CallState.sonnerie ||
        s == CallState.enCours ||
        s == CallState.enAppel;
  }

  void _onDoctorCallState() {
    if (mounted) {
      _syncCallIconsPulse();
      setState(() {});
    }
  }

  bool _shouldBlinkCallIconsForRendezVous() {
    if (_doctorInActiveCall) return false;
    final start = _nextRendezVousStart;
    if (start == null) return false;
    final now = DateTime.now();
    if (!now.isBefore(start)) return false;
    final windowStart = start.subtract(const Duration(minutes: 10));
    return !now.isBefore(windowStart);
  }

  void _syncCallIconsPulse() {
    if (!mounted) return;
    final blink = _shouldBlinkCallIconsForRendezVous();
    if (blink) {
      if (!_callIconsPulse.isAnimating) {
        _callIconsPulse.repeat();
      }
    } else {
      _callIconsPulse.stop();
      _callIconsPulse.value = 0.0;
    }
  }

  DateTime? _parseAgendaRdvLocal(Map<String, dynamic> e) {
    final iso = e['dateHeure'] ?? e['scheduledAt'];
    if (iso is! String || iso.isEmpty) return null;
    return DateTime.tryParse(iso)?.toLocal();
  }

  Future<void> _refreshNearestRendezVous() async {
    try {
      final rows = await ApiService.getDoctorAgendaRendezVous(
        doctorId: widget.doctorId,
      );
      if (!mounted) return;
      final now = DateTime.now();
      final pid = widget.patientId;
      DateTime? best;
      for (final raw in rows) {
        final e = Map<String, dynamic>.from(raw);
        if ((e['statut'] as String? ?? '') == 'annule') continue;
        if ((e['patientId']?.toString() ?? '') != pid) continue;
        final dt = _parseAgendaRdvLocal(e);
        if (dt == null || !now.isBefore(dt)) continue;
        final windowStart = dt.subtract(const Duration(minutes: 10));
        if (now.isBefore(windowStart)) continue;
        if (best == null || dt.isBefore(best)) best = dt;
      }
      setState(() {
        _nextRendezVousStart = best;
      });
      _syncCallIconsPulse();
    } catch (_) {
      if (mounted) {
        setState(() => _nextRendezVousStart = null);
        _syncCallIconsPulse();
      }
    }
  }

  void _onPatientLeftWaitingUi() {
    _patientLeftFadeTimer?.cancel();
    setState(() {
      _patientWaitingSince = null;
      _showPatientLeftNotice = true;
    });
    _patientLeftFadeTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _showPatientLeftNotice = false);
      }
    });
  }

  String? _patientPhotoUrl() {
    final p = widget.patientPhotoPath;
    if (p == null || p.trim().isEmpty) return null;
    final u = ApiService.resolveMediaUrl(p);
    return u.isEmpty ? null : u;
  }

  Future<void> _startAudioCall() async {
    if (_doctorInActiveCall) return;
    final ok = await PermissionService.instance.ensureMicrophonePermission(
      context,
    );
    if (!ok || !mounted) return;
    final roomId =
        'room_${widget.conversationId}_${DateTime.now().millisecondsSinceEpoch}';
    await _callProvider.startOutgoingCall(
      targetUserId: widget.patientId,
      callRoomId: roomId,
      isVideo: false,
    );
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => OutgoingCallScreen(
          callProvider: _callProvider,
          displayName: widget.patientName,
          avatarUrl: _patientPhotoUrl(),
          isVideoCall: false,
        ),
      ),
    );
  }

  Future<void> _startVideoCall() async {
    if (_doctorInActiveCall) return;
    final ok = await PermissionService.instance
        .ensureCameraAndMicrophonePermissions(context);
    if (!ok || !mounted) return;
    final roomId =
        'room_${widget.conversationId}_${DateTime.now().millisecondsSinceEpoch}';
    await _callProvider.startOutgoingCall(
      targetUserId: widget.patientId,
      callRoomId: roomId,
      isVideo: true,
    );
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => OutgoingCallScreen(
          callProvider: _callProvider,
          displayName: widget.patientName,
          avatarUrl: _patientPhotoUrl(),
          isVideoCall: true,
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _callIconsPulse = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    _callProvider = CallProvider(webRtcService: WebRtcService.instance);
    _callProvider.addListener(_onDoctorCallState);
    CallChatContext.register(
      conversationId: widget.conversationId,
      doctorId: widget.doctorId,
      patientId: widget.patientId,
      isPatientSide: false,
      patientDisplayName: widget.patientName,
      onReloadMessages: () async {
        await _load();
      },
    );
    WebRtcService.instance.connectSocket(selfUserId: widget.doctorId);
    WebRtcService.instance.joinConversationRoom(widget.conversationId);
    () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final name = readableDoctorName(prefs.getString(kSessionDoctorNameKey));
        if (mounted) setState(() => _doctorDisplayName = name);
      } catch (_) {}
    }();
    _callSummarySocketSub = WebRtcService.instance.callSummaryEvents.listen((
      data,
    ) async {
      final conv = data['conversationId']?.toString() ?? '';
      if (conv != widget.conversationId) return;
      await _loadNewMessages();
      if (!mounted) return;
      setState(() {});
    });
    _patientWaitingSub = WebRtcService.instance.consultationPatientWaiting
        .listen((data) {
          final cid = data['conversationId']?.toString() ?? '';
          if (cid != widget.conversationId) return;
          final raw = data['enteredAt']?.toString();
          final dt = DateTime.tryParse(raw ?? '')?.toLocal() ?? DateTime.now();
          if (!mounted) return;
          setState(() {
            _patientWaitingSince = dt;
            _showPatientLeftNotice = false;
          });
          _patientLeftFadeTimer?.cancel();
        });
    _patientLeftSub = WebRtcService.instance.consultationPatientLeftWaiting
        .listen((data) {
          final cid = data['conversationId']?.toString() ?? '';
          if (cid != widget.conversationId) return;
          final pid = data['patientId']?.toString() ?? '';
          if (pid.isNotEmpty && pid != widget.patientId) return;
          if (!mounted) return;
          _onPatientLeftWaitingUi();
        });
    _chatSessionClosedSub = WebRtcService.instance.chatSessionClosedEvents
        .listen((data) async {
          final cid = data['conversationId']?.toString() ?? '';
          if (cid != widget.conversationId) return;
          if (!mounted) return;
          setState(() => _sessionClosed = true);
          await _load();
        });
    _chatSessionReopenedSub = WebRtcService.instance.chatSessionReopenedEvents
        .listen((data) async {
          final cid = data['conversationId']?.toString() ?? '';
          if (cid != widget.conversationId) return;
          if (!mounted) return;
          setState(() => _sessionClosed = false);
          await _load();
        });
    _chatTypingSub = WebRtcService.instance.chatTypingEvents.listen((data) {
      final cid = data['conversationId']?.toString() ?? '';
      if (cid != widget.conversationId) return;
      final role = data['role']?.toString() ?? '';
      if (role != 'patient') return;
      final typing = data['typing'] == true;
      if (!mounted) return;
      _typingPauseTimer?.cancel();
      if (typing) {
        setState(() => _peerTyping = true);
        _typingPauseTimer = Timer(const Duration(seconds: 3), () {
          if (mounted) setState(() => _peerTyping = false);
        });
      } else {
        setState(() => _peerTyping = false);
      }
    });
    _chatMessagesReadSub = WebRtcService.instance.chatMessagesReadEvents.listen(
      (data) {
        final cid = data['conversationId']?.toString() ?? '';
        if (cid != widget.conversationId) return;
        final rt = data['readerFromType']?.toString() ?? '';
        if (rt != 'patient') return;
        final iso = data['readAt']?.toString();
        if (!mounted) return;
        setState(() {
          for (final m in _messages) {
            if (m['fromType'] == 'doctor' && m['readAt'] == null) {
              m['readAt'] = iso;
            }
          }
        });
      },
    );
    _incomingCallSub = WebRtcService.instance.incomingCalls.listen((data) {
      if (!mounted) return;
      final fromUserId = data['from']?.toString() ?? '';
      if (fromUserId.isEmpty || fromUserId != widget.patientId) return;
      if (_doctorInActiveCall) return;
      final sdp = Map<String, dynamic>.from((data['sdp'] as Map?) ?? {});
      final roomId = data['roomId']?.toString() ?? '';
      final mediaType = data['mediaType']?.toString() ?? 'audio';
      final isVideoCall = mediaType == 'video';
      if (roomId.isEmpty || sdp.isEmpty) return;
      final callerInfo = Map<String, dynamic>.from(
        (data['callerInfo'] as Map?) ?? {},
      );
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => IncomingCallScreen(
            callProvider: _callProvider,
            fromUserId: fromUserId,
            displayName: callerInfo['name']?.toString() ?? widget.patientName,
            avatarUrl:
                callerInfo['avatarUrl']?.toString() ?? _patientPhotoUrl(),
            roomId: roomId,
            offer: sdp,
            isVideoCall: isVideoCall,
          ),
        ),
      );
    });
    _waitingUiTick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _patientWaitingSince == null) return;
      setState(() {});
    });
    _rdvPollTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      unawaited(_refreshNearestRendezVous());
    });
    _rdvBoundaryTick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted || _nextRendezVousStart == null) return;
      setState(() {});
      _syncCallIconsPulse();
    });
    _load();
    _startMessagePolling();
    if (widget.autoStartAudioCall) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted || _autoCallTriggered) return;
        _autoCallTriggered = true;
        await Future<void>.delayed(const Duration(milliseconds: 250));
        if (!mounted) return;
        await _startAudioCall();
      });
    }
  }

  void _startMessagePolling() {
    _messagePollTimer?.cancel();
    _messagePollTimer = Timer.periodic(_pollInterval, (_) async {
      if (!mounted || _pollInFlight) return;
      if (_textSendInFlight) return;
      _pollInFlight = true;
      try {
        final hasNew = await _loadNewMessages();
        if (hasNew && mounted) setState(() {});
      } catch (_) {
      } finally {
        _pollInFlight = false;
      }
    });
  }

  String? _extractObjectId(dynamic value) {
    if (value == null) return null;
    final s = value.toString();
    final m = RegExp(r'[0-9a-fA-F]{24}').firstMatch(s);
    return m?.group(0);
  }

  Future<bool> _loadNewMessages() async {
    if (_messages.isEmpty) return false;
    final afterId = _extractObjectId(_messages.last['_id']);
    if (afterId == null || afterId.isEmpty) return false;

    final bundle = await ApiService.getMessagesAfter(
      conversationId: widget.conversationId,
      afterId: afterId,
    );
    final rawList = bundle['messages'];
    final newMessages = rawList is List
        ? rawList.map((e) => Map<String, dynamic>.from(e as Map)).toList()
        : <Map<String, dynamic>>[];
    final ss = bundle['sessionStatus']?.toString() ?? 'open';
    if (mounted) {
      setState(() => _sessionClosed = ss == 'cloture');
    }
    if (newMessages.isEmpty) return false;

    final existingIds = <String>{
      for (final m in _messages)
        if (_extractObjectId(m['_id']) != null) _extractObjectId(m['_id'])!,
    };
    var added = 0;
    for (final raw in newMessages) {
      final m = Map<String, dynamic>.from(raw);
      final id = _extractObjectId(m['_id']);
      if (id != null && existingIds.contains(id)) continue;
      if (id != null) existingIds.add(id);
      _messages.add(m);
      added++;
    }
    if (added > 0) {
      _scrollToEnd();
      unawaited(_markDoctorReadQuiet());
    }
    return added > 0;
  }

  Future<void> _markDoctorReadQuiet() async {
    try {
      await ApiService.markMessagesRead(
        conversationId: widget.conversationId,
        readerFromType: 'doctor',
      );
    } catch (_) {}
  }

  void _onTextChangedTyping(String text) {
    if (_sessionClosed) return;
    if (mounted) setState(() {});
    WebRtcService.instance.emitChatTyping(
      conversationId: widget.conversationId,
      typing: true,
      role: 'doctor',
    );
    _typingEmitEndTimer?.cancel();
    _typingEmitEndTimer = Timer(const Duration(milliseconds: 1200), () {
      WebRtcService.instance.emitChatTyping(
        conversationId: widget.conversationId,
        typing: false,
        role: 'doctor',
      );
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final futMessages = ApiService.getMessages(
        conversationId: widget.conversationId,
      );
      final bundle = await futMessages;
      final list =
          (bundle['messages'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          <Map<String, dynamic>>[];
      final ss = bundle['sessionStatus']?.toString() ?? 'open';

      if (mounted) {
        setState(() {
          _messages.clear();
          _messages.addAll(list);
          _sessionClosed = ss == 'cloture';
          _loading = false;
        });
        _scrollToEnd();
        unawaited(_markDoctorReadQuiet());
        try {
          final wr = await ApiService.getConversationWaitingRoom(
            widget.conversationId,
          );
          if (!mounted) return;
          if (wr['waiting'] == true) {
            final iso = wr['enteredAt']?.toString();
            final dt = DateTime.tryParse(iso ?? '')?.toLocal();
            setState(() {
              _patientWaitingSince = dt ?? DateTime.now();
              _showPatientLeftNotice = false;
            });
          }
        } catch (_) {}
        unawaited(_refreshNearestRendezVous());
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  DateTime? _messageCreatedAt(Map<String, dynamic> m) {
    final raw = m['createdAt'];
    if (raw == null) return null;
    if (raw is String) return DateTime.tryParse(raw)?.toLocal();
    return null;
  }

  String _formatDateHeaderLine(DateTime day) {
    final now = DateTime.now();
    final t0 = DateTime(now.year, now.month, now.day);
    final y0 = t0.subtract(const Duration(days: 1));
    final d0 = DateTime(day.year, day.month, day.day);
    if (d0 == t0) return 'Aujourd\'hui';
    if (d0 == y0) return 'Hier';
    return DateFormat('dd/MM/yyyy').format(day);
  }

  List<Widget> _buildDatedMessageChildren() {
    final msgs = _messagesForDisplay;
    if (msgs.isEmpty) return [];
    final out = <Widget>[];
    DateTime? lastDay;
    for (final m in msgs) {
      final dt = _messageCreatedAt(m);
      if (dt != null) {
        final day = DateTime(dt.year, dt.month, dt.day);
        if (lastDay == null ||
            day.year != lastDay.year ||
            day.month != lastDay.month ||
            day.day != lastDay.day) {
          lastDay = day;
          out.add(_DateSeparatorChip(label: _formatDateHeaderLine(day)));
        }
      }
      out.add(_buildMessageBubble(m));
    }
    return out;
  }

  Future<void> _openClotureDialog() async {
    final ok = await showDoctorCloseDiscussionDialog(context);
    if (ok != true || !mounted) return;
    try {
      await ApiService.cloturerConversation(
        conversationId: widget.conversationId,
        doctorId: widget.doctorId,
      );
      if (!mounted) return;
      setState(() => _sessionClosed = true);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _openRouvrirDialog() async {
    final ok = await showDoctorReopenDiscussionDialog(context);
    if (ok != true || !mounted) return;
    try {
      await ApiService.rouvrirConversation(
        conversationId: widget.conversationId,
        doctorId: widget.doctorId,
      );
      if (!mounted) return;
      setState(() => _sessionClosed = false);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Session réouverte ✅ Le patient peut de nouveau envoyer des messages',
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: _rouvrirGreen,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  static String _urgencyToPayload(_MessageUrgency u) {
    switch (u) {
      case _MessageUrgency.urgent:
        return 'urgent';
      case _MessageUrgency.medium:
        return 'medium';
      case _MessageUrgency.normal:
        return 'normal';
    }
  }

  Future<void> _sendText() async {
    if (_sessionClosed || !_canSendMessages) return;
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    if (_textSendInFlight) return;
    _textSendInFlight = true;
    _textController.clear();
    try {
      await ApiService.sendDoctorMessage(
        conversationId: widget.conversationId,
        doctorId: widget.doctorId,
        type: 'text',
        content: text,
        payload: {
          'urgency': _urgencyToPayload(_messageUrgency),
          'importance': _messageImportance,
        },
      );
      final hasNew = await _loadNewMessages();
      if (!hasNew) await _load();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      _textSendInFlight = false;
    }
  }

  Future<void> _executePendingSend() async {
    if (_sessionClosed || !_canSendMessages) return;
    if (_pendingAttachmentFile != null) {
      try {
        await ApiService.uploadChatAttachment(
          conversationId: widget.conversationId,
          senderId: widget.doctorId,
          file: _pendingAttachmentFile!,
        );
        setState(() => _pendingAttachmentFile = null);
        final hasNew = await _loadNewMessages();
        if (!hasNew) await _load();
        return;
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }

    if (_pendingVoiceFile != null) {
      try {
        await ApiService.uploadChatAttachment(
          conversationId: widget.conversationId,
          senderId: widget.doctorId,
          file: _pendingVoiceFile!,
        );
        setState(() => _pendingVoiceFile = null);
        final hasNew = await _loadNewMessages();
        if (!hasNew) await _load();
        return;
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }

    await _sendText();
  }

  void _removeSendImportanceOverlay() {
    _sendImportanceOverlay?.remove();
    _sendImportanceOverlay = null;
  }

  bool _hasSendableContent() {
    return _pendingAttachmentFile != null ||
        _pendingVoiceFile != null ||
        _textController.text.trim().isNotEmpty;
  }

  void _showSendImportanceOverlay() {
    if (_sessionClosed) return;
    if (!_hasSendableContent()) return;
    _removeSendImportanceOverlay();
    if (!mounted) return;

    _sendImportanceOverlay = OverlayEntry(
      builder: (_) => _buildSendImportanceOverlay(),
    );
    Overlay.of(context, rootOverlay: true).insert(_sendImportanceOverlay!);
  }

  Widget _buildSendImportanceOverlay() {
    double measuredW = 48.0;
    final ctx = _sendButtonKey.currentContext;
    if (ctx != null) {
      final box = ctx.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize) {
        measuredW = box.size.width;
      }
    }
    final double panelWidth = math.max(200.0, measuredW + 16.0);

    Widget option({
      required String value,
      required String label,
      required String emoji,
      required Color color,
    }) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () {
              _removeSendImportanceOverlay();
              _selectImportance(value);
              unawaited(_executePendingSend());
            },
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              backgroundColor: color,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.max,
              children: [
                Text(emoji, style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _removeSendImportanceOverlay,
            child: Container(color: Colors.black.withValues(alpha: 0.12)),
          ),
        ),
        CompositedTransformFollower(
          link: _sendButtonLayerLink,
          targetAnchor: Alignment.topRight,
          followerAnchor: Alignment.bottomRight,
          offset: const Offset(0, -8),
          child: Material(
            elevation: 12,
            borderRadius: BorderRadius.circular(12),
            color: Colors.white,
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              width: panelWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 4),
                  option(
                    value: 'very_important',
                    label: 'Très important',
                    emoji: '🔴',
                    color: const Color(0xFFF44336),
                  ),
                  option(
                    value: 'important',
                    label: 'Important',
                    emoji: '🟠',
                    color: const Color(0xFFFF9800),
                  ),
                  option(
                    value: 'normal',
                    label: 'Normal',
                    emoji: '🟢',
                    color: const Color(0xFF4CAF50),
                  ),
                  const SizedBox(height: 4),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _selectImportance(String selected) {
    setState(() {
      _messageImportance = selected;
      _messageUrgency = selected == 'very_important'
          ? _MessageUrgency.urgent
          : selected == 'important'
          ? _MessageUrgency.medium
          : _MessageUrgency.normal;
    });
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles();
      if (result == null || result.files.isEmpty) return;
      setState(() => _pendingAttachmentFile = result.files.first);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Fichier prêt: ${_pendingAttachmentFile!.name}. Appuyez sur Envoyer.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _pickImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) return;
      setState(() => _pendingAttachmentFile = result.files.first);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Image prête: ${_pendingAttachmentFile!.name}. Appuyez sur Envoyer.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _pickFromCamera() async {
    try {
      final picker = ImagePicker();
      final x = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 4096,
      );
      if (x == null) return;
      final bytes = await x.readAsBytes();
      var name = x.name.trim();
      if (name.isEmpty) {
        name = 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
      }
      setState(
        () => _pendingAttachmentFile = PlatformFile(
          name: name,
          size: bytes.length,
          bytes: bytes,
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Photo prête: ${_pendingAttachmentFile!.name}. Appuyez sur Envoyer.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showAttachmentPickerMenu() {
    if (_sessionClosed) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                leading: Icon(Icons.folder_open_rounded, color: _skyBlue),
                title: const Text('Fichiers'),
                subtitle: const Text('Importer depuis l\'appareil'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _pickFile();
                },
              ),
              ListTile(
                leading: Icon(Icons.photo_library_rounded, color: _skyBlue),
                title: const Text('Galerie'),
                subtitle: const Text(
                  'Choisir une image dans la galerie photos',
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _pickImage();
                },
              ),
              ListTile(
                leading: Icon(Icons.photo_camera_rounded, color: _skyBlue),
                title: const Text('Appareil photo'),
                subtitle: const Text('Prendre une photo'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _pickFromCamera();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  DateTime _attachmentSortTime(Map<String, dynamic> msg) {
    final c = msg['createdAt'];
    if (c is String) {
      final d = DateTime.tryParse(c);
      if (d != null) return d.toLocal();
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  Future<void> _openConversationInfoPanel() async {
    final entries = <Map<String, dynamic>>[];
    for (final msg in _messages) {
      final type = msg['type'] as String? ?? '';
      if (type != 'attachment' && type != 'file') continue;
      final payload = msg['payload'] as Map<String, dynamic>?;
      final path = payload?['path'] as String?;
      if (path == null || path.isEmpty) continue;
      final url = ApiService.resolveMediaUrl(path);
      if (url.isEmpty) continue;
      final filename = msg['content'] as String? ?? 'Fichier';
      final mimetype = payload?['mimetype'] as String? ?? '';
      final isAudio =
          mimetype.startsWith('audio/') ||
          filename.toLowerCase().endsWith('.m4a') ||
          filename.toLowerCase().endsWith('.webm');
      if (isAudio) continue;
      final isImage =
          !isAudio && _medecinChatAttachmentIsImage(mimetype, filename, url);
      entries.add({
        'url': url,
        'filename': filename,
        'mimetype': mimetype,
        'size': payload?['size'],
        'isImage': isImage,
        'createdAt': _attachmentSortTime(msg),
      });
    }
    entries.sort(
      (a, b) =>
          (b['createdAt'] as DateTime).compareTo(a['createdAt'] as DateTime),
    );
    final medias = entries.where((e) => e['isImage'] == true).toList();
    final files = entries.where((e) => e['isImage'] != true).toList();

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: HeadsAppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (_, controller) {
            return ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: HeadsAppColors.border,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Stack(
                  children: [
                    const Align(
                      alignment: Alignment.center,
                      child: Text(
                        'Informations de la conversation',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Positioned(
                      top: 0,
                      right: 0,
                      child: IconButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        tooltip: 'Fermer',
                        icon: const Icon(Icons.close_rounded, size: 20),
                        color: HeadsAppColors.textPrimary,
                        style: IconButton.styleFrom(
                          backgroundColor: HeadsAppColors.surfaceSoft,
                          side: const BorderSide(
                            color: HeadsAppColors.border,
                            width: 1,
                          ),
                          minimumSize: const Size(36, 36),
                          padding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Médias (${medias.length})',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                if (medias.isEmpty)
                  Text(
                    'Aucun média.',
                    style: const TextStyle(color: HeadsAppColors.textSecondary),
                  )
                else
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: medias.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 6,
                          crossAxisSpacing: 6,
                        ),
                    itemBuilder: (_, i) {
                      final m = medias[i];
                      return InkWell(
                        onTap: () => _medecinShowChatImageFullscreen(
                          context,
                          m['url'] as String,
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            m['url'] as String,
                            fit: BoxFit.cover,
                          ),
                        ),
                      );
                    },
                  ),
                const SizedBox(height: 20),
                Text(
                  'Fichiers (${files.length})',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                if (files.isEmpty)
                  Text(
                    'Aucun fichier.',
                    style: const TextStyle(color: HeadsAppColors.textSecondary),
                  )
                else
                  ...files.map((f) {
                    final filename = f['filename'] as String;
                    final mimetype = f['mimetype'] as String? ?? '';
                    final style = _medecinFileTypeStyle(filename, mimetype);
                    final url = f['url'] as String;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: HeadsAppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: HeadsAppColors.border),
                      ),
                      child: Row(
                        children: [
                          Icon(style.icon, color: style.accent, size: 24),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  filename,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  [
                                        _medecinFormatAttachmentSize(f['size']),
                                        style.extLabel,
                                      ]
                                      .where((e) => e.toString().isNotEmpty)
                                      .join(' · '),
                                  style: TextStyle(
                                    color: HeadsAppColors.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: () => _medecinOpenChatAttachmentFile(
                              context,
                              url,
                              filename,
                              isImage: false,
                              mimetype: mimetype,
                            ),
                            icon: const Icon(Icons.download_rounded, size: 18),
                            label: const Text('Ouvrir'),
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              minimumSize: const Size(0, 32),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _startRecording() async {
    final hasPermission = await _audioRecorder.hasPermission();
    if (!hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Autorisation micro requise pour enregistrer.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    try {
      if (kIsWeb) {
        const path = 'voice.webm';
        await _audioRecorder.start(
          const RecordConfig(encoder: AudioEncoder.opus),
          path: path,
        );
      } else {
        final dir = await getTemporaryDirectory();
        final path =
            '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
        await _audioRecorder.start(
          const RecordConfig(encoder: AudioEncoder.aacLc),
          path: path,
        );
      }
      if (mounted) setState(() => _isRecording = true);
    } catch (e) {
      if (!mounted) return;
      final msg =
          e.toString().contains('MissingPluginException') ||
              e.toString().contains('getTemporaryDirectory')
          ? 'Enregistrement vocal non disponible sur cette plateforme.'
          : 'Erreur enregistrement: ${e.toString().replaceFirst('Exception: ', '')}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
      );
    }
  }

  Future<void> _stopAndSendRecording() async {
    if (!_isRecording) return;
    try {
      final path = await _audioRecorder.stop();
      if (path == null || path.isEmpty) {
        if (mounted) setState(() => _isRecording = false);
        return;
      }
      PlatformFile file;
      if (kIsWeb) {
        Uint8List? bytes;
        try {
          bytes = await XFile(path).readAsBytes();
        } catch (_) {
          try {
            final resp = await http.get(Uri.parse(path));
            if (resp.statusCode >= 200 && resp.statusCode < 300) {
              bytes = resp.bodyBytes;
            }
          } catch (_) {}
        }
        if (bytes == null || bytes.isEmpty) {
          throw Exception('Impossible de lire l’enregistrement vocal web.');
        }
        file = PlatformFile(
          name: 'voice.webm',
          size: bytes.length,
          bytes: bytes,
        );
      } else {
        file = PlatformFile(name: 'voice.m4a', path: path, size: 0);
      }
      if (mounted) {
        setState(() {
          _isRecording = false;
          _pendingVoiceFile = file;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Message vocal prêt à être envoyé.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isRecording = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  void dispose() {
    _messagePollTimer?.cancel();
    _waitingUiTick?.cancel();
    _rdvPollTimer?.cancel();
    _rdvBoundaryTick?.cancel();
    _patientLeftFadeTimer?.cancel();
    _typingPauseTimer?.cancel();
    _typingEmitEndTimer?.cancel();
    _chatSessionClosedSub?.cancel();
    _chatSessionReopenedSub?.cancel();
    _chatTypingSub?.cancel();
    _chatMessagesReadSub?.cancel();
    _incomingCallSub?.cancel();
    _patientWaitingSub?.cancel();
    _patientLeftSub?.cancel();
    _callSummarySocketSub?.cancel();
    _callProvider.removeListener(_onDoctorCallState);
    _callProvider.dispose();
    _callIconsPulse.dispose();
    CallChatContext.unregister();
    _textController.dispose();
    _scrollController.dispose();
    _audioRecorder.dispose();
    _removeSendImportanceOverlay();
    super.dispose();
  }

  Widget _buildWaitingRoomTopBanners() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: _patientWaitingSince != null
          ? _DoctorWaitingRoomStrip(
              key: const ValueKey<String>('waiting-room-strip'),
              patientName: widget.patientName,
              waitingSince: _patientWaitingSince!,
            )
          : _showPatientLeftNotice
          ? Material(
              key: const ValueKey<String>('left-notice'),
              color: Colors.grey.shade200,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      color: Colors.grey.shade700,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Le patient a quitté la salle d\'attente',
                        style: TextStyle(
                          color: Colors.grey.shade800,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : const SizedBox.shrink(key: ValueKey<String>('none')),
    );
  }

  Widget _buildPulsingCallAction({
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
    Color iconColor = _headerNavy,
  }) {
    final blink = _shouldBlinkCallIconsForRendezVous();
    return AnimatedBuilder(
      animation: _callIconsPulse,
      builder: (context, child) {
        final opacity = blink ? (_callIconsPulse.value < 0.5 ? 1.0 : 0.0) : 1.0;
        return Opacity(
          opacity: opacity,
          child: IconButton(
            tooltip: tooltip,
            icon: Icon(icon, color: iconColor, size: 22),
            onPressed: onPressed,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(8),
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
        );
      },
    );
  }

  Widget _buildChatHeader() {
    return Material(
      color: Colors.white,
      elevation: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(2, 2, 4, 8),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                color: _headerNavy,
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              Stack(
                clipBehavior: Clip.none,
                children: [
                  patientAvatarForDoctor(
                    name: widget.patientName,
                    patientPhotoPath: widget.patientPhotoPath,
                    radius: 20,
                    backgroundColor: HeadsAppColors.brandHighlight,
                    accentColor: _headerNavy,
                  ),
                  if (!_sessionClosed)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 11,
                        height: 11,
                        decoration: BoxDecoration(
                          color: _onlineGreen,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.patientName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: HeadsAppColors.textPrimary,
                      ),
                    ),
                    Text(
                      _sessionClosed ? 'Session clôturée' : 'En ligne',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: _sessionClosed
                            ? HeadsAppColors.textSecondary
                            : _onlineGreen,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: _sessionClosed
                    ? 'Session clôturée'
                    : 'Rédiger une ordonnance',
                icon: const Icon(Icons.medical_information_outlined, size: 22),
                color: _headerNavy,
                onPressed: _sessionClosed ? null : _openPrescriptionComposer,
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                tooltip: PrescriptionHistoryStrings.tooltipHistory,
                icon: const Icon(Icons.history_rounded, size: 22),
                color: _headerNavy,
                onPressed: _openPrescriptionHistoryForDoctor,
                visualDensity: VisualDensity.compact,
              ),
              _buildPulsingCallAction(
                tooltip: 'Appel vidéo',
                icon: Icons.videocam_outlined,
                onPressed: _doctorInActiveCall ? null : _startVideoCall,
              ),
              _buildPulsingCallAction(
                tooltip: 'Appel audio',
                icon: Icons.call_outlined,
                onPressed: _doctorInActiveCall ? null : _startAudioCall,
              ),
              IconButton(
                tooltip: 'Informations',
                icon: const Icon(Icons.more_vert_rounded, size: 22),
                color: _headerNavy,
                onPressed: _openConversationInfoPanel,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _isReplyByMessageMarker(Map<String, dynamic> msg) {
    return _payloadEvent(msg) == 'reply_by_message';
  }

  String? _payloadEvent(Map<String, dynamic> m) {
    final p = m['payload'];
    if (p == null || p is! Map) return null;
    final map = Map<String, dynamic>.from(p);
    final ev = map['event'];
    if (ev == null) return null;
    return ev.toString();
  }

  bool get _canSendMessages {
    if (_sessionClosed) return false;
    int lastTeleIndex = -1;
    for (var i = 0; i < _messages.length; i++) {
      final m = _messages[i];
      final type = m['type'] as String? ?? '';
      final fromType = m['fromType'] as String? ?? '';
      if (fromType == 'system' &&
          (type == 'request_teleconsult' || type == 'form_teleconsult')) {
        lastTeleIndex = i;
      }
    }
    if (lastTeleIndex == -1) return false;

    for (var j = lastTeleIndex + 1; j < _messages.length; j++) {
      if (_payloadEvent(_messages[j]) == 'reply_by_message') return true;
    }
    return false;
  }

  bool _isDecisionMessage(Map<String, dynamic> msg) {
    final type = msg['type'] as String? ?? '';
    return type == 'accept_request' || _isReplyByMessageMarker(msg);
  }

  bool _hasDecisionAfterIndex(int index) {
    for (var i = index + 1; i < _messages.length; i++) {
      if (_isDecisionMessage(_messages[i])) return true;
    }
    return false;
  }

  Future<void> _openPrescriptionComposer() async {
    if (!_canSendMessages) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Choisissez « Répondre par message » depuis le formulaire de téléconsultation pour ouvrir l’échange.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    await showDoctorPrescriptionFormBottomSheet(
      context,
      conversationId: widget.conversationId,
      doctorId: widget.doctorId,
      patientName: widget.patientName,
      source: PrescriptionSendSource.chat,
      onSent: _load,
    );
  }

  void _openPrescriptionHistoryForDoctor() {
    openDoctorPrescriptionHistory(
      context,
      conversationId: widget.conversationId,
      doctorId: widget.doctorId,
      patientName: widget.patientName,
      sessionClosed: _sessionClosed,
      onPrescriptionChanged: _load,
    );
  }

  List<Map<String, dynamic>> get _messagesForDisplay {
    final out = <Map<String, dynamic>>[];
    for (var i = 0; i < _messages.length; i++) {
      final msg = _messages[i];
      final type = msg['type'] as String? ?? '';

      if (_isDecisionMessage(msg)) continue;
      if (type == 'form_teleconsult' || type == 'form_teleconsult_prompt') {
        continue;
      }

      final isTeleRequest = type == 'request_teleconsult';
      if (isTeleRequest && _hasDecisionAfterIndex(i)) continue;

      out.add(msg);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE8ECF0),
      body: _loading
          ? Column(
              children: [
                _buildChatHeader(),
                const Expanded(
                  child: Center(
                    child: CircularProgressIndicator(color: _skyBlue),
                  ),
                ),
              ],
            )
          : _error != null
              ? Column(
                  children: [
                    _buildChatHeader(),
                    Expanded(
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.error_outline_rounded,
                                size: 56,
                                color: Colors.red.shade700,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _error!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: HeadsAppColors.danger,
                                ),
                              ),
                              const SizedBox(height: 16),
                              FilledButton.icon(
                                onPressed: _load,
                                icon: const Icon(Icons.refresh_rounded),
                                label: const Text('Réessayer'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: HeadsAppColors.brandPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              : Column(
                  children: [
                    _buildChatHeader(),
                    _buildWaitingRoomTopBanners(),
                    AnimatedCrossFade(
                      duration: const Duration(milliseconds: 300),
                      sizeCurve: Curves.easeOut,
                      firstCurve: Curves.easeOut,
                      secondCurve: Curves.easeOut,
                      crossFadeState: _sessionClosed
                          ? CrossFadeState.showFirst
                          : CrossFadeState.showSecond,
                      firstChild: Material(
                        color: const Color(0xFFEEF2F6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.check_circle_outline_rounded,
                                color: _sessionClosedBannerGreenFg,
                                size: 22,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Session clôturée ✅',
                                  style: TextStyle(
                                    color: _sessionClosedBannerGreenFg,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      secondChild: const SizedBox(width: double.infinity),
                    ),
                    Expanded(
                      child: DoctorChatPatternBackground(
                        child: Column(
                          children: [
                            Expanded(
                              child: RefreshIndicator(
                                color: _skyBlue,
                                onRefresh: _load,
                                child: ListView(
                                  controller: _scrollController,
                                  padding:
                                      const EdgeInsets.fromLTRB(16, 12, 16, 8),
                                  children: _buildDatedMessageChildren(),
                                ),
                              ),
                            ),
                            if (_canSendMessages)
                              const DoctorChatSecureNoticeCard(),
                            _buildInputBar(),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> msg) {
    final type = msg['type'] as String? ?? 'text';
    final fromType = msg['fromType'] as String? ?? 'system';

    if (type == 'request_teleconsult') {
      final payload = msg['payload'] as Map<String, dynamic>? ?? {};
      final motif = payload['motif'] as String? ?? '';
      final letterRaw = (payload['letterBody'] as String? ?? '').trim();
      final letterBody = letterRaw.isNotEmpty
          ? letterRaw
          : kTeleconsultFirstRequestLetterBody;
      return _RequestTeleconsultCard(letterBody: letterBody, motif: motif);
    }
    if (type == 'accept_request') {
      return const _InfoBubbleDoctor(
        icon: Icons.check_circle_rounded,
        iconColor: Color(0xFF16A34A),
        text:
            'Vous avez accepté la demande de téléconsultation. Le patient peut désormais échanger dans ce chat.',
      );
    }
    if (type == 'call_event') {
      final p = msg['payload'];
      if (p is Map && p['kind']?.toString() == 'call_log') {
        return CallLogBubble(
          payload: Map<String, dynamic>.from(p),
          titleOverride: msg['content'] as String?,
        );
      }
      return _InfoBubbleDoctor(
        icon: Icons.phone_callback_rounded,
        iconColor: const Color(0xFF64748B),
        text: msg['content'] as String? ?? '',
      );
    }
    if (type == 'rdv_teleconsult_programme') {
      return _InfoBubbleDoctor(
        icon: Icons.event_note_rounded,
        iconColor: const Color(0xFF0F766E),
        text: msg['content'] as String? ?? '',
      );
    }
    if (type == 'rdv_teleconsult_annule') {
      return _InfoBubbleDoctor(
        icon: Icons.event_busy_rounded,
        iconColor: const Color(0xFFB91C1C),
        text: msg['content'] as String? ?? '',
      );
    }
    if (type == 'teleconsult_scheduled') {
      final dt = _teleconsultLocalFromMessage(msg);
      final content = (msg['content'] as String? ?? '').trim();
      final fallbackDate = dt != null
          ? DateFormat('dd/MM/yyyy à HH:mm').format(dt)
          : '—';
      if (fromType == 'doctor') {
        return _ScheduledTeleconsultReadOnlyCard(dateLabel: fallbackDate);
      }
      return _InfoBubbleDoctor(
        icon: Icons.event_available_rounded,
        iconColor: _skyBlue,
        text: content.isNotEmpty ? content : fallbackDate,
      );
    }
    if (type == 'chat_closed') {
      return ChatSessionStatusChip(msg: msg, closed: true);
    }
    if (type == 'chat_reopened') {
      return ChatSessionStatusChip(msg: msg, closed: false);
    }
    if (type == 'question_physique') {
      return _SystemBubble(
        text:
            msg['content'] as String? ??
            'Avez‑vous déjà eu une consultation physique avec ce médecin ?',
      );
    }
    if (type == 'prescription' && fromType == 'doctor') {
      final payload = msg['payload'] as Map<String, dynamic>? ?? {};
      final pdfUrl = '${payload['pdfUrl'] ?? ''}'.trim();
      final prescriptionId = '${payload['prescriptionId'] ?? ''}'.trim();
      final prescriptionMessageId = _extractObjectId(msg['_id']);
      final sentRaw = payload['sentAt']?.toString();
      final sent = DateTime.tryParse(sentRaw ?? '')?.toLocal();
      final dateStr = sent != null
          ? DateFormat('dd/MM/yyyy à HH:mm').format(sent)
          : '';
      final readStr = msg['readAt']?.toString();
      return Align(
        alignment: Alignment.centerRight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _DoctorPrescriptionChatCard(
              icon: Icons.medical_information_rounded,
              iconColor: const Color(0xFF0F766E),
              text: dateStr.isEmpty
                  ? 'Ordonnance médicale'
                  : 'Ordonnance médicale · $dateStr',
              thumbnailUrl: '',
              onOpen: pdfUrl.isEmpty
                  ? null
                  : () {
                      Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          builder: (_) => DoctorPrescriptionPdfViewerScreen(
                            pdfUrl: pdfUrl,
                            conversationId: widget.conversationId,
                            prescriptionId: prescriptionId.isEmpty
                                ? null
                                : prescriptionId,
                            prescriptionMessageId: prescriptionMessageId,
                          ),
                        ),
                      );
                    },
            ),
            if (readStr != null && readStr.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2, right: 4),
                child: Icon(
                  Icons.done_all_rounded,
                  size: 14,
                  color: Colors.grey.shade600,
                ),
              ),
          ],
        ),
      );
    }
    if (type == 'attachment' || type == 'file') {
      final messageId = _extractObjectId(msg['_id']);
      final content = msg['content'] as String? ?? 'Fichier';
      final payload = msg['payload'] as Map<String, dynamic>?;
      final path = payload?['path'] as String?;
      final filename = msg['content'] as String? ?? '';
      final mimetype = payload?['mimetype'] as String? ?? '';
      final isVoice =
          path != null &&
          (mimetype.startsWith('audio/') ||
              filename.toLowerCase().endsWith('.m4a') ||
              filename.toLowerCase().endsWith('.webm'));
      if (isVoice) {
        return _VoiceMessageBubbleDoctor(msg: msg);
      }
      return _AttachmentBubble(
        fromType: fromType,
        content: content,
        payload: payload,
        messageId: messageId,
        conversationId: widget.conversationId,
        readAt: fromType == 'doctor' ? msg['readAt']?.toString() : null,
      );
    }
    final isDoctor = fromType == 'doctor';
    final payload = msg['payload'] as Map<String, dynamic>? ?? {};
    final rawRead = msg['readAt'];
    final readStr = rawRead == null ? null : rawRead.toString();
    return _TextBubble(
      content: msg['content'] as String? ?? '',
      isDoctor: isDoctor,
      urgency: isDoctor ? doctorTextUrgencyFromPayload(payload) : null,
      readAt: readStr,
      doctorDisplayName: _doctorDisplayName,
    );
  }

  Widget _buildInputCircleButton({
    required Widget icon,
    required VoidCallback? onPressed,
    Color backgroundColor = Colors.white,
    String? tooltip,
  }) {
    Widget button = Material(
      color: backgroundColor,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(child: icon),
        ),
      ),
    );
    if (tooltip != null && tooltip.isNotEmpty) {
      button = Tooltip(message: tooltip, child: button);
    }
    return button;
  }

  Widget _buildInputBar() {
    if (!_sessionClosed && !_canSendMessages) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
            decoration: BoxDecoration(
              color: const Color(0xFFE3F2FD),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF90CAF9)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 20,
                  color: Color(0xFF1A458B),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'L’échange de messages n’est pas encore ouvert. Depuis la liste des formulaires de téléconsultation, choisissez « Répondre par message » pour activer le chat.',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: Color(0xFF1A458B),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 8, 10),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_peerTyping)
              Padding(
                padding: const EdgeInsets.only(bottom: 6, left: 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Le patient est en train d\'écrire…',
                    style: TextStyle(
                      fontSize: 12,
                      color: _inputHintGrey,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ),
            if (_sessionClosed)
              Padding(
                padding: const EdgeInsets.only(bottom: 6, left: 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Session clôturée — lecture seule',
                    style: TextStyle(
                      fontSize: 12,
                      color: _inputHintGrey,
                    ),
                  ),
                ),
              ),
            if (_pendingAttachmentFile != null)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.attach_file_rounded,
                      size: 18,
                      color: _inputPlusBlue,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Fichier prêt: ${_pendingAttachmentFile!.name}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    IconButton(
                      onPressed: () =>
                          setState(() => _pendingAttachmentFile = null),
                      icon: const Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: HeadsAppColors.danger,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                    ),
                  ],
                ),
              ),
            if (_pendingVoiceFile != null)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.mic_rounded,
                      size: 18,
                      color: _inputPlusBlue,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Message vocal prêt à envoyer',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                    IconButton(
                      onPressed: () => setState(() => _pendingVoiceFile = null),
                      icon: const Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: HeadsAppColors.danger,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                    ),
                  ],
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8, bottom: 2),
                  child: _buildInputCircleButton(
                    tooltip: 'Ajouter une pièce jointe',
                    onPressed: _sessionClosed ? null : _showAttachmentPickerMenu,
                    icon: Icon(
                      Icons.add_rounded,
                      size: 26,
                      color: _sessionClosed
                          ? _inputHintGrey.withValues(alpha: 0.6)
                          : _inputPlusBlue,
                    ),
                  ),
                ),
                Expanded(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: TextField(
                        controller: _textController,
                        readOnly: _sessionClosed,
                        onChanged: _onTextChangedTyping,
                        textInputAction: TextInputAction.send,
                        decoration: InputDecoration(
                          hintText: _sessionClosed
                              ? 'Session clôturée — lecture seule'
                              : 'Répondre au patient...',
                          hintStyle: const TextStyle(
                            color: _inputHintGrey,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 14,
                          ),
                        ),
                        maxLines: 4,
                        minLines: 1,
                        onSubmitted: (_) => _showSendImportanceOverlay(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: _buildInputCircleButton(
                    tooltip: _isRecording
                        ? 'Arrêter l’enregistrement'
                        : 'Message vocal',
                    onPressed: _sessionClosed
                        ? null
                        : (_isRecording
                              ? _stopAndSendRecording
                              : _startRecording),
                    icon: Icon(
                      _isRecording
                          ? Icons.stop_rounded
                          : Icons.mic_none_rounded,
                      size: 22,
                      color: _isRecording
                          ? _inputLockRed
                          : _inputHintGrey,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                CompositedTransformTarget(
                  key: _sendButtonKey,
                  link: _sendButtonLayerLink,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Material(
                      color: _sessionClosed
                          ? _inputSendBlue.withValues(alpha: 0.45)
                          : _inputSendBlue,
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: _sessionClosed
                            ? null
                            : _showSendImportanceOverlay,
                        customBorder: const CircleBorder(),
                        child: const SizedBox(
                          width: 44,
                          height: 44,
                          child: Icon(
                            Icons.send_rounded,
                            size: 20,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  padding: const EdgeInsets.all(8),
                  constraints: const BoxConstraints(
                    minWidth: 40,
                    minHeight: 40,
                  ),
                  tooltip: _sessionClosed
                      ? 'Réouvrir la session'
                      : 'Clôturer la session',
                  icon: Icon(
                    _sessionClosed
                        ? Icons.lock_open_rounded
                        : Icons.lock_outline_rounded,
                    color: _sessionClosed ? _rouvrirGreen : _inputLockRed,
                    size: 22,
                  ),
                  onPressed: _sessionClosed
                      ? _openRouvrirDialog
                      : _openClotureDialog,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RequestTeleconsultCard extends StatelessWidget {
  const _RequestTeleconsultCard({
    required this.letterBody,
    required this.motif,
  });

  /// Texte intégral de la demande (lettre type) — identique à ce que le patient a certifié.
  final String letterBody;
  final String motif;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: HeadsAppColors.brandPrimary.withValues(alpha: 0.10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: HeadsAppColors.brandPrimary.withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.contact_mail_rounded,
                  color: HeadsAppColors.brandPrimary,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Demande de première téléconsultation',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: HeadsAppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Texte de la demande',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: HeadsAppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 320),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: HeadsAppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: HeadsAppColors.border),
              ),
              child: SingleChildScrollView(
                child: Text(
                  letterBody,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    height: 1.4,
                    color: HeadsAppColors.textPrimary,
                  ),
                ),
              ),
            ),
            if (motif.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Précisions du patient (facultatif)',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: HeadsAppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                motif,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: HeadsAppColors.textPrimary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SystemBubble extends StatelessWidget {
  const _SystemBubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: HeadsAppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: HeadsAppColors.textSecondary,
              fontStyle: FontStyle.italic,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

class _ScheduledTeleconsultReadOnlyCard extends StatelessWidget {
  const _ScheduledTeleconsultReadOnlyCard({required this.dateLabel});

  final String dateLabel;

  static const Color _skyBlue = HeadsAppColors.brandPrimary;

  @override
  Widget build(BuildContext context) {
    final maxW = MediaQuery.sizeOf(context).width - 48;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Center(
        child: Container(
          constraints: BoxConstraints(maxWidth: maxW),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: BoxDecoration(
            color: HeadsAppColors.surfaceSoft,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: HeadsAppColors.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.event_available_rounded,
                size: 20,
                color: _skyBlue,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Téléconsultation planifiée : $dateLabel',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: HeadsAppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoBubbleDoctor extends StatelessWidget {
  const _InfoBubbleDoctor({
    required this.icon,
    required this.iconColor,
    required this.text,
  });

  final IconData icon;
  final Color iconColor;
  final String text;

  @override
  Widget build(BuildContext context) {
    final maxW = MediaQuery.sizeOf(context).width - 48;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Center(
        child: Container(
          constraints: BoxConstraints(maxWidth: maxW),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFE0F2F1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFF16A34A).withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: iconColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF065F46),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DoctorPrescriptionChatCard extends StatelessWidget {
  const _DoctorPrescriptionChatCard({
    required this.icon,
    required this.iconColor,
    required this.text,
    required this.thumbnailUrl,
    this.onOpen,
  });

  final IconData icon;
  final Color iconColor;
  final String text;
  final String thumbnailUrl;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final maxW = MediaQuery.sizeOf(context).width - 48;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onOpen,
            child: Container(
              constraints: BoxConstraints(maxWidth: maxW),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFE0F2F1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFF16A34A).withValues(alpha: 0.4),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(icon, size: 18, color: iconColor),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          text,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: const Color(0xFF065F46),
                                fontWeight: FontWeight.w500,
                              ),
                        ),
                      ),
                    ],
                  ),
                  if (thumbnailUrl.trim().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: Image.network(
                          thumbnailUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: Colors.white,
                            alignment: Alignment.center,
                            child: const Icon(Icons.picture_as_pdf_rounded),
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (onOpen != null) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.tonalIcon(
                        onPressed: onOpen,
                        icon: const Icon(Icons.open_in_new_rounded, size: 18),
                        label: const Text('Ouvrir'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
    );
  }
}

class _TextBubble extends StatelessWidget {
  const _TextBubble({
    required this.content,
    required this.isDoctor,
    required this.doctorDisplayName,
    this.urgency,
    this.readAt,
  });

  final String content;
  final bool isDoctor;
  final String doctorDisplayName;

  /// `urgent` | `medium` | `normal` — uniquement pour les messages médecin.
  final String? urgency;
  final String? readAt;

  @override
  Widget build(BuildContext context) {
    final align = isDoctor ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final isRead = readAt != null && readAt!.trim().isNotEmpty;
    final maxWidth = MediaQuery.of(context).size.width * 0.78;

    if (isDoctor) {
      final level = urgency ?? 'normal';

      late final Color doctorBg;
      late final Color doctorLeftBorder;
      late final String? importanceTag;

      switch (level) {
        case 'urgent':
          doctorBg = const Color(0xFFFFF5F5);
          doctorLeftBorder = const Color(0xFFDC2626);
          importanceTag = 'TRÈS IMPORTANT';
          break;
        case 'medium':
          doctorBg = const Color(0xFFFFF7ED);
          doctorLeftBorder = const Color(0xFFEA580C);
          importanceTag = 'IMPORTANT';
          break;
        default:
          doctorBg = const Color(0xFFF8FAFC);
          doctorLeftBorder = const Color(0xFF22C55E);
          importanceTag = null;
          break;
      }

      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: align,
          children: [
            if (importanceTag != null)
              Container(
                margin: const EdgeInsets.only(bottom: 6, right: 2),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: level == 'urgent'
                      ? const Color(0xFFFCE7F3)
                      : const Color(0xFFFFEDD5),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  importanceTag,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: level == 'urgent'
                        ? const Color(0xFF991B1B)
                        : const Color(0xFF9A3412),
                  ),
                ),
              ),
            Container(
              constraints: BoxConstraints(maxWidth: maxWidth),
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                color: doctorBg,
                borderRadius: BorderRadius.circular(14),
                border: Border(
                  left: BorderSide(color: doctorLeftBorder, width: 5),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _doctorBubbleDisplayName(doctorDisplayName),
                    style: const TextStyle(
                      color: Color(0xFF1A458B),
                      fontWeight: FontWeight.w800,
                      fontSize: 13.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    content,
                    style: const TextStyle(
                      color: Color(0xFF111827),
                      height: 1.4,
                      fontSize: 14.5,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 2),
              child: Icon(
                isRead ? Icons.done_all_rounded : Icons.done_rounded,
                size: 15,
                color: isRead ? const Color(0xFF4FA8D5) : Colors.grey.shade500,
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: align,
        children: [
          Container(
            constraints: BoxConstraints(maxWidth: maxWidth),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: HeadsAppColors.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              content,
              style: const TextStyle(
                color: Color(0xFF1A2740),
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DateSeparatorChip extends StatelessWidget {
  const _DateSeparatorChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: HeadsAppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

bool _medecinChatAttachmentIsImage(
  String mimetype,
  String filename,
  String url,
) {
  final f = filename.toLowerCase();
  const nonImageExt = [
    '.pdf',
    '.doc',
    '.docx',
    '.xls',
    '.xlsx',
    '.ppt',
    '.pptx',
    '.zip',
    '.rar',
    '.7z',
    '.mp3',
    '.wav',
    '.m4a',
    '.webm',
    '.mp4',
    '.mov',
  ];
  for (final ext in nonImageExt) {
    if (f.endsWith(ext)) return false;
  }
  final m = mimetype.toLowerCase();
  if (m.startsWith('image/')) return true;
  for (final ext in [
    '.jpg',
    '.jpeg',
    '.png',
    '.gif',
    '.webp',
    '.bmp',
    '.heic',
    '.heif',
  ]) {
    if (f.endsWith(ext)) return true;
  }
  final u = url.toLowerCase();
  return u.contains('res.cloudinary.com') && u.contains('/image/upload/');
}

Future<void> _medecinShowChatImageFullscreen(
  BuildContext context,
  String url,
) async {
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.all(16),
      backgroundColor: Colors.black,
      child: GestureDetector(
        onTap: () => Navigator.of(ctx).pop(),
        child: InteractiveViewer(
          child: Image.network(url, fit: BoxFit.contain),
        ),
      ),
    ),
  );
}

Future<void> _medecinOpenChatAttachmentFile(
  BuildContext context,
  String url,
  String filename, {
  required bool isImage,
  String mimetype = '',
}) async {
  if (isImage) {
    await _medecinShowChatImageFullscreen(context, url);
    return;
  }
  if (!context.mounted) return;
  if (!kIsWeb) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: CircularProgressIndicator(),
          ),
        ),
      ),
    );
  }
  try {
    await openChatAttachment(url: url, filename: filename);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  } finally {
    if (!kIsWeb && context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }
}

String _medecinFormatAttachmentSize(dynamic sizeRaw) {
  if (sizeRaw == null) return '';
  final n = sizeRaw is int ? sizeRaw : int.tryParse('$sizeRaw');
  if (n == null || n < 0) return '';
  if (n < 1024) return '$n o';
  if (n < 1024 * 1024) {
    final ko = n / 1024;
    return ko < 10 ? '${ko.toStringAsFixed(1)} Ko' : '${ko.round()} Ko';
  }
  return '${(n / (1024 * 1024)).toStringAsFixed(1)} Mo';
}

({String extLabel, IconData icon, Color accent}) _medecinFileTypeStyle(
  String filename,
  String mimetype,
) {
  final lower = filename.toLowerCase();
  if (lower.endsWith('.pdf')) {
    return (
      extLabel: 'PDF',
      icon: Icons.picture_as_pdf_rounded,
      accent: const Color(0xFFE53935),
    );
  }
  if (lower.endsWith('.doc') || lower.endsWith('.docx')) {
    return (
      extLabel: 'DOCX',
      icon: Icons.description_rounded,
      accent: const Color(0xFF2B579A),
    );
  }
  if (lower.endsWith('.xls') || lower.endsWith('.xlsx')) {
    return (
      extLabel: 'XLSX',
      icon: Icons.table_chart_rounded,
      accent: const Color(0xFF217346),
    );
  }
  if (lower.endsWith('.ppt') || lower.endsWith('.pptx')) {
    return (
      extLabel: 'PPTX',
      icon: Icons.slideshow_rounded,
      accent: const Color(0xFFD24726),
    );
  }
  if (lower.endsWith('.zip') ||
      lower.endsWith('.rar') ||
      lower.endsWith('.7z')) {
    return (
      extLabel: 'ZIP',
      icon: Icons.folder_zip_rounded,
      accent: const Color(0xFFF9A825),
    );
  }
  if (mimetype.startsWith('audio/') ||
      lower.endsWith('.m4a') ||
      lower.endsWith('.mp3') ||
      lower.endsWith('.wav')) {
    return (
      extLabel: 'AUDIO',
      icon: Icons.audio_file_rounded,
      accent: const Color(0xFF7E57C2),
    );
  }
  if (mimetype.startsWith('video/') ||
      lower.endsWith('.mp4') ||
      lower.endsWith('.mov')) {
    return (
      extLabel: 'VIDÉO',
      icon: Icons.video_file_rounded,
      accent: const Color(0xFF0288D1),
    );
  }
  final dot = filename.lastIndexOf('.');
  var ext = dot >= 0 ? filename.substring(dot + 1).toUpperCase() : '';
  if (ext.length > 6) ext = 'FICHIER';
  if (ext.isEmpty) ext = 'FICHIER';
  return (
    extLabel: ext,
    icon: Icons.insert_drive_file_rounded,
    accent: const Color(0xFF64748B),
  );
}

class _AttachmentBubble extends StatelessWidget {
  const _AttachmentBubble({
    required this.fromType,
    required this.content,
    this.payload,
    this.messageId,
    this.conversationId,
    this.readAt,
  });

  final String fromType;
  final String content;
  final Map<String, dynamic>? payload;
  final String? messageId;
  final String? conversationId;

  /// Accusé lecture (messages envoyés par le médecin).
  final String? readAt;

  @override
  Widget build(BuildContext context) {
    final isDoctor = fromType == 'doctor';
    final bg = isDoctor ? const Color(0xFF87CEEB) : const Color(0xFFE8F6FC);
    final textColor = isDoctor ? Colors.white : const Color(0xFF2C3E50);
    final align = isDoctor ? CrossAxisAlignment.end : CrossAxisAlignment.start;

    final path = payload?['path'] as String?;
    final mimetype = payload?['mimetype'] as String? ?? '';
    final url = (path != null && path.isNotEmpty)
        ? ApiService.resolveMediaUrl(path)
        : '';
    final isImage =
        url.isNotEmpty && _medecinChatAttachmentIsImage(mimetype, content, url);
    final fileStyle = _medecinFileTypeStyle(content, mimetype);
    final openFileUrl = url;

    final readStr = readAt?.trim();
    final isRead = readStr != null && readStr.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: align,
        children: [
          if (isImage)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: url.isEmpty
                      ? null
                      : () => _medecinShowChatImageFullscreen(context, url),
                  borderRadius: BorderRadius.circular(16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: 260,
                        maxHeight: 220,
                      ),
                      child: Image.network(
                        url,
                        fit: BoxFit.cover,
                        width: 260,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Container(
                            width: 260,
                            height: 160,
                            color: bg.withValues(alpha: 0.5),
                            alignment: Alignment.center,
                            child: SizedBox(
                              width: 28,
                              height: 28,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: textColor,
                              ),
                            ),
                          );
                        },
                        errorBuilder: (context, _, _) => Container(
                          width: 260,
                          padding: const EdgeInsets.all(16),
                          color: bg,
                          child: Row(
                            children: [
                              Icon(
                                Icons.broken_image_rounded,
                                color: textColor,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  content,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: textColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (!isImage)
            InkWell(
              onTap: openFileUrl.isEmpty
                  ? null
                  : () => _medecinOpenChatAttachmentFile(
                      context,
                      openFileUrl,
                      content,
                      isImage: false,
                      mimetype: mimetype,
                    ),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 280),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: fileStyle.accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            fileStyle.icon,
                            color: fileStyle.accent,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                content,
                                style: const TextStyle(
                                  color: Color(0xFF2C3E50),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                [
                                  _medecinFormatAttachmentSize(
                                    payload?['size'],
                                  ),
                                  fileStyle.extLabel,
                                ].where((e) => e.isNotEmpty).join(' · '),
                                style: TextStyle(
                                  color: Colors.grey.shade700,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: OutlinedButton.icon(
                        onPressed: openFileUrl.isEmpty
                            ? null
                            : () => _medecinOpenChatAttachmentFile(
                                context,
                                openFileUrl,
                                content,
                                isImage: false,
                                mimetype: mimetype,
                              ),
                        icon: const Icon(Icons.download_rounded, size: 18),
                        label: const Text('Ouvrir'),
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          minimumSize: const Size(0, 32),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (isDoctor)
            Padding(
              padding: const EdgeInsets.only(top: 2, right: 4),
              child: Icon(
                isRead ? Icons.done_all_rounded : Icons.done_rounded,
                size: 15,
                color: isRead ? const Color(0xFF4FA8D5) : Colors.grey.shade600,
              ),
            ),
        ],
      ),
    );
  }
}

class _VoiceMessageBubbleDoctor extends StatefulWidget {
  const _VoiceMessageBubbleDoctor({required this.msg});

  final Map<String, dynamic> msg;

  @override
  State<_VoiceMessageBubbleDoctor> createState() =>
      _VoiceMessageBubbleDoctorState();
}

class _VoiceMessageBubbleDoctorState extends State<_VoiceMessageBubbleDoctor> {
  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;
  StreamSubscription<PlayerState>? _stateSubscription;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<Duration>? _positionSub;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  String get _audioUrl {
    final payload = widget.msg['payload'] as Map<String, dynamic>?;
    final path = payload?['path'] as String? ?? '';
    final raw = ApiService.resolveMediaUrl(path);
    return raw.replaceAll('/upload/fl_inline/', '/upload/');
  }

  String get _audioMimeType {
    final payload = widget.msg['payload'] as Map<String, dynamic>?;
    return (payload?['mimetype'] as String? ?? '').trim();
  }

  @override
  void initState() {
    super.initState();
    _stateSubscription = _player.onPlayerStateChanged.listen((
      PlayerState state,
    ) {
      if (!mounted) return;
      setState(() {
        _isPlaying = state == PlayerState.playing;
      });
    });
    _durationSub = _player.onDurationChanged.listen((d) {
      if (!mounted) return;
      setState(() => _duration = d);
    });
    _positionSub = _player.onPositionChanged.listen((p) {
      if (!mounted) return;
      setState(() => _position = p);
    });
  }

  @override
  void dispose() {
    _durationSub?.cancel();
    _positionSub?.cancel();
    _stateSubscription?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    if (_audioUrl.isEmpty) return;
    if (_isPlaying) {
      await _player.pause();
    } else {
      try {
        await _player.play(UrlSource(_audioUrl));
      } catch (_) {
        final resp = await http.get(Uri.parse(_audioUrl));
        if (resp.statusCode < 200 ||
            resp.statusCode >= 300 ||
            resp.bodyBytes.isEmpty) {
          throw Exception('Source audio non supportée sur ce navigateur.');
        }
        final mime = _audioMimeType.isNotEmpty ? _audioMimeType : 'audio/webm';
        await _player.play(BytesSource(resp.bodyBytes, mimeType: mime));
      }
    }
  }

  String _fmtDuration(Duration d) {
    final t = d.inSeconds.clamp(0, 86400);
    final m = t ~/ 60;
    final s = t % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final fromType = widget.msg['fromType'] as String? ?? 'system';
    final isDoctor = fromType == 'doctor';
    final align = isDoctor ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final bgColor = isDoctor
        ? const Color(0xFF87CEEB)
        : const Color(0xFFE8F6FC);
    final textColor = isDoctor ? Colors.white : const Color(0xFF2C3E50);
    final rawRead = widget.msg['readAt']?.toString().trim();
    final voiceRead = rawRead != null && rawRead.isNotEmpty;

    return Column(
      crossAxisAlignment: align,
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          constraints: const BoxConstraints(maxWidth: 280),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.mic_rounded, color: textColor, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Message vocal',
                      style: TextStyle(fontSize: 14, color: textColor),
                    ),
                  ),
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                    onPressed: _audioUrl.isEmpty ? null : _togglePlay,
                    icon: Icon(
                      _isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: textColor,
                      size: 28,
                    ),
                  ),
                ],
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 2,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 5,
                  ),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 0),
                ),
                child: Slider(
                  value: _duration.inMilliseconds > 0
                      ? _position.inMilliseconds
                            .clamp(0, _duration.inMilliseconds)
                            .toDouble()
                      : 0,
                  max: _duration.inMilliseconds > 0
                      ? _duration.inMilliseconds.toDouble()
                      : 1,
                  onChanged: _audioUrl.isEmpty || _duration.inMilliseconds <= 0
                      ? null
                      : (v) async {
                          await _player.seek(Duration(milliseconds: v.round()));
                        },
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 4, right: 4, bottom: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _fmtDuration(_position),
                      style: TextStyle(
                        fontSize: 11,
                        color: textColor.withValues(alpha: 0.9),
                      ),
                    ),
                    Text(
                      _fmtDuration(_duration),
                      style: TextStyle(
                        fontSize: 11,
                        color: textColor.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ),
              if (isDoctor) ...[
                const SizedBox(height: 2),
                Align(
                  alignment: Alignment.centerRight,
                  child: Icon(
                    voiceRead ? Icons.done_all_rounded : Icons.done_rounded,
                    size: 15,
                    color: voiceRead ? Colors.white : Colors.white70,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Bandeau salle d’attente sous l’AppBar du chat médecin.
class _DoctorWaitingRoomStrip extends StatelessWidget {
  const _DoctorWaitingRoomStrip({
    super.key,
    required this.patientName,
    required this.waitingSince,
  });

  final String patientName;
  final DateTime waitingSince;

  String _durationLabel() {
    final d = DateTime.now().difference(waitingSince);
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    if (m > 0) {
      return 'En attente depuis $m min ${s.toString().padLeft(2, '0')} sec';
    }
    return 'En attente depuis $s sec';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: HeadsAppColors.success.withValues(alpha: 0.14),
        border: Border(
          left: BorderSide(color: HeadsAppColors.success, width: 5),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PulsingGreenDot(),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$patientName est dans la salle d\'attente',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: HeadsAppColors.success,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _durationLabel(),
                  style: const TextStyle(
                    fontSize: 13,
                    color: HeadsAppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PulsingGreenDot extends StatefulWidget {
  const _PulsingGreenDot();

  @override
  State<_PulsingGreenDot> createState() => _PulsingGreenDotState();
}

class _PulsingGreenDotState extends State<_PulsingGreenDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(
        begin: 0.45,
        end: 1,
      ).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
      child: Container(
        width: 14,
        height: 14,
        margin: const EdgeInsets.only(top: 2),
        decoration: const BoxDecoration(
          color: HeadsAppColors.success,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

DateTime? _teleconsultLocalFromMessage(Map<String, dynamic> msg) {
  final p = msg['payload'];
  Map<String, dynamic> map = {};
  if (p is Map<String, dynamic>) {
    map = p;
  } else if (p is Map) {
    map = Map<String, dynamic>.from(p);
  }
  final iso = map['scheduledAt'];
  if (iso is String && iso.isNotEmpty) {
    final utc = DateTime.tryParse(iso);
    if (utc != null) return utc.toLocal();
  }
  final content = msg['content'] as String? ?? '';
  final re = RegExp(
    r'(\d{2})/(\d{2})/(\d{4})\s+à\s+(\d{2}):(\d{2})',
    caseSensitive: false,
  );
  final m = re.firstMatch(content);
  if (m == null) return null;
  final day = int.tryParse(m.group(1)!);
  final month = int.tryParse(m.group(2)!);
  final year = int.tryParse(m.group(3)!);
  final hour = int.tryParse(m.group(4)!);
  final minute = int.tryParse(m.group(5)!);
  if (day == null ||
      month == null ||
      year == null ||
      hour == null ||
      minute == null) {
    return null;
  }
  return DateTime(year, month, day, hour, minute);
}

enum _MessageUrgency { normal, medium, urgent }
