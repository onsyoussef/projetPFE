import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'bloc_urgence_page.dart';
import 'chat_page.dart';
import 'choix_medecin_page.dart';
import 'dossier_medical_page.dart';
import 'discussions_patient_page.dart';
import 'rendezvous_patient_page.dart';
import 'screens/blood_pressure_screen.dart';
import 'screens/patient_notifications_screen.dart';
import 'screens/patient_settings_page.dart';
import 'headsapp_theme.dart';
import 'services/api_service.dart';
import 'services/push_notification_service.dart';
import 'services/patient_reply_notification_service.dart';
import 'services/webrtc_service.dart';
import 'widgets/patient_logout_dialog.dart';
import 'utils/patient_session_utils.dart';
import 'utils/patient_ui_utils.dart';

class EspacePatientPage extends StatefulWidget {
  const EspacePatientPage({
    super.key,
    required this.patientName,
    required this.patientId,
  });

  final String patientName;
  final String patientId;

  @override
  State<EspacePatientPage> createState() => _EspacePatientPageState();
}

class _EspacePatientPageState extends State<EspacePatientPage> with WidgetsBindingObserver {
  bool _notificationsEnabled = true;
  late String _patientName;
  String? _patientPhotoPath;
  // Le profil est accessible via Paramètres uniquement.

  late final PatientReplyNotificationService _replyNotifService;
  late final AudioPlayer _replyNotifPlayer;
  bool _replyNotifSoundInFlight = false;
  Timer? _teleconsultReminderTimer;
  final Set<String> _remindedTeleconsultKeys = <String>{};
  StreamSubscription<Map<String, dynamic>>? _teleconsultReqDecisionSub;
  StreamSubscription<Map<String, dynamic>>? _teleconsultFormDecisionSub;
  StreamSubscription<Map<String, dynamic>>? _patientRdvNotifSub;
  StreamSubscription<Map<String, dynamic>>? _patientChatSessionReopenedSub;
  StreamSubscription<Map<String, dynamic>>? _inboxNewMsgSub;

  /// Alertes « Répondre par message » visibles dans la cloche (hors chat).
  final List<_PendingDoctorReply> _pendingDoctorReplies = [];
  int _unreadNotificationCount = 0;
  int _inboxMessageBadge = 0;

