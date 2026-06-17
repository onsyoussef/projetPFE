import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'espace_patient_page.dart';
import 'headsapp_theme.dart';
import 'prescription_history/prescription_history_bottom_sheet.dart';
import 'prescription_history/prescription_history_strings.dart';
import 'providers/call_provider.dart';
import 'widgets/heads_form_cta_button.dart';
import 'widgets/call_log_bubble.dart';
import 'widgets/patient_prescription_message_card.dart';
import 'widgets/waiting_room_banner.dart';
import 'widgets/waiting_room_screen.dart';
import 'utils/chat_attachment_open.dart';
import 'utils/patient_ui_utils.dart';
import 'services/api_service.dart';
import 'services/patient_reply_notification_service.dart';
import 'services/webrtc_service.dart';
import 'services/call_chat_context.dart';
import 'teleconsult_first_request_letter.dart';
import 'utils/waiting_room_browser_notify.dart';

class _WaitingRoomBannerData {
  const _WaitingRoomBannerData({
    required this.consultationTime,
    required this.canEnter,
  });
  final DateTime consultationTime;
  final bool canEnter;
}

class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    required this.patientId,
    required this.doctorId,
    required this.doctorName,
    this.doctorPhotoPath,
    this.currentUserFromType = 'patient',
  });

  final String patientId;
  final String doctorId;
  final String doctorName;
  final String? doctorPhotoPath;
  // Utilisé pour savoir si les messages reçus viennent "de l'autre côté".
  // Ex: côté patient => incoming messages = fromType 'doctor'.
  final String currentUserFromType;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with WidgetsBindingObserver {
  String get _doctorDisplayName => readableDoctorName(widget.doctorName);

  String? _conversationId;
  bool _loading = true;
  String? _error;
  String? _doctorStatus; // 'available' | 'busy' | 'unavailable'
  String? _doctorAbsenceMessage;
  bool _doctorAutoReplyEnabled = false;
  final List<Map<String, dynamic>> _messages = [];
  final TextEditingController _textController = TextEditingController();
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  PlatformFile? _pendingVoiceFile;
  PlatformFile? _pendingAttachmentFile;

  Timer? _messagePollTimer;
  Timer? _doctorStatusPollTimer;
  /// Rafraîchissement bandeau / fenêtre J-10 (compte à rebours).
  Timer? _patientCallWindowTimer;
  Timer? _waitingRoomOpenKickTimer;
  StreamSubscription<Map<String, dynamic>>? _consultationSocketSub;
  StreamSubscription<Map<String, dynamic>>? _callSummarySocketSub;
  /// Une entrée par créneau (ISO UTC) : notification J-10 déjà affichée.
  final Set<String> _announcedWaitingRoomSlots = {};
  static const Duration _waitingRoomLead = Duration(minutes: 10);
  static const Duration _waitingRoomAfterGrace = Duration(minutes: 10);
  String _patientDisplayName = 'Patient';
  String? _doctorSpecialty;
  String? _doctorPhotoPath;
  bool _waitingRoomRestored = false;
  StreamSubscription<bool>? _socketConnSub;
  StreamSubscription<String>? _chatActivitySub;
  StreamSubscription<Map<String, dynamic>>? _chatSessionClosedSub;
  StreamSubscription<Map<String, dynamic>>? _chatSessionReopenedSub;
  StreamSubscription<Map<String, dynamic>>? _chatTypingSub;
  StreamSubscription<Map<String, dynamic>>? _chatMessagesReadSub;
  StreamSubscription<Map<String, dynamic>>? _doctorStatusUpdatedSub;
  bool _pollInFlight = false;
  bool _sessionCloture = false;
  bool _teleFormStartedLocally = false;
  String? _lastChatClosedMarkerSeen;
  /// Premier frame gris puis animation vers le blanc après réouverture de session.
  bool _patientInputSurfaceGreyForReopenAnim = false;
  bool _peerTyping = false;
  Timer? _typingPauseTimer;
  Timer? _typingEmitEndTimer;
  final ScrollController _chatScrollController = ScrollController();
  /// Évite double envoi (double clic / Flutter Web / concurrence avec le polling).
  bool _textSendInFlight = false;
  // Polling plus doux pour réduire la charge réseau et éviter la latence d'envoi.
  static const Duration _pollInterval = Duration(milliseconds: 700);
  static const Duration _doctorStatusPollInterval = Duration(seconds: 10);

  // Notification sonore pour les nouveaux messages reçus.
  late final AudioPlayer _notificationPlayer;
  bool _notificationInFlight = false;

  // Suppression anti-"double son" : quand l'utilisateur envoie un message,
  // on évite de jouer le son sur l'écho de ce même message qui revient via le polling.
  DateTime? _outgoingSuppressionUntil;
  String _lastOutgoingFromType = 'patient';

  // Petit bip public. Si le son ne se lit pas (réseau/cors), on restera silencieux.
  static const String _notificationSoundUrl =
      'https://actions.google.com/sounds/v1/alarms/beep_short.ogg';
  late final CallProvider _callProvider;

  bool get _hasScheduledTeleconsultMessage =>
      _messages.any((m) {
        final t = (m['type'] as String? ?? '');
        return t == 'teleconsult_scheduled' || t == 'rdv_teleconsult_programme';
      });

  /// J-10 → J+10 : période où le patient peut entrer en salle d’attente.
  bool _isInWaitingRoomNotifiedWindow(DateTime consult, DateTime now) {
    final open = consult.subtract(_waitingRoomLead);
    final end = consult.add(_waitingRoomAfterGrace);
    return !now.isBefore(open) && !now.isAfter(end);
  }

  /// Affiche la salle d'attente uniquement pendant la fenêtre J-10 -> J+10.
  bool _bannerVisibleForConsult(DateTime consult, DateTime now) {
    return _isInWaitingRoomNotifiedWindow(consult, now);
  }

  /// Prochain créneau `teleconsult_scheduled` pas encore expiré (après J+10).
  DateTime? _nextScheduledConsultLocal() {
    final now = DateTime.now();
    DateTime? best;
    for (final m in _messages) {
      final dt = _ChatPageState._scheduledConsultLocalFromMessage(m);
      if (dt == null) continue;
      if (now.isAfter(dt.add(_waitingRoomAfterGrace))) continue;
      if (best == null || dt.isBefore(best)) best = dt;
    }
    return best;
  }

  _WaitingRoomBannerData? _waitingRoomBannerData() {
    if (_patientInActiveCall) return null;
    final consult = _nextScheduledConsultLocal();
    if (consult == null) return null;
    final now = DateTime.now();
    if (!_bannerVisibleForConsult(consult, now)) return null;
    return _WaitingRoomBannerData(
      consultationTime: consult,
      canEnter: _isInWaitingRoomNotifiedWindow(consult, now),
    );
  }

  /// Message SnackBar si l’utilisateur tente d’ouvrir la salle avant J-10.
  String _snackTextWaitingRoomOpensIn(DateTime consult) {
    final now = DateTime.now();
    final opensAt = consult.subtract(_waitingRoomLead);
    final remaining = opensAt.difference(now);
    final hh = opensAt.hour.toString().padLeft(2, '0');
    final mm = opensAt.minute.toString().padLeft(2, '0');
    if (!remaining.isNegative) {
      final h = remaining.inHours;
      final min = remaining.inMinutes.remainder(60);
      if (h > 0) {
        return 'La salle d\'attente ouvre dans ${h}h ${min}min (à $hh:$mm).';
      }
      if (min > 0) {
        return 'La salle d\'attente ouvre dans ${min}min (à $hh:$mm).';
      }
      final s = remaining.inSeconds.remainder(60).clamp(0, 59);
      return 'La salle d\'attente ouvre dans ${s}s (à $hh:$mm).';
    }
    return 'La salle d\'attente s\'ouvre 10 minutes avant l\'heure de la téléconsultation.';
  }

  DateTime? _displayConsultationTimeForWaitingScreen() {
    final d = _waitingRoomBannerData();
    if (d == null || !d.canEnter) return null;
    return d.consultationTime;
  }

  void _rescheduleWaitingRoomKickTimer() {
    _waitingRoomOpenKickTimer?.cancel();
    _waitingRoomOpenKickTimer = null;
    final now = DateTime.now();
    Duration? shortest;
    for (final m in _messages) {
      final dt = _ChatPageState._scheduledConsultLocalFromMessage(m);
      if (dt == null) continue;
      if (now.isAfter(dt.add(_waitingRoomAfterGrace))) continue;
      final open = dt.subtract(_waitingRoomLead);
      if (now.isBefore(open)) {
        final d = open.difference(now);
        final prev = shortest;
        if (prev == null || d < prev) {
          shortest = d;
        }
      }
    }
    final delay = shortest;
    if (delay != null && delay > Duration.zero) {
      _waitingRoomOpenKickTimer = Timer(delay, () {
        if (!mounted) return;
        _announceWaitingRoomEntry();
        setState(() {});
        _rescheduleWaitingRoomKickTimer();
      });
    }
  }

  void _announceWaitingRoomEntry() {
    final consult = _nextScheduledConsultLocal();
    if (consult == null) return;
    if (!_isInWaitingRoomNotifiedWindow(consult, DateTime.now())) return;
    final key = consult.toUtc().toIso8601String();
    if (_announcedWaitingRoomSlots.contains(key)) return;
    _announcedWaitingRoomSlots.add(key);

    final fmt = TimeOfDay.fromDateTime(consult);
    final hh = fmt.hour.toString().padLeft(2, '0');
    final mm = fmt.minute.toString().padLeft(2, '0');
    final timeLabel = '$hh:$mm';

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Votre consultation avec $_doctorDisplayName commence à $timeLabel '
            '(dans 10 minutes). Vous pouvez entrer dans la salle d\'attente.',
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
        ),
      );
    }
    notifyWaitingRoomBrowser(
      doctorName: _doctorDisplayName,
      timeLabel: timeLabel,
    );
  }

  void _onConsultationSocketEvent() {
    if (!mounted) return;
    final c = _nextScheduledConsultLocal();
    if (c != null && _isInWaitingRoomNotifiedWindow(c, DateTime.now())) {
      _announceWaitingRoomEntry();
    }
    _rescheduleWaitingRoomKickTimer();
    setState(() {});
  }

  void _syncWaitingRoomAfterMessages() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final c = _nextScheduledConsultLocal();
      if (c != null && _isInWaitingRoomNotifiedWindow(c, DateTime.now())) {
        _announceWaitingRoomEntry();
      }
      _rescheduleWaitingRoomKickTimer();
    });
  }

  void _attachConsultationSocketListener() {
    _consultationSocketSub?.cancel();
    _consultationSocketSub = WebRtcService.instance.consultationEvents.listen((ev) async {
      final cid = ev['conversationId']?.toString() ?? '';
      if (cid.isEmpty || cid != _conversationId) return;
      await _loadMessages(awaitTeleFormModal: false);
      if (!mounted) return;
      if (ev['event'] == 'cancelled') {
        await _checkWaitingRoomCancelled();
      }
      _onConsultationSocketEvent();
    });

    _callSummarySocketSub?.cancel();
    _callSummarySocketSub = WebRtcService.instance.callSummaryEvents.listen((data) async {
      final cid = data['conversationId']?.toString() ?? '';
      if (cid.isEmpty || cid != _conversationId) return;
      await _loadNewMessages();
      if (!mounted) return;
      setState(() {});
    });
  }

  bool get _patientInActiveCall {
    final s = _callProvider.currentState;
    return s == CallState.sonnerie ||
        s == CallState.enCours ||
        s == CallState.enAppel;
  }

  String? _resolvedDoctorPhotoUrl() {
    final p = _doctorPhotoPath;
    if (p == null || p.trim().isEmpty) return null;
    final u = ApiService.resolveMediaUrl(p);
    return u.isEmpty ? null : u;
  }

  Future<void> _persistWaitingRoomPrefs() async {
    final cid = _conversationId;
    if (cid == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('waiting_room_$cid', 'true');
  }

  Future<void> _clearWaitingRoomPrefs() async {
    final cid = _conversationId;
    if (cid == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('waiting_room_$cid');
  }

  Future<void> _leaveWaitingRoom() async {
    final cid = _conversationId;
    var shouldNotifyServer = false;
    if (cid != null) {
      final prefs = await SharedPreferences.getInstance();
      shouldNotifyServer = prefs.getString('waiting_room_$cid') == 'true';
    }
    await _clearWaitingRoomPrefs();
    if (cid != null && shouldNotifyServer) {
      WebRtcService.instance.notifyPatientLeftWaitingRoom(
        conversationId: cid,
        patientId: widget.patientId,
        doctorId: widget.doctorId,
      );
    }
  }

  Future<void> _enterWaitingRoom() async {
    await _openWaitingRoomScreen(restore: false);
  }

  Future<void> _openWaitingRoomScreen({required bool restore}) async {
    final cid = _conversationId;
    if (cid == null) return;
    final t = _displayConsultationTimeForWaitingScreen();
    if (t == null) {
      if (mounted) {
        final consult = _nextScheduledConsultLocal();
        final text = consult == null
            ? 'Aucune téléconsultation planifiée.'
            : _snackTextWaitingRoomOpensIn(consult);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(text),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    if (!restore) {
      await _persistWaitingRoomPrefs();
    }
    WebRtcService.instance.notifyPatientEnteredWaitingRoom(
      conversationId: cid,
      patientId: widget.patientId,
      doctorId: widget.doctorId,
      patientName: _patientDisplayName,
    );
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => WaitingRoomScreen(
          consultationTime: t,
          doctorName: _doctorDisplayName,
          doctorAvatarUrl: _resolvedDoctorPhotoUrl(),
          onLeaveRoom: _leaveWaitingRoom,
          onSyncUnload: () {
            WebRtcService.instance.notifyPatientLeftWaitingRoom(
              conversationId: cid,
              patientId: widget.patientId,
              doctorId: widget.doctorId,
            );
          },
          onConsultationStillValid: () async {
            await _loadMessages(awaitTeleFormModal: false);
            if (!mounted) return true;
            return _hasScheduledTeleconsultMessage;
          },
          onConsultationInvalidated: _leaveWaitingRoom,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _maybeRestoreWaitingRoom() async {
    if (_waitingRoomRestored) return;
    final cid = _conversationId;
    if (cid == null) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString('waiting_room_$cid') != 'true') return;
    if (!_hasScheduledTeleconsultMessage) {
      await _clearWaitingRoomPrefs();
      return;
    }
    if (_displayConsultationTimeForWaitingScreen() == null) {
      await _clearWaitingRoomPrefs();
      return;
    }
    _waitingRoomRestored = true;
    await _openWaitingRoomScreen(restore: true);
  }

  Future<void> _checkWaitingRoomCancelled() async {
    final cid = _conversationId;
    if (cid == null) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString('waiting_room_$cid') != 'true') return;
    if (_hasScheduledTeleconsultMessage) return;
    await _leaveWaitingRoom();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La téléconsultation planifiée n’est plus disponible.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _onCallProviderChanged() {
    if (mounted) setState(() {});
  }

  /// Icônes appel (patient) : toujours désactivées — seul le médecin initie.
  Widget _patientCallBarIconButton({
    required IconData icon,
  }) {
    const tooltip = 'L\'appel est réservé au médecin';
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: null,
        mouseCursor: SystemMouseCursors.forbidden,
        style: IconButton.styleFrom(
          foregroundColor: Colors.white,
          disabledForegroundColor: Colors.white.withValues(alpha: 0.38),
        ),
        icon: Icon(icon),
      ),
    );
  }



  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (kIsWeb) return;
    if (state == AppLifecycleState.resumed) {
      WebRtcService.instance.emitPatientAppLifecycle(true);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      WebRtcService.instance.emitPatientAppLifecycle(false);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _doctorPhotoPath = widget.doctorPhotoPath;
    _callProvider = CallProvider(webRtcService: WebRtcService.instance);
    _callProvider.addListener(_onCallProviderChanged);
    CallChatContext.register(
      doctorId: widget.doctorId,
      patientId: widget.patientId,
      isPatientSide: true,
      onReloadMessages: () async {
        await _loadMessages(awaitTeleFormModal: false);
        if (mounted) setState(() {});
      },
    );

    _notificationPlayer = AudioPlayer();

    // Permet de restaurer le chat après un refresh web.
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('patientId', widget.patientId);
      await prefs.setString('lastRoute', 'chat');
      await prefs.setString('chatDoctorId', widget.doctorId);
      await prefs.setString('chatDoctorName', _doctorDisplayName);
      final ph = widget.doctorPhotoPath?.trim();
      if (ph != null && ph.isNotEmpty) {
        await prefs.setString('chatDoctorPhotoPath', ph);
      } else {
        await prefs.remove('chatDoctorPhotoPath');
      }
      if (mounted) {
        setState(() {
          _patientDisplayName = readablePatientName(prefs.getString('patientName'));
        });
      }
    }();
    _socketConnSub = WebRtcService.instance.socketConnected.listen((_) {
      if (mounted) setState(() {});
    });
    WebRtcService.instance.connectSocket(selfUserId: widget.patientId);
    _initConversation();
    _loadDoctorStatus();
    _subscribeDoctorStatusUpdates();
    _startDoctorStatusPolling();
    _patientCallWindowTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_waitingRoomBannerData() != null) {
        setState(() {});
      }
    });
  }

  Future<void> _loadDoctorStatus() async {
    try {
      final data = await ApiService.getDoctor(widget.doctorId);
      if (mounted) {
        final nextStatus = data['status'] as String? ?? 'available';
        final nextAbsenceMessage =
            (data['absenceMessage'] as String?)?.trim().isEmpty ?? true
                ? null
                : (data['absenceMessage'] as String).trim();
        final nextAutoReplyEnabled = data['autoReplyEnabled'] == true;
        final nextSpecialty = readableDecryptedField(
          data['specialty']?.toString(),
        );
        final nextPhotoPath = data['photoPath']?.toString();
        final hasChanged = _doctorStatus != nextStatus ||
            _doctorAbsenceMessage != nextAbsenceMessage ||
            _doctorAutoReplyEnabled != nextAutoReplyEnabled ||
            _doctorSpecialty != nextSpecialty ||
            _doctorPhotoPath != nextPhotoPath;
        if (!hasChanged) return;
        setState(() {
          _doctorStatus = nextStatus;
          _doctorAbsenceMessage = nextAbsenceMessage;
          _doctorAutoReplyEnabled = nextAutoReplyEnabled;
          _doctorSpecialty = nextSpecialty;
          _doctorPhotoPath = nextPhotoPath;
        });
      }
    } catch (_) {}
  }

  void _startDoctorStatusPolling() {
    _doctorStatusPollTimer?.cancel();
    _doctorStatusPollTimer = Timer.periodic(_doctorStatusPollInterval, (_) {
      if (!mounted) return;
      _loadDoctorStatus();
    });
  }

  void _subscribeChatActivity() {
    _chatActivitySub?.cancel();
    _chatActivitySub =
        WebRtcService.instance.chatActivityConversationIds.listen((cid) {
      if (!mounted || _conversationId == null) return;
      if (cid == _conversationId) {
        _loadMessages(awaitTeleFormModal: false);
      }
    });
  }

  void _subscribeDoctorStatusUpdates() {
    _doctorStatusUpdatedSub?.cancel();
    _doctorStatusUpdatedSub =
        WebRtcService.instance.doctorStatusUpdatedEvents.listen((data) {
      if (!mounted) return;
      final payloadDoctorId = data['doctorId']?.toString() ?? '';
      if (payloadDoctorId.isNotEmpty && payloadDoctorId != widget.doctorId) {
        return;
      }
      final nextStatus = data['status']?.toString() ?? 'available';
      final nextAbsenceMessage =
          (data['absenceMessage'] as String?)?.trim().isEmpty ?? true
              ? null
              : (data['absenceMessage'] as String).trim();
      final nextAutoReplyEnabled = data['autoReplyEnabled'] == true;
      final nextPhotoPath = data['photoPath']?.toString();
      final hasChanged = _doctorStatus != nextStatus ||
          _doctorAbsenceMessage != nextAbsenceMessage ||
          _doctorAutoReplyEnabled != nextAutoReplyEnabled ||
          _doctorPhotoPath != nextPhotoPath;
      if (!hasChanged) return;
      setState(() {
        _doctorStatus = nextStatus;
        _doctorAbsenceMessage = nextAbsenceMessage;
        _doctorAutoReplyEnabled = nextAutoReplyEnabled;
        _doctorPhotoPath = nextPhotoPath;
      });
    });
  }

  Future<void> _initConversation() async {
    try {
      final data = await ApiService.createConversation(
        patientId: widget.patientId,
        doctorId: widget.doctorId,
      );
      _conversationId = data['conversationId'] as String?;
      CallChatContext.updateConversationId(_conversationId);
      PatientReplyNotificationService.setSuppressedConversation(_conversationId);
      WebRtcService.instance.joinConversationRoom(_conversationId);
      _attachConsultationSocketListener();
      _subscribeChatActivity();
      _subscribeChatSessionSockets();
      // Premier chargement sans modal pour savoir l'état à l'entrée.
      await _loadMessages(awaitTeleFormModal: false);
      await _maybeShowTeleFormModal();
      if (mounted) {
        await _maybeRestoreWaitingRoom();
      }
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }

    if (mounted) {
      _startMessagePolling();
    }
  }

  void _startMessagePolling() {
    _messagePollTimer?.cancel();
    _messagePollTimer = Timer.periodic(_pollInterval, (_) async {
      if (!mounted) return;
      if (_conversationId == null) return;
      if (_pollInFlight) return;
      if (_textSendInFlight) return;

      _pollInFlight = true;
      try {
        final hasNewMessages = await _loadNewMessages();
        if (hasNewMessages && mounted) setState(() {});

        // Stop polling if chat is closed to reduce load.
        if (_isChatClosed && _messagePollTimer != null) {
          _messagePollTimer?.cancel();
          _messagePollTimer = null;
        }
      } catch (_) {
        // On ignore : le prochain tick réessaiera.
      } finally {
        _pollInFlight = false;
      }
    });
  }

  String? _extractObjectId(dynamic value) {
    if (value == null) return null;
    if (value is String) {
      final match = RegExp(r'[0-9a-fA-F]{24}').firstMatch(value);
      return match?.group(0);
    }
    final s = value.toString();
    final match = RegExp(r'[0-9a-fA-F]{24}').firstMatch(s);
    return match?.group(0);
  }

  static String _formatTeleconsultPatient(DateTime stored) {
    final l = stored.toLocal();
    final dd = l.day.toString().padLeft(2, '0');
    final mm = l.month.toString().padLeft(2, '0');
    final hh = l.hour.toString().padLeft(2, '0');
    final min = l.minute.toString().padLeft(2, '0');
    return 'Votre téléconsultation est prévue le $dd/$mm/${l.year} à $hh:$min. Merci de vous connecter quelques minutes à l’avance.';
  }

  /// Payload JSON parfois reçu en `Map<dynamic, dynamic>` : normalisation pour lire `scheduledAt`.
  static Map<String, dynamic> _payloadMap(Map<String, dynamic> msg) {
    final p = msg['payload'];
    if (p == null) return {};
    if (p is Map<String, dynamic>) return p;
    if (p is Map) return Map<String, dynamic>.from(p);
    return {};
  }

  /// Interprète [scheduledAt] (String ISO, DateTime, Map Mongo `$date`, etc.).
  static DateTime? _parseScheduledAtToLocal(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw.toLocal();
    if (raw is String && raw.isNotEmpty) {
      final utc = DateTime.tryParse(raw);
      if (utc != null) return utc.toLocal();
      return null;
    }
    if (raw is Map) {
      final inner = raw[r'$date'];
      if (inner != null) return _parseScheduledAtToLocal(inner);
    }
    final s = raw.toString();
    if (s.isNotEmpty && s != 'null') {
      final utc = DateTime.tryParse(s);
      if (utc != null) return utc.toLocal();
    }
    return null;
  }

  /// Date/heure locales de la téléconsultation (ISO dans le payload ou repli sur le texte du message).
  static DateTime? _teleconsultLocalDateTime(Map<String, dynamic> msg) {
    final map = _payloadMap(msg);
    final fromPayload = _parseScheduledAtToLocal(map['scheduledAt']);
    if (fromPayload != null) return fromPayload;
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

  /// Créneau issu du message système `rdv_teleconsult_programme` (date + heure wall-clock).
  static DateTime? _rdvProgrammeLocalFromMessage(Map<String, dynamic> msg) {
    if ((msg['type'] as String? ?? '').trim() != 'rdv_teleconsult_programme') {
      return null;
    }
    final p = msg['payload'];
    if (p is! Map) return null;
    final map = Map<String, dynamic>.from(p);
    final ds = map['date']?.toString();
    final hs = map['heure']?.toString().trim();
    if (ds == null || hs == null || ds.isEmpty || hs.isEmpty) return null;
    final dm = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(ds);
    final hm = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(hs);
    if (dm == null || hm == null) return null;
    final y = int.tryParse(dm.group(1)!);
    final mo = int.tryParse(dm.group(2)!);
    final d = int.tryParse(dm.group(3)!);
    final hh = int.tryParse(hm.group(1)!);
    final mm = int.tryParse(hm.group(2)!);
    if (y == null || mo == null || d == null || hh == null || mm == null) {
      return null;
    }
    return DateTime(y, mo, d, hh, mm);
  }

  static DateTime? _scheduledConsultLocalFromMessage(Map<String, dynamic> m) {
    return _teleconsultLocalDateTime(m) ?? _rdvProgrammeLocalFromMessage(m);
  }

  /// Extrait `payload.event` même si la map est typée `Map<dynamic, dynamic>` (JSON).
  String? _payloadEvent(Map<String, dynamic> m) {
    final p = m['payload'];
    if (p == null || p is! Map) return null;
    final map = Map<String, dynamic>.from(p);
    final ev = map['event'];
    if (ev == null) return null;
    return ev.toString();
  }

  /// Ces messages restent dans l’historique (logique métier) mais ne s’affichent pas dans la discussion.
  /// L’info est donnée par SnackBar / notifications (clôture, formulaire, répondre par message).
  bool _hideMessageFromPatientDiscussion(Map<String, dynamic> msg) {
    final type = msg['type'] as String? ?? '';
    if (type == 'form_teleconsult') return true;
    if (type == 'system' && _payloadEvent(msg) == 'reply_by_message') {
      return true;
    }
    return false;
  }

  Future<bool> _loadNewMessages() async {
    if (_conversationId == null) return false;

    // Si on n'a pas encore d'historique chargé, on fait un chargement complet.
    if (_messages.isEmpty) {
      await _loadMessages(awaitTeleFormModal: false);
      return _messages.isNotEmpty;
    }

    final afterId = _extractObjectId(_messages.last['_id']);
    if (afterId == null || afterId.isEmpty) {
      // Fallback : si le dernier id n'est pas exploitable, on recharge tout.
      await _loadMessages(awaitTeleFormModal: false);
      return _messages.isNotEmpty;
    }

    final afterBundle = await ApiService.getMessagesAfter(
      conversationId: _conversationId!,
      afterId: afterId,
    );
    final rawAfter = afterBundle['messages'];
    final newMessages = rawAfter is List
        ? rawAfter
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList()
        : <Map<String, dynamic>>[];
    final ss = afterBundle['sessionStatus']?.toString() ?? 'open';
    if (mounted) {
      setState(() => _sessionCloture = ss == 'cloture');
    }

    if (newMessages.isEmpty) return false;

    // Ne pas réinsérer un message déjà présent (course entre _loadMessages et le poll).
    final existingIds = <String>{
      for (final m in _messages)
        if (_extractObjectId(m['_id']) != null) _extractObjectId(m['_id'])!,
    };
    final filteredNew = <Map<String, dynamic>>[];
    for (final raw in newMessages) {
      final m = Map<String, dynamic>.from(raw);
      final id = _extractObjectId(m['_id']);
      if (id != null && existingIds.contains(id)) continue;
      if (id != null) existingIds.add(id);
      filteredNew.add(m);
    }
    if (filteredNew.isEmpty) return false;

    final hasReplyByMessageEvent = filteredNew.any((m) {
      return _payloadEvent(m) == 'reply_by_message';
    });
    final hasChatClosedEvent = filteredNew.any(
      (m) => (m['type'] as String? ?? '') == 'chat_closed',
    );
    final hasChatReopenedEvent = filteredNew.any(
      (m) => (m['type'] as String? ?? '') == 'chat_reopened',
    );

    _messages.addAll(filteredNew);
    _syncTeleFormCycleStateWithMessages();
    // Ne pas bloquer : le bottom sheet (si nécessaire) s'ouvrira quand même.
    _maybeShowTeleFormModal();

    final now = DateTime.now();
    final shouldNotify = filteredNew.any((m) {
      final fromType = m['fromType'] as String? ?? 'system';
      if (fromType != 'patient' && fromType != 'doctor') return false;

      // Si c'est notre message à nous (envoi tout récent), on coupe le son.
      final suppressed = _outgoingSuppressionUntil != null &&
          now.isBefore(_outgoingSuppressionUntil!) &&
          fromType == _lastOutgoingFromType;

      return !suppressed;
    });

    if (shouldNotify) {
      _playNotificationSound();
    }

    if (hasReplyByMessageEvent && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Le médecin a choisi de vous répondre par message.'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 3),
        ),
      );
    }
    if (hasChatClosedEvent && mounted) {
      setState(() => _sessionCloture = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Le médecin a clôturé la discussion. Vous ne pouvez plus envoyer de messages dans ce chat.',
          ),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 4),
        ),
      );
    }
    if (hasChatReopenedEvent && mounted) {
      setState(() {
        _sessionCloture = false;
        _patientInputSurfaceGreyForReopenAnim = true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _patientInputSurfaceGreyForReopenAnim = false);
        }
      });
    }
    if (_conversationId != null && _messages.isNotEmpty) {
      await PatientReplyNotificationService.syncCursorToLatestMessage(
        patientId: widget.patientId,
        conversationId: _conversationId!,
        messages: _messages,
      );
    }
    unawaited(_markPatientReadQuiet());
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkWaitingRoomCancelled();
        _syncWaitingRoomAfterMessages();
        _scrollChatToEnd();
      });
    }
    return true;
  }

  Future<void> _markPatientReadQuiet() async {
    if (_conversationId == null) return;
    try {
      await ApiService.markMessagesRead(
        conversationId: _conversationId!,
        readerFromType: 'patient',
      );
    } catch (_) {}
  }

  void _scrollChatToEnd() {
    if (!_chatScrollController.hasClients) return;
    _chatScrollController.animateTo(
      _chatScrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  void _onPatientTextChangedTyping(String _) {
    if (_conversationId == null || _sessionCloture) return;
    WebRtcService.instance.emitChatTyping(
      conversationId: _conversationId!,
      typing: true,
      role: 'patient',
    );
    _typingEmitEndTimer?.cancel();
    _typingEmitEndTimer = Timer(const Duration(milliseconds: 1200), () {
      if (_conversationId == null) return;
      WebRtcService.instance.emitChatTyping(
        conversationId: _conversationId!,
        typing: false,
        role: 'patient',
      );
    });
  }

  void _subscribeChatSessionSockets() {
    _chatSessionClosedSub?.cancel();
    _chatSessionClosedSub =
        WebRtcService.instance.chatSessionClosedEvents.listen((data) async {
      if (!mounted || _conversationId == null) return;
      if (data['conversationId']?.toString() != _conversationId) return;
      setState(() => _sessionCloture = true);
      await _loadMessages(awaitTeleFormModal: false);
      if (mounted) setState(() {});
    });
    _chatSessionReopenedSub?.cancel();
    _chatSessionReopenedSub =
        WebRtcService.instance.chatSessionReopenedEvents.listen((data) async {
      if (!mounted || _conversationId == null) return;
      if (data['conversationId']?.toString() != _conversationId) return;
      setState(() {
        _sessionCloture = false;
        _patientInputSurfaceGreyForReopenAnim = true;
      });
      await _loadMessages(awaitTeleFormModal: false);
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _patientInputSurfaceGreyForReopenAnim = false);
        }
      });
    });
    _chatTypingSub?.cancel();
    _chatTypingSub = WebRtcService.instance.chatTypingEvents.listen((data) {
      if (!mounted || _conversationId == null) return;
      if (data['conversationId']?.toString() != _conversationId) return;
      if (data['role']?.toString() != 'doctor') return;
      final typing = data['typing'] == true;
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
    _chatMessagesReadSub?.cancel();
    _chatMessagesReadSub =
        WebRtcService.instance.chatMessagesReadEvents.listen((data) {
      if (!mounted || _conversationId == null) return;
      if (data['conversationId']?.toString() != _conversationId) return;
      if (data['readerFromType']?.toString() != 'doctor') return;
      final iso = data['readAt']?.toString();
      setState(() {
        for (final m in _messages) {
          if (m['fromType'] == 'patient' && m['readAt'] == null) {
            m['readAt'] = iso;
          }
        }
      });
    });
  }

  DateTime? _patientMessageCreatedAt(Map<String, dynamic> m) {
    final raw = m['createdAt'];
    if (raw is String) return DateTime.tryParse(raw)?.toLocal();
    return null;
  }

  String _formatPatientDateHeader(DateTime day) {
    final now = DateTime.now();
    final t0 = DateTime(now.year, now.month, now.day);
    final y0 = t0.subtract(const Duration(days: 1));
    final d0 = DateTime(day.year, day.month, day.day);
    if (d0 == t0) return 'Aujourd\'hui';
    if (d0 == y0) return 'Hier';
    return DateFormat('dd/MM/yyyy').format(day);
  }

  bool _showDateBeforePatientIndex(int index) {
    final msg = _messages[index];
    if (_hideMessageFromPatientDiscussion(msg)) return false;
    final dt = _patientMessageCreatedAt(msg);
    if (dt == null) return false;
    final day = DateTime(dt.year, dt.month, dt.day);
    for (var j = index - 1; j >= 0; j--) {
      final prev = _messages[j];
      if (_hideMessageFromPatientDiscussion(prev)) continue;
      final pdt = _patientMessageCreatedAt(prev);
      if (pdt == null) return true;
      final pday = DateTime(pdt.year, pdt.month, pdt.day);
      return day != pday;
    }
    return true;
  }

  void _markOutgoingMessage({required String fromType}) {
    _lastOutgoingFromType = fromType;
    _outgoingSuppressionUntil = DateTime.now().add(const Duration(seconds: 2));
  }

  Future<void> _playNotificationSound() async {
    if (!mounted) return;
    if (_notificationInFlight) return;
    _notificationInFlight = true;
    try {
      await _notificationPlayer.stop();
      await _notificationPlayer.play(UrlSource(_notificationSoundUrl));
    } catch (_) {
      // Sur Flutter Web, la lecture audio peut être bloquée si pas de "user gesture".
      // On ignore et on continue.
    } finally {
      _notificationInFlight = false;
    }
  }

  Future<void> _loadMessages({bool awaitTeleFormModal = true}) async {
    if (_conversationId == null) return;
    final data = await ApiService.getMessages(conversationId: _conversationId!);
    final list = data['messages'] as List?;
    _messages.clear();
    if (list != null) {
      final seen = <String>{};
      for (final raw in list) {
        final m = Map<String, dynamic>.from(raw as Map);
        final id = _extractObjectId(m['_id']);
        if (id != null) {
          if (seen.contains(id)) continue;
          seen.add(id);
        }
        _messages.add(m);
      }
    }
    _syncTeleFormCycleStateWithMessages();
    final ss = data['sessionStatus']?.toString() ?? 'open';
    _sessionCloture = ss == 'cloture';
    // Pendant le polling, éviter de bloquer l'UI si un bottom sheet devait s'ouvrir.
    if (awaitTeleFormModal) {
      await _maybeShowTeleFormModal();
    } else {
      // Ne pas attendre : le modal s'affichera quand même si nécessaire.
      _maybeShowTeleFormModal();
    }
    if (_conversationId != null && _messages.isNotEmpty) {
      await PatientReplyNotificationService.syncCursorToLatestMessage(
        patientId: widget.patientId,
        conversationId: _conversationId!,
        messages: _messages,
      );
    }
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkWaitingRoomCancelled();
        _syncWaitingRoomAfterMessages();
        _scrollChatToEnd();
      });
    }
    unawaited(_markPatientReadQuiet());
  }

  bool get _hasHistory {
    // On considère qu'il y a un historique dès qu'il existe un message
    // non système (patient ou médecin) autre que la simple question initiale.
    return _messages.any((m) {
      final fromType = m['fromType'] as String? ?? 'system';
      final type = m['type'] as String? ?? '';
      if (type == 'question_physique') return false;
      return fromType != 'system';
    });
  }

  /// Clôture **du dernier** flux téléconsult (après le dernier formulaire / demande).
  /// Évite de bloquer l’envoi à cause d’une ancienne clôture avant un nouveau formulaire.
  bool get _isChatClosed {
    var lastTeleIndex = -1;
    for (var i = 0; i < _messages.length; i++) {
      final type = _messages[i]['type'] as String? ?? '';
      final fromType = _messages[i]['fromType'] as String? ?? '';
      if (fromType == 'system' &&
          (type == 'request_teleconsult' || type == 'form_teleconsult')) {
        lastTeleIndex = i;
      }
    }
    if (lastTeleIndex == -1) return false;
    var isClosed = false;
    for (var j = lastTeleIndex + 1; j < _messages.length; j++) {
      final type = _messages[j]['type'] as String? ?? '';
      if (type == 'chat_closed') isClosed = true;
      if (type == 'chat_reopened') isClosed = false;
    }
    return isClosed;
  }

  /// Demande acceptée par le médecin : le formulaire détaillé (`form_teleconsult`) n’est pas encore envoyé.
  bool get _shouldShowPostAcceptFillFormCta {
    if (_teleFormStartedLocally) return false;
    if (_sessionCloture) return false;
    var lastRequestIdx = -1;
    for (var i = 0; i < _messages.length; i++) {
      if ((_messages[i]['type'] as String? ?? '') == 'request_teleconsult') {
        lastRequestIdx = i;
      }
    }
    if (lastRequestIdx == -1) return false;
    var lastAcceptIdx = -1;
    for (var i = 0; i < _messages.length; i++) {
      if ((_messages[i]['type'] as String? ?? '') == 'accept_request') {
        lastAcceptIdx = i;
      }
    }
    if (lastAcceptIdx == -1 || lastAcceptIdx < lastRequestIdx) return false;
    for (var j = lastAcceptIdx + 1; j < _messages.length; j++) {
      if ((_messages[j]['type'] as String? ?? '') == 'form_teleconsult') {
        return false;
      }
    }
    return true;
  }

  String? _latestChatClosedMarkerFromMessages() {
    for (var i = _messages.length - 1; i >= 0; i--) {
      final m = _messages[i];
      final type = m['type'] as String? ?? '';
      if (type != 'chat_closed') continue;
      final id = _extractObjectId(m['_id']);
      if (id != null && id.isNotEmpty) return 'id:$id';
      final createdAt = m['createdAt']?.toString();
      if (createdAt != null && createdAt.isNotEmpty) return 'createdAt:$createdAt';
      return 'idx:$i';
    }
    return null;
  }

  bool get _hasSubmittedFormAfterLastClosure {
    var lastCloseIdx = -1;
    for (var i = 0; i < _messages.length; i++) {
      if ((_messages[i]['type'] as String? ?? '') == 'chat_closed') {
        lastCloseIdx = i;
      }
    }
    if (lastCloseIdx == -1) return false;
    for (var j = lastCloseIdx + 1; j < _messages.length; j++) {
      final type = _messages[j]['type'] as String? ?? '';
      if (type == 'form_teleconsult') return true;
    }
    return false;
  }

  bool get _shouldShowSessionClosedFillFormCta {
    if (!_sessionCloture) return false;
    if (_teleFormStartedLocally) return false;
    if (_hasSubmittedFormAfterLastClosure) return false;
    return _latestChatClosedMarkerFromMessages() != null;
  }

  void _syncTeleFormCycleStateWithMessages() {
    final marker = _latestChatClosedMarkerFromMessages();
    if (marker == null) return;
    if (_lastChatClosedMarkerSeen == marker) return;
    _lastChatClosedMarkerSeen = marker;
    _teleFormStartedLocally = false;
  }

  /// Indique si le patient a déjà terminé un flux de téléconsultation
  /// (formulaire ou demande envoyés) dans cette conversation.
  bool get _hasTeleconsultFlowDone {
    return _messages.any((m) {
      final fromType = m['fromType'] as String? ?? '';
      final type = m['type'] as String? ?? '';
      if (fromType != 'system') return false;
      return type == 'request_teleconsult' || type == 'form_teleconsult';
    });
  }

  bool _teleFormModalShown = false;

  Future<void> _maybeShowTeleFormModal() async {
    if (!mounted || _conversationId == null || _teleFormModalShown) return;
    // Session clôturée par le médecin : pas de formulaire automatique (bouton dédié dans le chat).
    if (_sessionCloture) return;

    final hasFormPrompt =
        _messages.any((m) => (m['type'] as String? ?? '') == 'form_teleconsult_prompt');
    final hasRequestPrompt =
        _messages.any((m) => (m['type'] as String? ?? '') == 'request_teleconsult_prompt');

    // Après clôture (historique messages), ne plus ouvrir le formulaire tout seul.
    if (_isChatClosed) {
      return;
    }

    // Première fois tant qu'aucun flux n'a été terminé.
    if (!_hasTeleconsultFlowDone && (hasFormPrompt || hasRequestPrompt)) {
      await _showTeleFormModal(showRequest: hasRequestPrompt && !hasFormPrompt);
    }
  }

  /// Ouvre le formulaire après clôture de session (action explicite du patient).
  Future<void> _openTeleFormAfterSessionClosure() async {
    if (!mounted || _conversationId == null || !_sessionCloture) return;
    await _showTeleFormModal(
      showRequest: false,
      recordGloballyShown: false,
    );
  }

  Future<void> _showTeleFormModal({
    required bool showRequest,
    bool recordGloballyShown = true,
  }) async {
    if (!mounted) return;
    if (recordGloballyShown) _teleFormModalShown = true;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final bottomInset =
            MediaQuery.viewInsetsOf(ctx).bottom.clamp(0.0, double.infinity);
        final maxHeight = MediaQuery.of(ctx).size.height * 0.9;
        return Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              constraints: BoxConstraints(maxWidth: 640, maxHeight: maxHeight),
              decoration: BoxDecoration(
                color: HeadsAppColors.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 24,
                    offset: Offset(0, -8),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              showRequest
                                  ? 'Demande de téléconsultation'
                                  : 'Formulaire de téléconsultation',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: HeadsAppColors.textPrimary,
                                  ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () => Navigator.of(ctx).pop(),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Merci de remplir ce formulaire pour que le médecin puisse traiter correctement votre demande.',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: HeadsAppColors.textSecondary,
                                height: 1.4,
                              ),
                        ),
                        const SizedBox(height: 16),
                        if (showRequest)
                          _TeleconsultRequestCard(
                            conversationId: _conversationId!,
                            onSubmitted: () async {
                              await _loadMessages();
                              if (!ctx.mounted) return;
                              Navigator.of(ctx).pop();
                            },
                          )
                        else
                          _TeleconsultFormCard(
                            conversationId: _conversationId!,
                            patientId: widget.patientId,
                            onStarted: () {
                              if (!mounted || _teleFormStartedLocally) return;
                              setState(() => _teleFormStartedLocally = true);
                            },
                            onSubmitted: () async {
                              await _loadMessages();
                              if (!ctx.mounted) return;
                              Navigator.of(ctx).pop();
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  bool get _canSendMessages {
    if (_sessionCloture) return false;
    // Après une demande (`request_teleconsult`), l’acceptation médecin (`accept_request`)
    // ne débloque pas le chat : le patient doit d’abord envoyer le formulaire
    // (`form_teleconsult`). Ensuite, échange autorisé si le médecin a réagi
    // (message, créneau, etc.) — voir boucle ci-dessous.
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
      final m = _messages[j];
      final fromType = m['fromType'] as String? ?? '';
      final type = m['type'] as String? ?? '';
      if (fromType == 'doctor') return true;
      // Pas de `accept_request` ici : après acceptation, formulaire obligatoire avant message libre.
      if (type == 'teleconsult_scheduled') return true;
      if (type == 'rdv_teleconsult_programme') return true;
      if (_payloadEvent(m) == 'reply_by_message') return true;
    }
    return false;
  }

  Future<void> _sendTextMessage(String text) async {
    if (_conversationId == null || text.trim().isEmpty) return;
    if (_textSendInFlight) return;
    if (!_canSendMessages) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Complétez d’abord le formulaire de téléconsultation si le médecin a accepté votre demande, puis attendez sa réponse pour écrire librement.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final trimmed = text.trim();
    _textSendInFlight = true;
    _textController.clear();
    try {
      await ApiService.sendMessage(
        conversationId: _conversationId!,
        fromType: 'patient',
        type: 'text',
        content: trimmed,
        // Pour le patient : pas de niveaux d'importance, toujours "normal".
        payload: const {'urgency': 'normal'},
      );

      _markOutgoingMessage(fromType: 'patient');
      final hasNew = await _loadNewMessages();
      if (!hasNew) {
        await _loadMessages();
      }
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        _textController.text = trimmed;
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

  Future<void> _pickFile() async {
    if (_conversationId == null) return;
    if (!_canSendMessages) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Complétez d’abord le formulaire de téléconsultation si le médecin a accepté votre demande, puis attendez sa réponse pour envoyer des pièces jointes.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    try {
      final result = await FilePicker.platform.pickFiles();
      if (result == null || result.files.isEmpty) return;
      setState(() {
        _pendingAttachmentFile = result.files.first;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fichier prêt: ${_pendingAttachmentFile!.name}. Cliquez sur Envoyer.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
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

  Future<void> _pickImage() async {
    if (_conversationId == null) return;
    if (!_canSendMessages) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Complétez d’abord le formulaire de téléconsultation si le médecin a accepté votre demande, puis attendez sa réponse pour envoyer des images.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) return;
      setState(() {
        _pendingAttachmentFile = result.files.first;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Image prête: ${_pendingAttachmentFile!.name}. Cliquez sur Envoyer.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
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

  DateTime _messageCreatedAt(Map<String, dynamic> msg) {
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
      final mid = _extractObjectId(msg['_id']);
      final filename = msg['content'] as String? ?? 'Fichier';
      final mimetype = payload?['mimetype'] as String? ?? '';
      final isAudio = mimetype.startsWith('audio/') ||
          filename.toLowerCase().endsWith('.m4a') ||
          filename.toLowerCase().endsWith('.webm');
      if (isAudio) continue;
      final isImage = !isAudio && _chatAttachmentIsImage(mimetype, filename, url);
      final openUrl = url;
      entries.add({
        'url': url,
        'openUrl': openUrl,
        'filename': filename,
        'mimetype': mimetype,
        'size': payload?['size'],
        'isImage': isImage,
        'createdAt': _messageCreatedAt(msg),
      });
    }
    entries.sort((a, b) => (b['createdAt'] as DateTime).compareTo(a['createdAt'] as DateTime));
    final medias = entries.where((e) => e['isImage'] == true).toList();
    final files = entries.where((e) => e['isImage'] != true).toList();

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
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
                      color: Colors.grey.shade300,
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
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ),
                    Positioned(
                      top: 0,
                      right: 0,
                      child: IconButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        tooltip: 'Fermer',
                        icon: const Icon(Icons.close_rounded, size: 20),
                        color: const Color(0xFF2C3E50),
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFFE8F6FC),
                          side: const BorderSide(color: Color(0xFF4FA8D5), width: 1),
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
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                if (medias.isEmpty)
                  Text('Aucun média.', style: TextStyle(color: Colors.grey.shade700))
                else
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: medias.length,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 6,
                      crossAxisSpacing: 6,
                    ),
                    itemBuilder: (_, i) {
                      final m = medias[i];
                      return InkWell(
                        onTap: () => _showChatImageFullscreen(context, m['url'] as String),
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
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                if (files.isEmpty)
                  Text('Aucun fichier.', style: TextStyle(color: Colors.grey.shade700))
                else
                  ...files.map((f) {
                    final filename = f['filename'] as String;
                    final mimetype = f['mimetype'] as String? ?? '';
                    final style = _chatFileTypeStyle(filename, mimetype);
                    final openUrl = (f['openUrl'] as String?) ?? (f['url'] as String);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
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
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  [
                                    _formatAttachmentSize(f['size']),
                                    style.extLabel,
                                  ].where((e) => e.toString().isNotEmpty).join(' · '),
                                  style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: () => _openChatAttachmentFile(
                              context,
                              openUrl,
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
    if (_conversationId == null) return;
    if (!_canSendMessages) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Complétez d’abord le formulaire de téléconsultation si le médecin a accepté votre demande, puis attendez sa réponse pour envoyer un vocal.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
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
        // Web : pas de path_provider, on utilise un identifiant virtuel (record_web gère un blob)
        const path = 'voice.webm';
        await _audioRecorder.start(
          const RecordConfig(encoder: AudioEncoder.opus),
          path: path,
        );
      } else {
        final dir = await getTemporaryDirectory();
        final path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
        await _audioRecorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
      }
      if (mounted) setState(() => _isRecording = true);
    } catch (e) {
      if (mounted) {
        final msg = e.toString().contains('MissingPluginException') || e.toString().contains('getTemporaryDirectory')
            ? 'Enregistrement vocal non disponible sur cette plateforme.'
            : 'Erreur enregistrement: ${e.toString().replaceFirst('Exception: ', '')}';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
        );
      }
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
        // Web: selon le navigateur, stop() retourne une URL blob lisible
        // par XFile ou via GET; on essaie les 2 pour robustesse.
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
        file = PlatformFile(
          name: 'voice.m4a',
          path: path,
          size: 0,
        );
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
      if (mounted) {
        setState(() => _isRecording = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WebRtcService.instance.joinConversationRoom(null);
    PatientReplyNotificationService.setSuppressedConversation(null);
    _messagePollTimer?.cancel();
    _messagePollTimer = null;
    _doctorStatusPollTimer?.cancel();
    _doctorStatusPollTimer = null;
    _patientCallWindowTimer?.cancel();
    _patientCallWindowTimer = null;
    _waitingRoomOpenKickTimer?.cancel();
    _waitingRoomOpenKickTimer = null;
    _consultationSocketSub?.cancel();
    _consultationSocketSub = null;
    _callSummarySocketSub?.cancel();
    _callSummarySocketSub = null;
    _socketConnSub?.cancel();
    _socketConnSub = null;
    _chatActivitySub?.cancel();
    _chatActivitySub = null;
    _chatSessionClosedSub?.cancel();
    _chatSessionClosedSub = null;
    _chatSessionReopenedSub?.cancel();
    _chatSessionReopenedSub = null;
    _chatTypingSub?.cancel();
    _chatTypingSub = null;
    _chatMessagesReadSub?.cancel();
    _chatMessagesReadSub = null;
    _doctorStatusUpdatedSub?.cancel();
    _doctorStatusUpdatedSub = null;
    _typingPauseTimer?.cancel();
    _typingEmitEndTimer?.cancel();
    _chatScrollController.dispose();
    _callProvider.removeListener(_onCallProviderChanged);
    _callProvider.dispose();
    CallChatContext.unregister();
    _textController.dispose();
    _audioRecorder.dispose();
    _notificationPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const skyBlue = HeadsAppColors.brandPrimary;

    final isDoctorAvailable = _doctorStatus == 'available';
    final showDoctorOnlineDot = isDoctorAvailable;
    final doctorStatusSubtitle = _doctorStatus == 'busy'
        ? 'Occupé'
        : (_doctorStatus == 'unavailable'
            ? 'Non disponible'
            : (_doctorStatus == 'available' ? 'En ligne' : ''));
    final doctorStatusColor = _doctorStatus == 'busy'
        ? const Color(0xFFF59E0B)
        : (_doctorStatus == 'unavailable'
            ? const Color(0xFF9CA3AF)
            : Colors.white);
    final waitingRoomBanner = _waitingRoomBannerData();

    // Important : ne pas intercepter le retour pour effacer la session ici.
    // Sur Flutter Web, un "refresh" peut déclencher ce flux et provoquer une
    // retombée sur la page de login (déconnexion) au prochain chargement.
    return PopScope(
      canPop: true,
      child: Scaffold(
      backgroundColor: HeadsAppColors.surfaceAlt,
      appBar: AppBar(
        backgroundColor: HeadsAppColors.brandPrimary,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () async {
            final prefs = await SharedPreferences.getInstance();
            await prefs.remove('lastRoute');
            await prefs.remove('chatDoctorId');
            await prefs.remove('chatDoctorName');
            await prefs.remove('chatDoctorPhotoPath');

            if (!context.mounted) return;
            // Si la page précédente existe dans la pile de navigation, on revient.
            final didPop = await Navigator.of(context).maybePop();
            if (didPop) return;

            // Sinon (cas "chat" réouvert après reload), on renvoie vers l'espace patient.
            if (!context.mounted) return;
            final patientId = prefs.getString('patientId') ?? widget.patientId;
            final patientName = readablePatientName(prefs.getString('patientName'));
            Navigator.of(context).pushReplacement(
              MaterialPageRoute<void>(
                builder: (_) => EspacePatientPage(
                  patientId: patientId,
                  patientName: patientName,
                ),
              ),
            );
          },
        ),
        titleSpacing: 0,
        title: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                doctorAvatarForPatient(
                  name: _doctorDisplayName,
                  doctorPhotoPath: _doctorPhotoPath,
                  radius: 16,
                  backgroundColor: Colors.white,
                  accentColor: HeadsAppColors.brandPrimary,
                  fallbackChild: const Icon(
                    Icons.person_rounded,
                    color: HeadsAppColors.brandPrimary,
                    size: 18,
                  ),
                ),
                if (showDoctorOnlineDot)
                  Positioned(
                    right: -1,
                    bottom: -1,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: const Color(0xFF22C55E),
                        shape: BoxShape.circle,
                        border: Border.all(color: skyBlue, width: 1.5),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _doctorDisplayName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  if (doctorStatusSubtitle.isNotEmpty)
                    Text(
                      doctorStatusSubtitle,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.2,
                        color: doctorStatusColor,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          _patientCallBarIconButton(icon: Icons.call_rounded),
          _patientCallBarIconButton(icon: Icons.videocam_rounded),
          if (_conversationId != null)
            IconButton(
              tooltip: PrescriptionHistoryStrings.tooltipHistory,
              icon: const Icon(Icons.history_rounded),
              onPressed: () {
                final cid = _conversationId;
                if (cid == null) return;
                unawaited(openPrescriptionHistory(context, conversationId: cid));
              },
            ),
          IconButton(
            icon: const Icon(Icons.info_outline_rounded),
            onPressed: _openConversationInfoPanel,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
                : Column(
                  children: [
                    if (!isDoctorAvailable &&
                        _doctorAutoReplyEnabled &&
                        _doctorAbsenceMessage != null)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              color: Colors.orange.shade600,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _doctorAbsenceMessage!,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF7C2D12),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (waitingRoomBanner != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                        child: WaitingRoomBanner(
                          consultationTime: waitingRoomBanner.consultationTime,
                          waitingRoomOpensAt: waitingRoomBanner.consultationTime
                              .subtract(_waitingRoomLead),
                          canEnterWaitingRoom: waitingRoomBanner.canEnter,
                          doctorName: _doctorDisplayName,
                          specialty: _doctorSpecialty ?? '',
                          onEnterRoom: _enterWaitingRoom,
                        ),
                      ),
                    Expanded(
                      child: CustomScrollView(
                        controller: _chatScrollController,
                        slivers: [
                          // Formulaire récurrent : pour patient avec historique, sans
                          // chat clôturé et sans flux de téléconsult déjà terminé.
                          // Le formulaire/demande s'affiche désormais dans une
                          // carte modale dédiée (bottom sheet), pas dans le chat.
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                            sliver: SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (context, index) {
                                  final msg = _messages[index];
                                  if (_hideMessageFromPatientDiscussion(msg)) {
                                    return const SizedBox.shrink();
                                  }
                                  final type = msg['type'] as String? ?? 'text';
                                  if (type == 'form_teleconsult_prompt' ||
                                      type == 'request_teleconsult_prompt') {
                                    return const SizedBox.shrink();
                                  }

                                  final created = _patientMessageCreatedAt(msg);
                                  final dateLine = _showDateBeforePatientIndex(index) &&
                                          created != null
                                      ? _formatPatientDateHeader(
                                          DateTime(
                                            created.year,
                                            created.month,
                                            created.day,
                                          ),
                                        )
                                      : null;

                                  late final Widget inner;
                                  if (type == 'question_physique') {
                                    if (_hasHistory ||
                                        _hasTeleconsultFlowDone ||
                                        _isChatClosed) {
                                      return const SizedBox.shrink();
                                    }
                                    inner = _QuestionPhysiqueCard(
                                      onAnswered: (hasConsulted) {
                                        _handleQuestionAnswer(hasConsulted);
                                      },
                                    );
                                  } else if (type == 'accept_request') {
                                    inner = const _InfoBubble(
                                      icon: Icons.check_circle_rounded,
                                      iconColor: Color(0xFF16A34A),
                                      text:
                                          'Votre demande de téléconsultation a été acceptée par le médecin.',
                                    );
                                  } else if (type == 'rdv_teleconsult_programme') {
                                    inner = _InfoBubble(
                                      icon: Icons.event_note_rounded,
                                      iconColor: const Color(0xFF0F766E),
                                      text: msg['content'] as String? ?? '',
                                    );
                                  } else if (type == 'rdv_teleconsult_annule') {
                                    inner = _InfoBubble(
                                      icon: Icons.event_busy_rounded,
                                      iconColor: const Color(0xFFB91C1C),
                                      text: msg['content'] as String? ?? '',
                                    );
                                  } else if (type == 'teleconsult_scheduled') {
                                    final when = _teleconsultLocalDateTime(msg);
                                    final text = when != null
                                        ? _formatTeleconsultPatient(when)
                                        : (msg['content'] as String? ?? '—');
                                    inner = _InfoBubble(
                                      icon: Icons.event_available_rounded,
                                      iconColor: const Color(0xFF40CFFF),
                                      text: text,
                                    );
                                  } else if (type == 'chat_closed') {
                                    inner = _PatientSessionClosedLine(
                                      text: msg['content'] as String? ??
                                          '🔒 La session a été clôturée par le médecin.',
                                    );
                                  } else if (type == 'chat_reopened') {
                                    inner = _PatientSessionReopenedLine(
                                      text: msg['content'] as String? ??
                                          '🔓 La session a été réouverte par le médecin.',
                                    );
                                  } else if (type == 'call_event') {
                                    final p = msg['payload'];
                                    if (p is Map &&
                                        p['kind']?.toString() == 'call_log') {
                                      inner = CallLogBubble(
                                        payload: Map<String, dynamic>.from(p),
                                        titleOverride: msg['content'] as String?,
                                      );
                                    } else {
                                      inner = _InfoBubble(
                                        icon: Icons.phone_callback_rounded,
                                        iconColor: const Color(0xFF64748B),
                                        text: msg['content'] as String? ?? '',
                                      );
                                    }
                                  } else if (type == 'prescription') {
                                    inner = PatientPrescriptionMessageCard(
                                      msg: msg,
                                      conversationId: _conversationId,
                                    );
                                  } else if (type == 'attachment' || type == 'file') {
                                    final payload = msg['payload'] as Map<String, dynamic>?;
                                    final path = payload?['path'] as String?;
                                    final filename = msg['content'] as String? ?? '';
                                    final mimetype = payload?['mimetype'] as String? ?? '';
                                    final isVoice = path != null &&
                                        (mimetype.startsWith('audio/') ||
                                            filename.toLowerCase().endsWith('.m4a') ||
                                            filename.toLowerCase().endsWith('.webm'));
                                    inner = isVoice
                                        ? _VoiceMessageBubble(msg: msg)
                                        : _AttachmentBubble(
                                            msg: msg,
                                            conversationId: _conversationId,
                                          );
                                  } else {
                                    inner = _TextBubble(msg: msg);
                                  }

                                  if (dateLine == null) return inner;
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      _PatientDateChip(label: dateLine),
                                      inner,
                                    ],
                                  );
                                },
                                childCount: _messages.length,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_shouldShowPostAcceptFillFormCta && !_sessionCloture)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                        child: _buildPostAcceptFillFormCard(),
                      ),
                    _buildInputBar(skyBlue),
                  ],
                ),
      ),
    );
  }

  Color _sendIconColor() {
    return const Color(0xFFE1395F);
  }

  Future<void> _onSendPressed() async {
    if (_pendingAttachmentFile != null && _conversationId != null) {
      try {
        await ApiService.uploadAttachment(
          conversationId: _conversationId!,
          file: _pendingAttachmentFile!,
          senderId: widget.patientId,
        );
        _markOutgoingMessage(fromType: 'patient');
        setState(() {
          _pendingAttachmentFile = null;
        });
        final hasNew = await _loadNewMessages();
        if (!hasNew) {
          await _loadMessages();
        }
        return;
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.toString().replaceFirst('Exception: ', ''),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }

    // Si un message vocal est en attente, l'envoyer en priorité
    if (_pendingVoiceFile != null && _conversationId != null) {
      try {
        await ApiService.uploadAttachment(
          conversationId: _conversationId!,
          file: _pendingVoiceFile!,
          senderId: widget.patientId,
        );

        _markOutgoingMessage(fromType: 'patient');

        setState(() {
          _pendingVoiceFile = null;
        });
        final hasNew = await _loadNewMessages();
        if (!hasNew) {
          await _loadMessages();
        }
        return;
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.toString().replaceFirst('Exception: ', ''),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }

    // Sinon, envoyer le texte comme avant
    _sendTextMessage(_textController.text);
  }

  Widget _buildPatientSessionClotureFormCard() {
    return Material(
      color: Colors.grey.shade200,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.lock_outline_rounded,
                  color: Colors.grey.shade800,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Session clôturée',
                        style: TextStyle(
                          color: Colors.grey.shade900,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Pour une nouvelle demande, remplissez le formulaire de téléconsultation.',
                        style: TextStyle(
                          color: Colors.grey.shade800,
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            HeadsFormCtaButton(
              compact: true,
              icon: Icons.edit_note_rounded,
              label: 'Remplir formulaire',
              onPressed: _openTeleFormAfterSessionClosure,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPostAcceptFillFormCard() {
    return Material(
      color: Colors.grey.shade200,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.check_circle_outline_rounded,
                  color: Colors.green.shade700,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Demande acceptée',
                        style: TextStyle(
                          color: Colors.grey.shade900,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Remplissez le formulaire de téléconsultation et envoyez-le au médecin pour poursuivre votre prise en charge.',
                        style: TextStyle(
                          color: Colors.grey.shade800,
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            HeadsFormCtaButton(
              compact: true,
              icon: Icons.edit_note_rounded,
              label: 'Remplir formulaire',
              onPressed: () async {
                await _showTeleFormModal(
                  showRequest: false,
                  recordGloballyShown: false,
                );
                if (mounted) setState(() {});
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar(Color skyBlue) {
    if (_sessionCloture) {
      return Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        color: Colors.white,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_peerTyping)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    'Le médecin est en train d\'écrire…',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              if (_shouldShowSessionClosedFillFormCta) ...[
                _buildPatientSessionClotureFormCard(),
                const SizedBox(height: 8),
              ],
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Session clôturée — vous ne pouvez plus envoyer de messages',
                  style: TextStyle(fontSize: 13, color: Color(0xFF374151)),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (_isChatClosed) {
      return Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        color: Colors.white,
        child: SafeArea(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFE5E7EB),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: const [
                Icon(Icons.info_outline_rounded, size: 18, color: Color(0xFF4B5563)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Ce chat a été clôturé par le médecin. Vous ne pouvez plus envoyer de messages dans cette conversation.',
                    style: TextStyle(fontSize: 13, color: Color(0xFF4B5563)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    // Tant que les deux conditions ne sont pas remplies (_canSendMessages == false),
    // on n'affiche QUE le message explicatif, pas le champ de saisie.
    if (!_canSendMessages) {
      return Container(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
        color: Colors.white,
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF7E6),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFF59E0B)),
          ),
          child: Row(
            children: const [
              Icon(Icons.info_outline_rounded,
                  size: 18, color: Color(0xFFF59E0B)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Si votre demande est acceptée, complétez d’abord le formulaire de téléconsultation. Vous pourrez écrire au médecin après envoi du formulaire et lorsque la conversation sera ouverte (réponse ou créneau du médecin).',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF92400E),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      color: Colors.white,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_peerTyping)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Le médecin est en train d\'écrire…',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 6),
          if (_pendingAttachmentFile != null)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: skyBlue.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: skyBlue.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.attach_file_rounded,
                      size: 18, color: Color(0xFF4FA8D5)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Fichier prêt: ${_pendingAttachmentFile!.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () {
                      setState(() {
                        _pendingAttachmentFile = null;
                      });
                    },
                    icon: const Icon(Icons.close_rounded,
                        size: 18, color: Colors.red),
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                ],
              ),
            ),
          if (_pendingAttachmentFile != null && _pendingVoiceFile != null)
            const SizedBox(height: 4),
          if (_pendingVoiceFile != null)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: skyBlue.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: skyBlue.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.mic_rounded,
                      size: 18, color: Color(0xFF4FA8D5)),
                  const SizedBox(width: 8),
                  const Text(
                    'Message vocal prêt à envoyer',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () {
                      setState(() {
                        _pendingVoiceFile = null;
                      });
                    },
                    icon: const Icon(Icons.close_rounded,
                        size: 18, color: Colors.red),
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                ],
              ),
            ),
          if (_pendingVoiceFile != null) const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                width: 44,
                height: 44,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: skyBlue.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: PopupMenuButton<String>(
                  tooltip: 'Ajouter une pièce jointe',
                  enabled: _conversationId != null,
                  padding: EdgeInsets.zero,
                  onSelected: (value) {
                    if (value == 'file') {
                      _pickFile();
                    } else if (value == 'image') {
                      _pickImage();
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem<String>(
                      value: 'file',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.attach_file_rounded),
                        title: Text('Fichier'),
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'image',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.photo_library_rounded),
                        title: Text('Photo'),
                      ),
                    ),
                  ],
                  child: Icon(
                    Icons.add_rounded,
                    size: 20,
                    color: _conversationId == null
                        ? Colors.grey.shade500
                        : skyBlue,
                  ),
                ),
              ),
              Expanded(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 52),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: _patientInputSurfaceGreyForReopenAnim
                          ? Colors.grey.shade200
                          : HeadsAppColors.surfaceSoft,
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(
                        color: HeadsAppColors.border,
                      ),
                    ),
                    child: TextField(
                      controller: _textController,
                      textInputAction: TextInputAction.send,
                      onChanged: _onPatientTextChangedTyping,
                      onSubmitted: (_) => _onSendPressed(),
                      decoration: const InputDecoration(
                        hintText: 'Écrire au médecin...',
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                      ),
                      minLines: 1,
                      maxLines: 4,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.9),
                  shape: BoxShape.circle,
                  border: Border.all(color: HeadsAppColors.border),
                ),
                child: IconButton(
                  onPressed: _isRecording
                      ? _stopAndSendRecording
                      : _startRecording,
                  padding: EdgeInsets.zero,
                  tooltip: _isRecording
                      ? 'Arrêter l’enregistrement'
                      : 'Message vocal',
                  icon: Icon(
                    _isRecording
                        ? Icons.stop_rounded
                        : Icons.mic_none_rounded,
                    size: 19,
                  ),
                  color: _isRecording
                      ? Colors.red
                      : Colors.grey.shade700,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _sendIconColor().withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  onPressed: _onSendPressed,
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.send_rounded, size: 22),
                  color: _sendIconColor(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _handleQuestionAnswer(bool hasConsulted) async {
    if (_conversationId == null) return;
    // on ajoute un message local pour afficher le bloc suivant
    if (_hasHistory || hasConsulted) {
      _messages.add({
        'type': 'form_teleconsult_prompt',
        'fromType': 'system',
      });
    } else {
      _messages.add({
        'type': 'request_teleconsult_prompt',
        'fromType': 'system',
      });
    }
    if (mounted) {
      setState(() {});
      await _maybeShowTeleFormModal();
    }
  }
}

class _QuestionPhysiqueCard extends StatelessWidget {
  const _QuestionPhysiqueCard({required this.onAnswered});

  final ValueChanged<bool> onAnswered;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Avez‑vous déjà eu une consultation physique avec ce médecin ?',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: () => onAnswered(true),
                    child: const Text('Oui, déjà consulté'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => onAnswered(false),
                    child: const Text('Non, première fois'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TeleconsultRequestCard extends StatefulWidget {
  const _TeleconsultRequestCard({
    required this.conversationId,
    required this.onSubmitted,
  });

  final String conversationId;
  final Future<void> Function() onSubmitted;

  @override
  State<_TeleconsultRequestCard> createState() => _TeleconsultRequestCardState();
}

class _TeleconsultRequestCardState extends State<_TeleconsultRequestCard> {
  final TextEditingController _motifController = TextEditingController();
  bool _sending = false;
  bool _accepted = false;

  @override
  void dispose() {
    _motifController.dispose();
    super.dispose();
  }

  Future<void> _sendRequest() async {
    if (_sending) return;
    setState(() => _sending = true);
    try {
      await ApiService.sendTeleconsultRequest(
        conversationId: widget.conversationId,
        motif: _motifController.text.trim(),
        letterBody: kTeleconsultFirstRequestLetterBody,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Demande de téléconsultation envoyée au médecin.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await widget.onSubmitted();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Demande de première téléconsultation',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: SingleChildScrollView(
                child: Text(
                  kTeleconsultFirstRequestLetterBody,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.4),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Checkbox(
                  value: _accepted,
                  onChanged: (v) => setState(() => _accepted = v ?? false),
                ),
                const Expanded(
                  child: Text(
                    'Je certifie avoir lu attentivement cette demande et je souhaite l\'envoyer à ce médecin.',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _motifController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Préciser éventuellement votre motif (facultatif)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            HeadsFormCtaButton(
              isLoading: _sending,
              label: 'Envoyer la demande',
              onPressed: _sending || !_accepted ? null : _sendRequest,
            ),
          ],
        ),
      ),
    );
  }
}

class _TeleconsultFormCard extends StatefulWidget {
  const _TeleconsultFormCard({
    required this.conversationId,
    required this.patientId,
    required this.onStarted,
    required this.onSubmitted,
  });

  final String conversationId;
  final String patientId;
  final VoidCallback onStarted;
  final Future<void> Function() onSubmitted;

  @override
  State<_TeleconsultFormCard> createState() => _TeleconsultFormCardState();
}

class _TeleconsultFormCardState extends State<_TeleconsultFormCard> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _autreMotifController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _traitementsPrecisionsController = TextEditingController();
  bool _sending = false;
  bool _startedNotified = false;
  /// Fichiers rattachés au dossier téléconsultation (API métier, pas le chat).
  final List<PlatformFile> _formAttachmentQueue = [];

  // Motifs
  bool _motifSuivi = false;
  bool _motifNouvelleDouleur = false;
  bool _motifResultat = false;
  bool _motifEffetSecondaire = false;
  bool _motifRenouvellement = false;
  bool _motifAutre = false;

  // Depuis quand
  String? _dureeProbleme;

  // Intensité douleur
  String? _intensiteDouleur;

  // Autres symptômes
  bool _symptFievre = false;
  bool _symptFatigue = false;
  bool _symptDyspnee = false;
  bool _symptNausees = false;
  bool _symptSaignement = false;
  bool _symptAucunAutre = false;

  // Traitement en cours
  bool? _prendTraitement;

  @override
  void dispose() {
    _autreMotifController.dispose();
    _descriptionController.dispose();
    _dateController.dispose();
    _traitementsPrecisionsController.dispose();
    super.dispose();
  }

  void _markStarted() {
    if (_startedNotified) return;
    _startedNotified = true;
    widget.onStarted();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
    );
    if (picked != null) {
      _markStarted();
      _dateController.text = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    }
  }

  Future<void> _sendForm() async {
    if (_sending) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _sending = true);
    try {
      // Construire le motif global
      final motifs = <String>[];
      if (_motifSuivi) motifs.add('Suivi de traitement');
      if (_motifNouvelleDouleur) motifs.add('Nouvelle douleur ou nouveau symptôme');
      if (_motifResultat) motifs.add('Résultat d’analyse');
      if (_motifEffetSecondaire) motifs.add('Effet secondaire d’un médicament');
      if (_motifRenouvellement) motifs.add('Renouvellement d’ordonnance');
      if (_motifAutre && _autreMotifController.text.trim().isNotEmpty) {
        motifs.add('Autre: ${_autreMotifController.text.trim()}');
      }
      final motif = motifs.join(' | ');

      // Texte symptômes / description
      final details = <String>[];
      if (_descriptionController.text.trim().isNotEmpty) {
        details.add('Description: ${_descriptionController.text.trim()}');
      }
      if (_dureeProbleme != null && _dureeProbleme!.isNotEmpty) {
        details.add('Depuis: $_dureeProbleme');
      }
      if (_intensiteDouleur != null && _intensiteDouleur!.isNotEmpty) {
        details.add('Intensité douleur: $_intensiteDouleur');
      }
      final autresSymptomes = <String>[];
      if (_symptFievre) autresSymptomes.add('Fièvre');
      if (_symptFatigue) autresSymptomes.add('Fatigue');
      if (_symptDyspnee) autresSymptomes.add('Difficulté à respirer');
      if (_symptNausees) autresSymptomes.add('Nausées');
      if (_symptSaignement) autresSymptomes.add('Saignement');
      if (_symptAucunAutre && autresSymptomes.isEmpty) {
        autresSymptomes.add('Aucun autre symptôme');
      }
      if (autresSymptomes.isNotEmpty) {
        details.add('Autres symptômes: ${autresSymptomes.join(', ')}');
      }
      final symptomes = details.join(' | ');

      String traitements = '';
      if (_prendTraitement != null) {
        traitements = _prendTraitement! ? 'Prend actuellement un traitement' : 'Ne prend pas de traitement';
      }
      if (_traitementsPrecisionsController.text.trim().isNotEmpty) {
        final sep = traitements.isEmpty ? '' : ' - ';
        traitements += '${sep}Détails traitement: ${_traitementsPrecisionsController.text.trim()}';
      }

      final res = await ApiService.sendTeleconsultForm(
        conversationId: widget.conversationId,
        motif: motif,
        symptomes: symptomes,
        dateDerniereConsultation: _dateController.text.trim().isEmpty ? null : _dateController.text.trim(),
        traitements: traitements,
        allergies: null,
      );
      final formId = res['id']?.toString();
      final patientIdForFiles =
          res['patientId']?.toString() ?? widget.patientId;
      if (formId != null &&
          formId.isNotEmpty &&
          _formAttachmentQueue.isNotEmpty) {
        for (final f in List<PlatformFile>.from(_formAttachmentQueue)) {
          await ApiService.uploadTeleconsultFormAttachment(
            formId: formId,
            patientId: patientIdForFiles,
            file: f,
          );
        }
      }
      if (mounted) {
        setState(() => _formAttachmentQueue.clear());
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Formulaire de téléconsultation envoyé.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await widget.onSubmitted();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const skyBlue = Color(0xFF4FA8D5);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
        child: Form(
          key: _formKey,
          onChanged: _markStarted,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: skyBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: skyBlue,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.medical_services_rounded,
                          color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            'Formulaire de téléconsultation',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Quelques questions pour mieux comprendre votre demande.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Pourquoi contactez-vous votre médecin ?',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF0F172A),
                    ),
              ),
              const SizedBox(height: 8),
              _buildMotifCheckbox('Suivi de traitement', _motifSuivi, (v) => setState(() => _motifSuivi = v)),
              _buildMotifCheckbox(
                'Nouvelle douleur ou nouveau symptôme',
                _motifNouvelleDouleur,
                (v) => setState(() => _motifNouvelleDouleur = v),
              ),
              _buildMotifCheckbox(
                'Résultat d’analyse',
                _motifResultat,
                (v) => setState(() => _motifResultat = v),
              ),
              _buildMotifCheckbox(
                'Effet secondaire d’un médicament',
                _motifEffetSecondaire,
                (v) => setState(() => _motifEffetSecondaire = v),
              ),
              _buildMotifCheckbox(
                'Renouvellement d’ordonnance',
                _motifRenouvellement,
                (v) => setState(() => _motifRenouvellement = v),
              ),
              Row(
                children: [
                  Checkbox(
                    value: _motifAutre,
                    onChanged: (v) {
                      _markStarted();
                      setState(() => _motifAutre = v ?? false);
                    },
                  ),
                  const Text('Autre :'),
                ],
              ),
              if (_motifAutre)
                TextFormField(
                  controller: _autreMotifController,
                  decoration: const InputDecoration(
                    labelText: 'Précisez le motif',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    if (_motifAutre && (v == null || v.isEmpty)) {
                      return 'Veuillez préciser le motif';
                    }
                    return null;
                  },
                ),
              const SizedBox(height: 16),
              if (_motifNouvelleDouleur || _motifEffetSecondaire) ...[
                Text(
                  'Expliquez simplement ce que vous ressentez.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _descriptionController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'Décrivez vos symptômes avec vos mots…',
                  ),
                  validator: (v) {
                    if ((_motifNouvelleDouleur || _motifEffetSecondaire) && (v == null || v.isEmpty)) {
                      return 'Merci de décrire ce que vous ressentez';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                Text(
                  'Depuis quand avez-vous ce problème ?',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                Column(
                  children: [
                    _buildDureeRadio('Aujourd’hui'),
                    _buildDureeRadio('Depuis 1 à 3 jours'),
                    _buildDureeRadio('Depuis plus de 3 jours'),
                    _buildDureeRadio('Depuis plus d’une semaine'),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Si vous avez une douleur, quelle est son intensité ?',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                Column(
                  children: [
                    _buildIntensiteRadio('0 : pas de douleur'),
                    _buildIntensiteRadio('<10 : douleur modérée'),
                    _buildIntensiteRadio('10 : douleur très forte'),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Avez-vous d’autres symptômes ?',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                _buildSymptCheck('Fièvre', _symptFievre, (v) => setState(() => _symptFievre = v)),
                _buildSymptCheck('Fatigue', _symptFatigue, (v) => setState(() => _symptFatigue = v)),
                _buildSymptCheck('Difficulté à respirer', _symptDyspnee, (v) => setState(() => _symptDyspnee = v)),
                _buildSymptCheck('Nausées', _symptNausees, (v) => setState(() => _symptNausees = v)),
                _buildSymptCheck('Saignement', _symptSaignement, (v) => setState(() => _symptSaignement = v)),
                _buildSymptCheck(
                  'Aucun autre symptôme',
                  _symptAucunAutre,
                  (v) => setState(() => _symptAucunAutre = v),
                ),
                const SizedBox(height: 16),
              ],
              TextFormField(
                controller: _dateController,
                readOnly: true,
                onTap: _pickDate,
                decoration: const InputDecoration(
                  labelText: 'Date de la dernière consultation physique',
                  border: OutlineInputBorder(),
                  suffixIcon: Icon(Icons.calendar_today_rounded),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Prenez-vous actuellement un traitement ?',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              Wrap(
                spacing: 10,
                children: [
                  ChoiceChip(
                    label: const Text('Oui'),
                    selected: _prendTraitement == true,
                    onSelected: (selected) {
                      _markStarted();
                      setState(() => _prendTraitement = selected ? true : null);
                    },
                  ),
                  ChoiceChip(
                    label: const Text('Non'),
                    selected: _prendTraitement == false,
                    onSelected: (selected) {
                      _markStarted();
                      setState(() => _prendTraitement = selected ? false : null);
                    },
                  ),
                ],
              ),
              TextField(
                controller: _traitementsPrecisionsController,
                decoration: const InputDecoration(
                  labelText: 'Précisez le traitement (nom, dose…) (facultatif)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Pièces jointes au dossier téléconsultation (optionnel)',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 4),
              OutlinedButton.icon(
                onPressed: _sending ? null : _pickFormAttachments,
                icon: const Icon(Icons.attach_file_rounded),
                label: const Text('Ajouter des fichiers au dossier'),
              ),
              if (_formAttachmentQueue.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (var i = 0; i < _formAttachmentQueue.length; i++)
                      InputChip(
                        label: Text(
                          _formAttachmentQueue[i].name,
                          style: const TextStyle(fontSize: 12),
                        ),
                        onDeleted: _sending
                            ? null
                            : () => setState(
                                  () => _formAttachmentQueue.removeAt(i),
                                ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              HeadsFormCtaButton(
                isLoading: _sending,
                label: 'Envoyer le formulaire et démarrer la discussion',
                onPressed: _sending ? null : _sendForm,
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Future<void> _pickFormAttachments() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: kIsWeb,
      );
      if (result == null || result.files.isEmpty) return;
      _markStarted();
      setState(() {
        for (final f in result.files) {
          if (f.name.isNotEmpty) _formAttachmentQueue.add(f);
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  // Helpers internes pour les champs du formulaire

  Widget _buildMotifCheckbox(String label, bool value, ValueChanged<bool> onChanged) {
    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      value: value,
      onChanged: (v) {
        _markStarted();
        onChanged(v ?? false);
      },
      title: Text(label),
    );
  }

  Widget _buildSymptCheck(String label, bool value, ValueChanged<bool> onChanged) {
    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      value: value,
      onChanged: (v) {
        _markStarted();
        onChanged(v ?? false);
      },
      title: Text(label),
    );
  }

  Widget _buildDureeRadio(String label) {
    final selected = _dureeProbleme == label;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      onTap: () {
        _markStarted();
        setState(() => _dureeProbleme = label);
      },
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_off,
        color: selected ? Theme.of(context).colorScheme.primary : null,
      ),
      title: Text(label),
    );
  }

  Widget _buildIntensiteRadio(String label) {
    final selected = _intensiteDouleur == label;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      onTap: () {
        _markStarted();
        setState(() => _intensiteDouleur = label);
      },
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_off,
        color: selected ? Theme.of(context).colorScheme.primary : null,
      ),
      title: Text(label),
    );
  }
}

class _VoiceMessageBubble extends StatefulWidget {
  const _VoiceMessageBubble({required this.msg});

  final Map<String, dynamic> msg;

  @override
  State<_VoiceMessageBubble> createState() => _VoiceMessageBubbleState();
}

class _VoiceMessageBubbleState extends State<_VoiceMessageBubble> {
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
    _stateSubscription = _player.onPlayerStateChanged.listen((PlayerState state) {
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
        if (resp.statusCode < 200 || resp.statusCode >= 300 || resp.bodyBytes.isEmpty) {
          throw Exception('Source audio non supportée sur ce navigateur.');
        }
        await _player.play(BytesSource(resp.bodyBytes, mimeType: _audioMimeType));
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
    final isPatient = fromType == 'patient';
    final align = isPatient ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final bgColor = isPatient ? const Color(0xFF87CEEB) : const Color(0xFFF1F5F9);
    final textColor = isPatient ? Colors.white : const Color(0xFF0F172A);
    final rawVoiceRead = widget.msg['readAt']?.toString().trim();
    final voiceRead = rawVoiceRead != null && rawVoiceRead.isNotEmpty;

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
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    onPressed: _audioUrl.isEmpty ? null : _togglePlay,
                    icon: Icon(
                      _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: textColor,
                      size: 28,
                    ),
                  ),
                ],
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 2,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 0),
                ),
                child: Slider(
                  value: _duration.inMilliseconds > 0
                      ? _position.inMilliseconds
                          .clamp(0, _duration.inMilliseconds)
                          .toDouble()
                      : 0,
                  max: _duration.inMilliseconds > 0 ? _duration.inMilliseconds.toDouble() : 1,
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
                      style: TextStyle(fontSize: 11, color: textColor.withValues(alpha: 0.9)),
                    ),
                    Text(
                      _fmtDuration(_duration),
                      style: TextStyle(fontSize: 11, color: textColor.withValues(alpha: 0.9)),
                    ),
                  ],
                ),
              ),
              if (isPatient) ...[
                const SizedBox(height: 2),
                Align(
                  alignment: Alignment.centerRight,
                  child: Icon(
                    voiceRead
                        ? Icons.done_all_rounded
                        : Icons.done_rounded,
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

bool _chatAttachmentIsImage(String mimetype, String filename, String url) {
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

Future<void> _showChatImageFullscreen(BuildContext context, String url) async {
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

/// Ouvre la pièce jointe dans la visionneuse intégrée (PDF, Office, etc.).
Future<void> _openChatAttachmentFile(
  BuildContext context,
  String url,
  String filename, {
  required bool isImage,
  String mimetype = '',
}) async {
  if (isImage) {
    await _showChatImageFullscreen(context, url);
    return;
  }
  if (!context.mounted) return;
  try {
    await openChatAttachment(
      context: context,
      url: url,
      filename: filename,
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

String _formatAttachmentSize(dynamic sizeRaw) {
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

({String extLabel, IconData icon, Color accent}) _chatFileTypeStyle(
  String filename,
  String mimetype,
) {
  final lower = filename.toLowerCase();
  if (lower.endsWith('.pdf')) {
    return (extLabel: 'PDF', icon: Icons.picture_as_pdf_rounded, accent: const Color(0xFFE53935));
  }
  if (lower.endsWith('.doc') || lower.endsWith('.docx')) {
    return (extLabel: 'DOCX', icon: Icons.description_rounded, accent: const Color(0xFF2B579A));
  }
  if (lower.endsWith('.xls') || lower.endsWith('.xlsx')) {
    return (extLabel: 'XLSX', icon: Icons.table_chart_rounded, accent: const Color(0xFF217346));
  }
  if (lower.endsWith('.ppt') || lower.endsWith('.pptx')) {
    return (extLabel: 'PPTX', icon: Icons.slideshow_rounded, accent: const Color(0xFFD24726));
  }
  if (lower.endsWith('.zip') || lower.endsWith('.rar') || lower.endsWith('.7z')) {
    return (extLabel: 'ZIP', icon: Icons.folder_zip_rounded, accent: const Color(0xFFF9A825));
  }
  if (mimetype.startsWith('audio/') ||
      lower.endsWith('.m4a') ||
      lower.endsWith('.mp3') ||
      lower.endsWith('.wav')) {
    return (extLabel: 'AUDIO', icon: Icons.audio_file_rounded, accent: const Color(0xFF7E57C2));
  }
  if (mimetype.startsWith('video/') || lower.endsWith('.mp4') || lower.endsWith('.mov')) {
    return (extLabel: 'VIDÉO', icon: Icons.video_file_rounded, accent: const Color(0xFF0288D1));
  }
  final dot = filename.lastIndexOf('.');
  var ext = dot >= 0 ? filename.substring(dot + 1).toUpperCase() : '';
  if (ext.length > 6) ext = 'FICHIER';
  if (ext.isEmpty) ext = 'FICHIER';
  return (extLabel: ext, icon: Icons.insert_drive_file_rounded, accent: const Color(0xFF64748B));
}

class _AttachmentBubble extends StatelessWidget {
  const _AttachmentBubble({required this.msg, this.conversationId});

  final Map<String, dynamic> msg;
  final String? conversationId;

  @override
  Widget build(BuildContext context) {
    final fromType = msg['fromType'] as String? ?? 'system';
    final isPatient = fromType == 'patient';
    final align = isPatient ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final bgColor = isPatient ? const Color(0xFF87CEEB) : const Color(0xFFF1F5F9);
    final textColor = isPatient ? Colors.white : const Color(0xFF0F172A);
    final filename = msg['content'] as String? ?? 'Fichier';
    final payload = msg['payload'] as Map<String, dynamic>?;
    final mimetype = payload?['mimetype'] as String? ?? '';
    final isAudio = mimetype.startsWith('audio/') ||
        filename.toLowerCase().endsWith('.m4a') ||
        filename.toLowerCase().endsWith('.webm');
    final path = payload?['path'] as String?;
    final url = path != null && path.isNotEmpty
        ? ApiService.resolveMediaUrl(path)
        : '';
    final isImage =
        !isAudio && url.isNotEmpty && _chatAttachmentIsImage(mimetype, filename, url);
    final fileStyle = _chatFileTypeStyle(filename, mimetype);
    final mid = RegExp(r'[0-9a-fA-F]{24}')
        .firstMatch('${msg['_id'] ?? ''}')
        ?.group(0);
    final openFileUrl = url;

    final rawRead = msg['readAt']?.toString().trim();
    final attachmentRead = rawRead != null && rawRead.isNotEmpty;

    return Column(
      crossAxisAlignment: align,
      children: [
        if (isImage)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: url.isEmpty ? null : () => _showChatImageFullscreen(context, url),
                borderRadius: BorderRadius.circular(16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 260, maxHeight: 220),
                    child: Image.network(
                      url,
                      fit: BoxFit.cover,
                      width: 260,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Container(
                          width: 260,
                          height: 160,
                          color: bgColor.withValues(alpha: 0.5),
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
                        color: bgColor,
                        child: Row(
                          children: [
                            Icon(Icons.broken_image_rounded, color: textColor),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                filename,
                                style: TextStyle(color: textColor, fontSize: 13),
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
                : () => _openChatAttachmentFile(
                      context,
                      openFileUrl,
                      filename,
                      isImage: false,
                      mimetype: mimetype,
                    ),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
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
                        child: Icon(fileStyle.icon, color: fileStyle.accent, size: 28),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              filename,
                              style: const TextStyle(
                                color: Color(0xFF0F172A),
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              [
                                _formatAttachmentSize(payload?['size']),
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
                          : () => _openChatAttachmentFile(
                                context,
                                  openFileUrl,
                                filename,
                                isImage: false,
                                mimetype: mimetype,
                              ),
                      icon: const Icon(Icons.download_rounded, size: 18),
                      label: const Text('Ouvrir'),
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        minimumSize: const Size(0, 32),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (isPatient)
          Padding(
            padding: const EdgeInsets.only(top: 2, right: 4, bottom: 4),
            child: Icon(
              attachmentRead
                  ? Icons.done_all_rounded
                  : Icons.done_rounded,
              size: 15,
              color: attachmentRead
                  ? const Color(0xFF4FA8D5)
                  : Colors.grey.shade500,
            ),
          ),
      ],
    );
  }
}

class _PatientDateChip extends StatelessWidget {
  const _PatientDateChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade800,
            ),
          ),
        ),
      ),
    );
  }
}

class _PatientSessionClosedLine extends StatelessWidget {
  const _PatientSessionClosedLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade700,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      ),
    );
  }
}

class _PatientSessionReopenedLine extends StatelessWidget {
  const _PatientSessionReopenedLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFE8F5E9),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF1B5E20),
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      ),
    );
  }
}

/// Même logique que côté app médecin (`urgency` ou `importance`).
String _doctorMessageLevelForPatient(Map<String, dynamic>? payload) {
  final p = payload ?? {};
  final u = (p['urgency']?.toString() ?? '').trim();
  if (u == 'urgent' || u == 'medium' || u == 'normal') return u;
  switch (p['importance']?.toString()) {
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

class _TextBubble extends StatelessWidget {
  const _TextBubble({required this.msg});

  final Map<String, dynamic> msg;

  @override
  Widget build(BuildContext context) {
    final fromType = msg['fromType'] as String? ?? 'system';
    final isPatient = fromType == 'patient';
    final isDoctor = fromType == 'doctor';
    final align = isPatient ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final payload = msg['payload'] as Map<String, dynamic>?;
    final rawRead = msg['readAt'];
    final readStr = rawRead?.toString();
    final isRead = readStr != null && readStr.trim().isNotEmpty;

    final level = isDoctor ? _doctorMessageLevelForPatient(payload) : 'normal';

    late final Color doctorBg;
    late final Color doctorBorder;
    late final double borderWidth;
    late final IconData badgeIcon;
    late final String badgeText;

    switch (level) {
      case 'urgent':
        doctorBg = const Color(0xFFE1395F);
        doctorBorder = const Color(0xFFB71C1C);
        borderWidth = 2;
        badgeIcon = Icons.priority_high_rounded;
        badgeText = 'Très important';
        break;
      case 'medium':
        doctorBg = const Color(0xFFFF9800);
        doctorBorder = const Color(0xFFE65100);
        borderWidth = 1.5;
        badgeIcon = Icons.error_outline_rounded;
        badgeText = 'Important';
        break;
      default:
        // Même palette que côté médecin pour "normal".
        doctorBg = const Color(0xFF16A34A);
        doctorBorder = const Color(0xFF166534);
        borderWidth = 1;
        badgeIcon = Icons.check_circle_outline_rounded;
        badgeText = 'Normal';
        break;
    }

    final bgColor = isDoctor
        ? doctorBg
        : (isPatient ? const Color(0xFF87CEEB) : const Color(0xFFF1F5F9));
    final textColor = (isDoctor || isPatient)
        ? Colors.white
        : const Color(0xFF0F172A);

    return Column(
      crossAxisAlignment: align,
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(16),
            border: isDoctor
                ? Border.all(color: doctorBorder, width: borderWidth)
                : null,
          ),
          child: Column(
            crossAxisAlignment: isDoctor ? CrossAxisAlignment.start : align,
            children: [
              if (isDoctor) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(badgeIcon, size: 14, color: Colors.white),
                      const SizedBox(width: 4),
                      Text(
                        badgeText,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              Text(
                (msg['content'] as String?) ?? '',
                style: TextStyle(color: textColor, height: 1.25),
              ),
            ],
          ),
        ),
        if (isPatient)
          Padding(
            padding: const EdgeInsets.only(bottom: 4, right: 2),
            child: Icon(
              isRead ? Icons.done_all_rounded : Icons.done_rounded,
              size: 15,
              color: isRead ? const Color(0xFF4FA8D5) : Colors.grey.shade500,
            ),
          ),
      ],
    );
  }
}

/// Bulle d'information centrée (pour messages système comme acceptation).
class _InfoBubble extends StatelessWidget {
  const _InfoBubble({
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
            border: Border.all(color: const Color(0xFF16A34A).withValues(alpha: 0.4)),
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