  static const String _replyNotifSoundUrl =
      'https://actions.google.com/sounds/v1/alarms/digital_watch_alarm_long.ogg';
  static const String _messageNotifSoundUrl =
      'https://actions.google.com/sounds/v1/alarms/digital_watch_alarm_short.ogg';

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
    _patientName = readablePatientName(widget.patientName);
    _replyNotifService = PatientReplyNotificationService(widget.patientId);
    _replyNotifPlayer = AudioPlayer();
    _loadPatientPhoto();
    WebRtcService.instance.connectSocket(
      selfUserId: widget.patientId,
      jwtToken: ApiService.jwtToken,
    );
    _teleconsultReqDecisionSub = WebRtcService.instance.teleconsultRequestDecisions
        .listen((p) => _onTeleconsultDecisionEvent(p, isForm: false));
    _teleconsultFormDecisionSub = WebRtcService.instance.teleconsultFormDecisions
        .listen((p) => _onTeleconsultDecisionEvent(p, isForm: true));
    _patientRdvNotifSub = WebRtcService.instance.patientRdvNotifications
        .listen(_onPatientRdvNotificationEvent);
    _patientChatSessionReopenedSub = WebRtcService.instance
        .patientChatSessionReopenedEvents
        .listen(_onPatientChatSessionReopened);
    _inboxNewMsgSub = WebRtcService.instance.patientInboxNewMessageEvents.listen((_) {
      if (!mounted) return;
      // Ne pas incrémenter localement (+1) : ça laissait un « 1 » fantôme si l’API
      // annonçait déjà 0 non lu. La source de vérité est GET /patient/conversations.
      _syncInboxBadgeFromApi();
      _playReplyNotificationSound(isMessage: true);
    });
    _syncInboxBadgeFromApi();
    _replyNotifService.start(
      interval: const Duration(seconds: 3),
      notificationsEnabled: () => _notificationsEnabled,
      onDoctorReplyByMessage: _onDoctorReplyByMessageOutsideChat,
      onTeleconsultScheduled: _onTeleconsultScheduledOutsideChat,
    );
    _startTeleconsultReminderLoop();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _teleconsultReminderTimer?.cancel();
    _teleconsultReqDecisionSub?.cancel();
    _teleconsultFormDecisionSub?.cancel();
    _patientRdvNotifSub?.cancel();
    _patientChatSessionReopenedSub?.cancel();
    _inboxNewMsgSub?.cancel();
    _replyNotifService.dispose();
    _replyNotifPlayer.dispose();
    super.dispose();
  }

  int _sumInboxUnreadFromConversations(List<Map<String, dynamic>> conversations) {
    var total = 0;
    for (final c in conversations) {
      final n = c['unreadCount'];
      if (n is num) {
        total += n.toInt();
      } else if (c['hasUnreadFromDoctor'] == true) {
        total += 1;
      }
    }
    return total.clamp(0, 99);
  }

  Future<void> _syncInboxBadgeFromApi() async {
    try {
      final list = await ApiService.getPatientConversations(patientId: widget.patientId);
      if (!mounted) return;
      setState(() => _inboxMessageBadge = _sumInboxUnreadFromConversations(list));
    } catch (_) {
      // Non bloquant.
    }
  }

  void _decrementInboxMessageBadge([int by = 1]) {
    if (!mounted) return;
    final dec = by < 0 ? 0 : by;
    setState(() => _inboxMessageBadge = (_inboxMessageBadge - dec).clamp(0, 99));
  }

  Future<void> _openPatientDiscussionsFromIcon() async {
    if (!mounted) return;
    await DiscussionsPatientPage.openAsSheet(
      context,
      patientId: widget.patientId,
      patientName: _patientName,
      patientPhotoPath: _patientPhotoPath,
      onConversationOpened: _decrementInboxMessageBadge,
    );
    if (!mounted) return;
    _syncInboxBadgeFromApi();
  }

  Future<void> _openPatientDiscussions() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lastRoute', 'discussions');
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DiscussionsPatientPage(
          patientId: widget.patientId,
          patientName: _patientName,
          patientPhotoPath: _patientPhotoPath,
          onConversationOpened: _decrementInboxMessageBadge,
        ),
      ),
    );
    if (!mounted) return;
    _syncInboxBadgeFromApi();
  }

  void _onPatientChatSessionReopened(Map<String, dynamic> p) {
    if (!mounted) return;
    final cid = p['conversationId']?.toString() ?? '';
    final joined = WebRtcService.instance.joinedConversationId ?? '';
    if (cid.isNotEmpty && cid == joined) return;

    final title = p['title']?.toString() ?? 'Session réouverte 🔓';
    final body = p['body']?.toString() ?? '';
    final openChat = p['openChat'] == true;
    final doctorId = p['doctorId']?.toString() ?? '';
    final doctorName = readableDoctorName(p['doctorName']?.toString());
    final doctorPhotoPath = p['doctorPhotoPath']?.toString();

    _playReplyNotificationSound();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 8),
        backgroundColor: HeadsAppColors.success,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: Colors.white,
              ),
            ),
            if (body.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(body, style: const TextStyle(color: Colors.white)),
            ],
          ],
        ),
        action: openChat && doctorId.isNotEmpty
            ? SnackBarAction(
                label: 'Ouvrir le chat',
                textColor: Colors.white,
                onPressed: () {
                  _decrementInboxMessageBadge();
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ChatPage(
                        patientId: widget.patientId,
                        doctorId: doctorId,
                        doctorName: doctorName,
                        doctorPhotoPath: doctorPhotoPath,
                      ),
                    ),
                  );
                },
              )
            : null,
      ),
    );
  }

  void _onTeleconsultDecisionEvent(Map<String, dynamic> p, {required bool isForm}) {
    if (!mounted || !_notificationsEnabled) return;
    final cid = p['conversationId']?.toString() ?? '';
    final status = p['status']?.toString() ?? '';
    final joined = WebRtcService.instance.joinedConversationId ?? '';
    final requestId = isForm ? '' : (p['requestId']?.toString() ?? '');
    final formId = isForm ? (p['formId']?.toString() ?? '') : '';

    if (status == 'accepted' && cid.isNotEmpty && cid == joined) {
      return;
    }

    final title = p['title']?.toString() ?? 'Téléconsultation';
    final body = p['body']?.toString() ?? '';
    final openChat = p['openChat'] == true;
    final doctorId = p['doctorId']?.toString() ?? '';
    final doctorName = readableDoctorName(p['doctorName']?.toString());
    final doctorPhotoPath = p['doctorPhotoPath']?.toString();

    setState(() {
      final exists = isForm
          ? formId.isNotEmpty &&
              _pendingDoctorReplies.any((e) => e.formId == formId)
          : requestId.isNotEmpty &&
              _pendingDoctorReplies.any((e) => e.requestId == requestId);
      if (!exists) {
        _pendingDoctorReplies.add(
          _PendingDoctorReply(
            conversationId: cid,
            doctorId: doctorId,
            doctorName: doctorName,
            doctorPhotoPath: doctorPhotoPath,
            requestId: requestId.isNotEmpty ? requestId : null,
            formId: formId.isNotEmpty ? formId : null,
            teleconsultDecisionStatus: status,
            decisionTitle: title,
            decisionBody: body,
            openChatOnTap: openChat,
          ),
        );
        _unreadNotificationCount++;
      }
    });
    _playReplyNotificationSound();
  }

  void _onPatientRdvNotificationEvent(Map<String, dynamic> p) {
    if (!mounted || !_notificationsEnabled) return;
    final cid = p['conversationId']?.toString() ?? '';
    final doctorId = p['doctorId']?.toString() ?? '';
    final scheduledAt = p['scheduledAt']?.toString() ?? '';
    if (cid.isEmpty || scheduledAt.isEmpty) return;

    final joined = WebRtcService.instance.joinedConversationId ?? '';
    if (cid.isNotEmpty && cid == joined) return;

    _onTeleconsultScheduledOutsideChat(
      readableDoctorName(p['doctorName']?.toString(), fallback: 'Votre médecin'),
      doctorId,
      cid,
      scheduledAt,
    );
  }

  void _startTeleconsultReminderLoop() {
    _checkTeleconsultReminders();
    _teleconsultReminderTimer?.cancel();
    _teleconsultReminderTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      _checkTeleconsultReminders();
    });
  }

  Future<void> _checkTeleconsultReminders() async {
    if (!_notificationsEnabled) return;
    try {
      final slots = await ApiService.getPatientScheduledTeleconsults(
        patientId: widget.patientId,
      );
      if (!mounted) return;
      final now = DateTime.now();
      for (final s in slots) {
        final iso = s['scheduledAt']?.toString() ?? '';
        final cid = s['conversationId']?.toString() ?? '';
        final doctorName = readableDoctorName(s['doctorName']?.toString(), fallback: 'le médecin');
        if (iso.isEmpty) continue;
        final dt = DateTime.tryParse(iso)?.toLocal();
        if (dt == null) continue;
        final key = '${cid}_$iso';
        if (_remindedTeleconsultKeys.contains(key)) continue;
        final diff = dt.difference(now);
        final mins = diff.inMinutes;
        if (mins >= 0 && mins <= 15) {
          _remindedTeleconsultKeys.add(key);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Rappel: téléconsultation avec $doctorName à ${_formatPendingTime(iso)}',
              ),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 4),
            ),
          );
          _playReplyNotificationSound();
        }
      }
    } catch (_) {
      // Rappel non bloquant.
    }
  }

  Future<void> _playReplyNotificationSound({bool isMessage = false}) async {
    if (!_notificationsEnabled) return;
    if (_replyNotifSoundInFlight) return;
    if (kIsWeb || defaultTargetPlatform == TargetPlatform.android) {
      try {
        await SystemSound.play(SystemSoundType.click);
      } catch (_) {
        // Son fallback non bloquant.
      }
      return;
    }
    _replyNotifSoundInFlight = true;
    try {
      await _replyNotifPlayer.stop();
      await _replyNotifPlayer.play(
        UrlSource(isMessage ? _messageNotifSoundUrl : _replyNotifSoundUrl),
      );
    } catch (_) {
      // Web / réseau : ignorer
    } finally {
      _replyNotifSoundInFlight = false;
    }
  }

  String _formatPendingDate(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    final l = d.toLocal();
    return '${l.day}/${l.month}/${l.year}';
  }

  String _formatPendingTime(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return '--:--';
    final l = d.toLocal();
    final hh = l.hour.toString().padLeft(2, '0');
    final mm = l.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  void _onDoctorReplyByMessageOutsideChat(
    String doctorName,
    String doctorId,
    String conversationId, {
    String? doctorPhotoPath,
  }) {
    if (!mounted) return;
    setState(() {
      final exists = _pendingDoctorReplies.any(
        (e) =>
            e.conversationId == conversationId && e.scheduledAtIso == null,
      );
      if (!exists) {
        _pendingDoctorReplies.add(
          _PendingDoctorReply(
            conversationId: conversationId,
            doctorId: doctorId,
            doctorName: doctorName,
            doctorPhotoPath: doctorPhotoPath,
          ),
        );
        _unreadNotificationCount++;
      }
    });
    // Notification audio + badge sur l’icône cloche uniquement (pas de SnackBar dans l’espace patient).
    _playReplyNotificationSound();
  }

  void _onTeleconsultScheduledOutsideChat(
    String doctorName,
    String doctorId,
    String conversationId,
    String scheduledAtIso, {
    String? doctorPhotoPath,
  }) {
    if (!mounted) return;
    setState(() {
      final exists = _pendingDoctorReplies.any(
        (e) =>
            e.conversationId == conversationId &&
            e.scheduledAtIso == scheduledAtIso,
      );
      if (!exists) {
        _pendingDoctorReplies.add(
          _PendingDoctorReply(
            conversationId: conversationId,
            doctorId: doctorId,
            doctorName: doctorName,
            scheduledAtIso: scheduledAtIso,
            doctorPhotoPath: doctorPhotoPath,
          ),
        );
        _unreadNotificationCount++;
      }
    });
    _playReplyNotificationSound();
  }

  void _openChatFromPending(
    String conversationId,
    String doctorId,
    String doctorName, {
    String? doctorPhotoPath,
  }) {
    _removePending(conversationId);
    _decrementInboxMessageBadge();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatPage(
          patientId: widget.patientId,
          doctorId: doctorId,
          doctorName: doctorName,
          doctorPhotoPath: doctorPhotoPath,
        ),
      ),
    );
  }

  void _removePending(String conversationId) {
    setState(() {
      _pendingDoctorReplies.removeWhere((e) => e.conversationId == conversationId);
      _syncUnreadNotificationCount();
    });
  }

  void _dismissTeleconsultDecisionNotification(_PendingDoctorReply item) {
    setState(() {
      if (item.formId != null && item.formId!.isNotEmpty) {
        _pendingDoctorReplies.removeWhere((e) => e.formId == item.formId);
      } else if (item.requestId != null && item.requestId!.isNotEmpty) {
        _pendingDoctorReplies.removeWhere((e) => e.requestId == item.requestId);
      } else {
        _pendingDoctorReplies.removeWhere(
          (e) =>
              e.conversationId == item.conversationId &&
              e.teleconsultDecisionStatus == item.teleconsultDecisionStatus,
        );
      }
      _syncUnreadNotificationCount();
    });
  }

  void _syncUnreadNotificationCount() {
    _unreadNotificationCount =
        _pendingDoctorReplies.where((e) => e.isNew).length;
  }

  _PendingDoctorReply? _findPendingByNotificationId(String id) {
    for (final item in _pendingDoctorReplies) {
      if (item.notificationId == id) return item;
    }
    return null;
  }

  PatientNotificationEntry _notificationEntryFromPending(
    _PendingDoctorReply item,
  ) {
    if (item.teleconsultDecisionStatus == 'accepted') {
      return PatientNotificationEntry(
        id: item.notificationId,
        type: PatientNotificationType.accepted,
        title: item.decisionTitle ?? 'Demande acceptée',
        description: item.decisionBody?.isNotEmpty == true
            ? item.decisionBody!
            : '${item.doctorName} a validé votre demande de suivi.',
        timestamp: item.createdAt,
        isNew: item.isNew,
      );
    }
    if (item.teleconsultDecisionStatus == 'rejected') {
      return PatientNotificationEntry(
        id: item.notificationId,
        type: PatientNotificationType.rejected,
        title: item.decisionTitle ?? 'Demande refusée',
        description: item.decisionBody?.isNotEmpty == true
            ? item.decisionBody!
            : '${item.doctorName} n\'a pas pu accepter votre demande.',
        timestamp: item.createdAt,
        isNew: item.isNew,
      );
    }
    if (item.scheduledAtIso != null) {
      return PatientNotificationEntry(
        id: item.notificationId,
        type: PatientNotificationType.teleconsult,
        title: 'Demande de téléconsultation',
        description:
            '${item.doctorName} propose un créneau pour le ${_formatPendingDate(item.scheduledAtIso!)} à ${_formatPendingTime(item.scheduledAtIso!)}.',
        timestamp: item.createdAt,
        isNew: item.isNew,
      );
    }
    return PatientNotificationEntry(
      id: item.notificationId,
      type: PatientNotificationType.message,
      title: 'Nouveau message',
      description:
          '${item.doctorName} vous a répondu — ouvrir la discussion.',
      timestamp: item.createdAt,
      isNew: item.isNew,
    );
  }

  void _openNotificationsPanel() {
    final entries = _pendingDoctorReplies
        .map(_notificationEntryFromPending)
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    Navigator.of(context)
        .push<void>(
      MaterialPageRoute<void>(
        builder: (_) => PatientNotificationsScreen(
          items: entries,
          onMarkAllAsRead: () {
            setState(() {
              for (final item in _pendingDoctorReplies) {
                item.isNew = false;
              }
              _unreadNotificationCount = 0;
            });
          },
          onItemTap: (entry) {
            final item = _findPendingByNotificationId(entry.id);
            if (item == null) return;
            setState(() {
              item.isNew = false;
              _syncUnreadNotificationCount();
            });
            Navigator.of(context).pop();
            if (item.openChatOnTap && item.doctorId.isNotEmpty) {
              _openChatFromPending(
                item.conversationId,
                item.doctorId,
                item.doctorName,
                doctorPhotoPath: item.doctorPhotoPath,
              );
            } else {
              _dismissTeleconsultDecisionNotification(item);
            }
          },
        ),
      ),
    )
        .then((_) {
      if (mounted) {
        setState(_syncUnreadNotificationCount);
      }
    });
  }

  static const Color _primary = HeadsAppColors.brandAccent;
  static const Color _primaryDark = HeadsAppColors.brandPrimary;
  static const Color _surface = Color(0xFFF1F5F9);
  static const Color _navy = Color(0xFF1A2B48);
  static const Color _onSurface = _navy;
  static const Color _onSurfaceVariant = Color(0xFF718096);
  static const Color _accentRed = HeadsAppColors.danger;
  static const Color _urgencePink = Color(0xFFFCE7F3);
  static const Color _urgencePinkText = Color(0xFFBE185D);

  void _openUrgence() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BlocUrgencePage(
          patientName: _patientName,
          patientId: widget.patientId,
        ),
      ),
    );
  }

  Widget _headerIconButton({
    required IconData icon,
    required VoidCallback onPressed,
    required String tooltip,
    Color? iconColor,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(),
        elevation: 0,
        shadowColor: Colors.black.withValues(alpha: 0.06),
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(
              icon,
              size: 22,
              color: iconColor ?? _navy,
            ),
          ),
        ),
      ),
    );
  }

  void _openParametres() {
    Navigator.of(context)
        .push<void>(
      MaterialPageRoute<void>(
        builder: (_) => PatientSettingsPage(
          patientId: widget.patientId,
          patientName: _patientName,
          patientPhotoPath: _patientPhotoPath,
          unreadNotificationCount: _unreadNotificationCount,
          onOpenNotifications: _openNotificationsPanel,
        ),
      ),
    )
        .then((_) {
      if (mounted) _loadPatientPhoto();
    });
  }

  Future<void> _loadPatientPhoto() async {
    try {
      final profile = await ApiService.getPatientProfile(patientId: widget.patientId);
      if (!mounted) return;
      final readableName = readablePatientName(
        profile['fullName'] as String?,
        fallback: _patientName,
      );
      setState(() {
        _patientPhotoPath = profile['photoPath'] as String?;
        _patientName = readableName;
      });
      await cachePatientNameIfReadable(profile['fullName'] as String?);
    } catch (_) {
      // Pas bloquant : si la photo échoue à charger, on garde l'avatar par défaut.
    }
  }

  String? _patientPhotoUrl() =>
      ApiService.resolveMediaUrlOrNull(_patientPhotoPath);

  Future<void> _confirmerEtDeconnecter() async {
    final confirmed = await showPatientLogoutDialog(context);
    if (confirmed && mounted) {
      _deconnecter();
    }
  }

  void _deconnecter() {
    SharedPreferences.getInstance().then((prefs) async {
      await prefs.remove('patientId');
      await prefs.remove('patientName');
      await PushNotificationService.instance.unregisterCurrentDevice();
      await prefs.remove('patient_jwt');
      ApiService.setJwtToken(null);
      await prefs.remove('lastRoute');
      await prefs.remove('chatDoctorId');
      await prefs.remove('chatDoctorName');
      await prefs.remove('chatDoctorPhotoPath');
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
    });
  }

  Drawer _buildTemplateDrawer() {
    const navy = Color(0xFF1A2B48);
    const logoutBg = Color(0xFFFFE8E8);
    const logoutFg = Color(0xFF8B2E3D);

    Future<void> closeAnd(Future<void> Function() action) async {
      Navigator.of(context).pop();
      await action();
    }

    void closeAndSync(void Function() action) {
      Navigator.of(context).pop();
      action();
    }

    return Drawer(
      backgroundColor: const Color(0xFFFAFBFC),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(28)),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 28),
            Column(
              children: [
                _PatientDrawerAvatar(photoUrl: _patientPhotoUrl()),
                const SizedBox(height: 14),
                Text(
                  _patientName,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: navy,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            const Divider(height: 1, thickness: 1, color: Color(0xFFE8EDF3)),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  _PatientDrawerTile(
                    icon: Icons.medical_services_rounded,
                    label: 'Rechercher un médecin',
                    onTap: () => closeAnd(() async {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setString('lastRoute', 'choix_medecin');
                      if (!mounted) return;
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ChoixMedecinPage(
                            patientName: _patientName,
                            patientId: widget.patientId,
                          ),
                        ),
                      );
                    }),
                  ),
                  _PatientDrawerTile(
                    icon: Icons.calendar_month_rounded,
                    label: 'Mes rendez-vous',
                    onTap: () => closeAnd(() async {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setString('lastRoute', 'rendezvous');
                      if (!mounted) return;
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => RendezVousPatientPage(
                            patientName: _patientName,
                            patientId: widget.patientId,
                          ),
                        ),
                      );
                    }),
                  ),
                  _PatientDrawerTile(
                    icon: Icons.chat_bubble_rounded,
                    label: 'Discussions',
                    onTap: () => closeAnd(_openPatientDiscussions),
                  ),
                  _PatientDrawerTile(
                    icon: Icons.folder_shared_rounded,
                    label: 'Dossier Médical',
                    onTap: () => closeAnd(() async {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setString('lastRoute', 'dossier_medical');
                      if (!mounted) return;
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => DossierMedicalPage(
                            patientId: widget.patientId,
                          ),
                        ),
                      );
                    }),
                  ),
                  _PatientDrawerTile(
                    icon: Icons.monitor_heart_rounded,
                    label: 'Tensiomètre connecté',
                    onTap: () => closeAnd(() async {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setString('lastRoute', 'tensiometre');
                      if (!mounted) return;
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => BloodPressureScreen(
                            patientId: widget.patientId,
                            patientName: _patientName,
                          ),
                        ),
                      );
                    }),
                  ),
                  _PatientDrawerTile(
                    icon: Icons.settings_rounded,
                    label: 'Paramètres',
                    onTap: () => closeAndSync(_openParametres),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Material(
                color: logoutBg,
                borderRadius: BorderRadius.circular(999),
                child: InkWell(
                  onTap: () async {
                    Navigator.of(context).pop();
                    if (!mounted) return;
                    await _confirmerEtDeconnecter();
                  },
                  borderRadius: BorderRadius.circular(999),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.logout_rounded,
                          color: logoutFg,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Se déconnecter',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                color: logoutFg,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surface,
      drawer: _buildTemplateDrawer(),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Row(
                  children: [
                    Builder(
                      builder: (context) => _headerIconButton(
                        icon: Icons.menu_rounded,
                        tooltip: 'Menu',
                        onPressed: () => Scaffold.of(context).openDrawer(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: _primaryDark.withValues(alpha: 0.18),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: _patientPhotoUrl() != null
                            ? Image.network(
                                _patientPhotoUrl()!,
                                fit: BoxFit.cover,
                              )
                            : const Icon(
                                Icons.person_rounded,
                                color: _primaryDark,
                                size: 28,
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Mon espace',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: _navy,
                                  letterSpacing: -0.4,
                                ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Bonjour $_patientName',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: _onSurfaceVariant,
                                  fontWeight: FontWeight.w500,
                                ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Badge(
                      isLabelVisible: _inboxMessageBadge > 0,
                      label: Text(
                        _inboxMessageBadge > 99 ? '99+' : '$_inboxMessageBadge',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      backgroundColor: _primaryDark,
                      child: _headerIconButton(
                        icon: Icons.chat_bubble_rounded,
                        tooltip: 'Messages',
                        iconColor: _navy,
                        onPressed: _openPatientDiscussionsFromIcon,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Badge(
                      isLabelVisible: _unreadNotificationCount > 0,
                      label: Text(
                        '$_unreadNotificationCount',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      backgroundColor: _accentRed,
                      child: _headerIconButton(
                        icon: _unreadNotificationCount > 0
                            ? Icons.notifications_active_rounded
                            : Icons.notifications_rounded,
                        tooltip: 'Notifications',
                        iconColor:
                            _unreadNotificationCount > 0 ? _accentRed : _navy,
                        onPressed: _openNotificationsPanel,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Material(
                    color: _urgencePink,
                    borderRadius: BorderRadius.circular(999),
                    child: InkWell(
                      onTap: _openUrgence,
                      borderRadius: BorderRadius.circular(999),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Text(
                          'Urgence',
                          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                color: _urgencePinkText,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  childAspectRatio: 0.84,
                ),
                delegate: SliverChildListDelegate(
                  [
                    _MenuCard(
                      icon: Icons.medical_services_rounded,
                      title: 'Rechercher un médecin',
                      subtitle:
                          'Recherche par spécialité, nom, gouvernorat ou position',
                      accentColor: _primaryDark,
                      iconBackgroundColor: _primaryDark.withValues(alpha: 0.1),
                      onTap: () async {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setString('lastRoute', 'choix_medecin');
                        if (!context.mounted) return;
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => ChoixMedecinPage(
                              patientName: _patientName,
                              patientId: widget.patientId,
                            ),
                          ),
                        );
                      },
                    ),
                    _MenuCard(
                      icon: Icons.calendar_month_rounded,
                      title: 'Mes rendez-vous',
                      subtitle: 'Calendrier de vos téléconsultations',
                      accentColor: const Color(0xFF0EA5E9),
                      iconBackgroundColor: const Color(0xFF0EA5E9).withValues(alpha: 0.12),
                      onTap: () async {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setString('lastRoute', 'rendezvous');
                        if (!context.mounted) return;
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => RendezVousPatientPage(
                              patientName: _patientName,
                              patientId: widget.patientId,
                            ),
                          ),
                        );
                      },
                    ),
                    _MenuCard(
                      icon: Icons.chat_bubble_rounded,
                      title: 'Discussions',
                      subtitle: 'Vos échanges avec les médecins',
                      accentColor: _primaryDark,
                      iconBackgroundColor: _primaryDark.withValues(alpha: 0.1),
                      onTap: () async {
                        await _openPatientDiscussions();
                      },
                    ),
                    _MenuCard(
                      icon: Icons.folder_shared_rounded,
                      title: 'Dossier Médical',
                      subtitle: 'Fichiers et images de vos discussions',
                      accentColor: _accentRed,
                      iconBackgroundColor: _accentRed.withValues(alpha: 0.1),
                      onTap: () async {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setString('lastRoute', 'dossier_medical');
                        if (!context.mounted) return;
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => DossierMedicalPage(
                              patientId: widget.patientId,
                            ),
                          ),
                        );
                      },
                    ),
                    _MenuCard(
                      icon: Icons.monitor_heart_rounded,
                      title: 'Tensiomètre connecté',
                      subtitle: 'Mesures, historique et alertes',
                      accentColor: _primaryDark,
                      iconBackgroundColor: _primaryDark.withValues(alpha: 0.1),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => BloodPressureScreen(
                              patientId: widget.patientId,
                              patientName: _patientName,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 28)),
          ],
        ),
      ),
    );
  }
}

class _PatientDrawerAvatar extends StatelessWidget {
  const _PatientDrawerAvatar({this.photoUrl});

  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF1A2B48);
    return Container(
      width: 88,
      height: 88,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFE879A9),
            Color(0xFF4A89DC),
          ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
          child: ClipOval(
            child: photoUrl != null
                ? Image.network(photoUrl!, fit: BoxFit.cover)
                : const Center(
                    child: Icon(
                      Icons.person_rounded,
                      color: navy,
                      size: 36,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _PatientDrawerTile extends StatelessWidget {
  const _PatientDrawerTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF1A2B48);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: navy, size: 24),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: navy,
                        fontWeight: FontWeight.w600,
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

class _PendingDoctorReply {
  _PendingDoctorReply({
    required this.conversationId,
    required this.doctorId,
    required this.doctorName,
    this.scheduledAtIso,
    this.doctorPhotoPath,
    this.requestId,
    this.formId,
    this.teleconsultDecisionStatus,
    this.decisionTitle,
    this.decisionBody,
    this.openChatOnTap = true,
    DateTime? createdAt,
    this.isNew = true,
  }) : createdAt = createdAt ?? DateTime.now();

  final String conversationId;
  final String doctorId;
  final String doctorName;
  /// Non null = notification « date de téléconsultation ».
  final String? scheduledAtIso;
  final String? doctorPhotoPath;
  /// Déduplication des décisions demande (`patient:teleconsult_request_decision`).
  final String? requestId;
  /// Déduplication des décisions formulaire (`patient:teleconsult_form_decision`).
  final String? formId;
  /// `accepted` | `rejected` — décision sur une demande de téléconsultation.
  final String? teleconsultDecisionStatus;
  final String? decisionTitle;
  final String? decisionBody;
  final bool openChatOnTap;
  final DateTime createdAt;
  bool isNew;

  String get notificationId {
    if (formId != null && formId!.isNotEmpty) return 'form_$formId';
    if (requestId != null && requestId!.isNotEmpty) return requestId!;
    if (scheduledAtIso != null) {
      return '${conversationId}_$scheduledAtIso';
    }
    return '${conversationId}_message';
  }
}

class _MenuCard extends StatelessWidget {
  const _MenuCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.accentColor,
    required this.iconBackgroundColor,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color accentColor;
  final Color iconBackgroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A2B48).withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 18, 14, 16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: iconBackgroundColor,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: accentColor, size: 24),
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF1A2B48),
                        height: 1.2,
                        letterSpacing: -0.2,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF718096),
                        height: 1.35,
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
