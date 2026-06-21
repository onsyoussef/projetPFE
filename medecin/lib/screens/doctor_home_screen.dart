import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../agenda_page.dart';
import '../chat_medecin_page.dart';
import '../headsapp_theme.dart';
import '../login_page.dart';
import '../services/api_service.dart';
import '../services/push_notification_service.dart';
import '../services/webrtc_service.dart';
import '../session_keys.dart';
import '../utils/doctor_notification_dismiss_storage.dart';
import '../utils/doctor_session_utils.dart';
import '../utils/doctor_ui_utils.dart';
import '../utils/doctor_waiting_room_dismiss_storage.dart';
import '../widgets/doctor_notifications_sheet.dart';
import '../widgets/headsapp_message_bubble_icon.dart';
import '../widgets/headsapp_logo_text.dart';
import 'doctor_inbox_screen.dart';
import 'doctor_blood_pressure_screen.dart';
import 'doctor_request_workflow_screen.dart';
import 'doctor_settings_screen.dart';
import 'doctor_teleconsult_form_workflow_screen.dart';

class DoctorHomeScreen extends StatefulWidget {
  const DoctorHomeScreen({
    super.key,
    required this.doctorId,
    required this.initialDoctorName,
  });

  final String doctorId;
  final String initialDoctorName;

  @override
  State<DoctorHomeScreen> createState() => _DoctorHomeScreenState();
}

class _DoctorHomeScreenState extends State<DoctorHomeScreen>
    with WidgetsBindingObserver {
  static const Color _dashBg = Color(0xFFF5F9FF);
  static const Color _dashNavy = Color(0xFF0D1B3E);
  static const Color _dashMuted = Color(0xFF757575);
  static const Color _dashIconBlue = Color(0xFF2459A8);
  static const Color _dashChipBg = Color(0xFFE8F0FE);
  static const Color _dashIconTileBg = Color(0xFFE3F2FD);
  static const Color _dashChatBlue = Color(0xFF1A3B70);
  static const Color _primaryDark = HeadsAppColors.brandPrimary;
  static const Color _surface = HeadsAppColors.surfaceSoft;
  static const Color _onSurface = _dashNavy;
  static const Color _onSurfaceVariant = _dashMuted;
  static const Color _accentRed = HeadsAppColors.danger;

  String _displayName = '';
  String? _photoPath;
  List<Map<String, dynamic>> _conversations = [];
  /// conversationId → dernier `lastMessageAt` pris en compte quand le médecin a effacé / ouvert les notifs.
  Map<String, String> _dismissedNotificationAtByConv = {};
  /// Salle d’attente : conversationId → `enteredAtMs` de la session déjà vue / effacée.
  Map<String, String> _dismissedWaitingSessionByConv = {};
  /// Patient actuellement en salle d’attente (événements socket).
  final Map<String, _WaitingRoomActive> _waitingByConv = {};
  StreamSubscription<Map<String, dynamic>>? _waitingRoomSub;
  StreamSubscription<Map<String, dynamic>>? _waitingLeftSub;
  StreamSubscription<Map<String, dynamic>>? _inboxNewMsgSub;
  StreamSubscription<Map<String, dynamic>>? _doctorNotifSub;
  final List<_DoctorNotification> _alertNotifications = [];
  bool _loading = true;
  int _badgeDemande = 0;
  int _badgeForm = 0;
  /// Messages non lus (patient) — incrément socket, remis à jour par l’API, effacé à l’ouverture de l’inbox.
  int _inboxMessageBadge = 0;
  Timer? _badgePollTimer;
  late final AudioPlayer _notifPlayer;
  bool _notifSoundInFlight = false;
  static const String _notifSoundUrl =
      'https://actions.google.com/sounds/v1/alarms/digital_watch_alarm_long.ogg';
  static const String _messageNotifSoundUrl =
      'https://actions.google.com/sounds/v1/alarms/digital_watch_alarm_short.ogg';

  Future<void> _promptLogout() async {
    Navigator.of(context).pop();
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => const _DoctorLogoutDialog(),
    );
    if (confirmed == true && mounted) {
      await _logout();
    }
  }

  Future<void> _logout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await PushNotificationService.instance.unregisterCurrentDevice();
      await prefs.remove(kSessionDoctorIdKey);
      await prefs.remove(kSessionDoctorNameKey);
      await prefs.remove(kSessionDoctorTokenKey);
      ApiService.setJwtToken(null);
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (_) => false,
    );
  }

  int _sumInboxUnreadFromConversations(List<Map<String, dynamic>> convs) {
    var n = 0;
    for (final c in convs) {
      final u = c['unreadCount'];
      if (u is int) {
        n += u;
      } else if (u is num) {
        n += u.toInt();
      } else if (c['hasUnreadFromPatient'] == true) {
        n += 1;
      }
    }
    return n.clamp(0, 999);
  }

  Future<void> _syncInboxBadgeFromApi() async {
    if (widget.doctorId.isEmpty) return;
    try {
      final list = await ApiService.getDoctorConversations(doctorId: widget.doctorId);
      if (!mounted) return;
      setState(() {
        _inboxMessageBadge = _sumInboxUnreadFromConversations(list);
      });
    } catch (_) {}
  }

  Future<void> _refreshBadgesOnly() async {
    if (widget.doctorId.isEmpty) {
      if (mounted) {
        setState(() {
          _badgeDemande = 0;
          _badgeForm = 0;
          _inboxMessageBadge = 0;
        });
      }
      return;
    }
    try {
      final stats =
          await ApiService.getDoctorTeleconsultStats(widget.doctorId);
      if (!mounted) return;
      final req = stats['requests'];
      final frm = stats['forms'];
      int nCount(dynamic v) {
        if (v is int) return v;
        if (v is num) return v.toInt();
        return int.tryParse(v?.toString() ?? '') ?? 0;
      }

      setState(() {
        _badgeDemande = req is Map ? nCount(req['pending']) : 0;
        _badgeForm = frm is Map ? nCount(frm['awaitingDoctorAction']) : 0;
      });
    } catch (_) {
      // Garde les compteurs affichés précédemment si l’API échoue.
    }
  }

  Future<void> _refresh() async {
    if (widget.doctorId.isEmpty) {
      setState(() {
        _loading = false;
        _badgeDemande = 0;
        _badgeForm = 0;
        _inboxMessageBadge = 0;
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        ApiService.getDoctorProfile(widget.doctorId),
        ApiService.getDoctorConversations(doctorId: widget.doctorId),
      ]);
      if (!mounted) return;
      final profile = results[0] as Map<String, dynamic>;
      final convList = results[1] as List<Map<String, dynamic>>;
      List<Map<String, dynamic>> waitingItems = [];
      try {
        waitingItems =
            await ApiService.getDoctorWaitingRooms(doctorId: widget.doctorId);
      } catch (_) {}
      final dismissed = await DoctorNotificationDismissStorage.getMap(
        widget.doctorId,
      );
      final waitingDismissed =
          await DoctorWaitingRoomDismissStorage.getMap(widget.doctorId);
      if (!mounted) return;
      setState(() {
        _displayName = readableDoctorName(
          profile['fullName']?.toString(),
          fallback: readableDoctorName(widget.initialDoctorName),
        );
        _photoPath = profile['photoPath']?.toString();
        _conversations = convList;
        _inboxMessageBadge = _sumInboxUnreadFromConversations(convList);
        _dismissedNotificationAtByConv = dismissed;
        _dismissedWaitingSessionByConv = waitingDismissed;
        _waitingByConv.clear();
        for (final w in waitingItems) {
          final cid = w['conversationId']?.toString() ?? '';
          if (cid.isEmpty) continue;
          final name = readablePatientName(w['patientName']?.toString());
          final rawAt = w['enteredAt']?.toString();
          final dt = DateTime.tryParse(rawAt ?? '');
          final ms = dt?.millisecondsSinceEpoch ??
              DateTime.now().millisecondsSinceEpoch;
          _waitingByConv[cid] = _WaitingRoomActive(
            patientName: name,
            enteredAtMs: ms,
            patientId: w['patientId']?.toString(),
          );
        }
        _loading = false;
      });
      await cacheDoctorNameIfReadable(_displayName);
      await _refreshBadgesOnly();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _displayName = readableDoctorName(widget.initialDoctorName);
        _loading = false;
      });
      await _refreshBadgesOnly();
    }
  }

  Future<void> _persistDismissNotifications(
    List<_DoctorNotification> list,
  ) async {
    if (widget.doctorId.isEmpty || list.isEmpty) return;
    final convUpdates = <String, String>{};
    final waitingUpdates = <String, String>{};
    for (final n in list) {
      if (n.waitingEnteredAt != null) {
        waitingUpdates[n.conversationId] = '${n.waitingEnteredAt}';
        continue;
      }
      for (final c in _conversations) {
        if (c['conversationId']?.toString() == n.conversationId) {
          convUpdates[n.conversationId] = notificationDismissSnapshotIso(c);
          break;
        }
      }
    }
    if (convUpdates.isEmpty && waitingUpdates.isEmpty) return;
    if (!mounted) return;
    setState(() {
      if (convUpdates.isNotEmpty) {
        _dismissedNotificationAtByConv = {
          ..._dismissedNotificationAtByConv,
          ...convUpdates,
        };
      }
      if (waitingUpdates.isNotEmpty) {
        _dismissedWaitingSessionByConv = {
          ..._dismissedWaitingSessionByConv,
          ...waitingUpdates,
        };
      }
    });
    if (convUpdates.isNotEmpty) {
      await DoctorNotificationDismissStorage.merge(widget.doctorId, convUpdates);
    }
    if (waitingUpdates.isNotEmpty) {
      await DoctorWaitingRoomDismissStorage.merge(
        widget.doctorId,
        waitingUpdates,
      );
    }
  }

  bool _conversationQualifiesForDoctorNotification(
    Map<String, dynamic> c,
  ) {
    if (c['urgenceFormulairePending'] == true) return false;
    final lastType = c['lastMessageType']?.toString() ?? '';
    final lastFrom = c['lastMessageFromType']?.toString() ?? '';
    if (lastType != 'request_teleconsult' && lastType != 'form_teleconsult') {
      return false;
    }
    return lastFrom == 'patient' || lastFrom == 'system';
  }

  String? _patientPhotoPathForConversation(String conversationId) {
    for (final c in _conversations) {
      if (c['conversationId']?.toString() == conversationId) {
        return c['patientPhotoPath']?.toString();
      }
    }
    return null;
  }

  List<_DoctorNotification> _visibleNotifications() {
    final out = <_DoctorNotification>[];
    for (final e in _waitingByConv.entries) {
      final cid = e.key;
      final w = e.value;
      if (waitingRoomSessionDismissed(
        cid,
        w.enteredAtMs,
        _dismissedWaitingSessionByConv,
      )) {
        continue;
      }
      out.add(
        _DoctorNotification(
          conversationId: cid,
          title: 'Alerte Urgence — ${w.patientName}',
          subtitle: 'Le patient est en attente de téléconsultation.',
          patientName: w.patientName,
          patientId: w.patientId ?? _patientIdForConversation(cid),
          patientPhotoPath: _patientPhotoPathForConversation(cid),
          waitingEnteredAt: w.enteredAtMs,
          kind: DoctorNotificationVisualKind.urgent,
          occurredAt: DateTime.fromMillisecondsSinceEpoch(w.enteredAtMs),
        ),
      );
    }

    for (final alert in _alertNotifications) {
      out.add(alert);
    }

    for (final c in _conversations) {
      final id = c['conversationId']?.toString() ?? '';
      if (id.isEmpty) continue;
      if (notificationDismissedForConversation(
        c,
        _dismissedNotificationAtByConv,
      )) {
        continue;
      }
      if (!_conversationQualifiesForDoctorNotification(c)) continue;

      final name = readablePatientName(c['patientName']?.toString());
      final last = c['lastMessage']?.toString() ?? '';
      final lastType = c['lastMessageType']?.toString() ?? '';
      final tags = conversationTags(c['tags']);
      final occurredAt = DateTime.tryParse(
        c['lastMessageAt']?.toString() ?? c['updatedAt']?.toString() ?? '',
      );

      final String title;
      final String subtitle;
      final DoctorNotificationVisualKind kind;
      if (lastType == 'request_teleconsult') {
        if (tags.contains('urgent')) {
          kind = DoctorNotificationVisualKind.urgent;
          title = 'Alerte Urgence — $name';
          subtitle = last.isNotEmpty
              ? last
              : 'Intervention requise pour ce patient.';
        } else {
          kind = DoctorNotificationVisualKind.message;
          title = 'Messages — $name';
          subtitle = last.isNotEmpty
              ? last
              : '$name vous a envoyé une demande de téléconsultation.';
        }
      } else {
        kind = DoctorNotificationVisualKind.analysis;
        title = 'Analyses Reçues — $name';
        subtitle = last.isNotEmpty
            ? last
            : 'Les résultats sont disponibles dans son dossier.';
      }

      out.add(
        _DoctorNotification(
          conversationId: id,
          title: title,
          subtitle: subtitle,
          patientName: name,
          patientId: c['patientId']?.toString(),
          patientPhotoPath: c['patientPhotoPath']?.toString(),
          kind: kind,
          occurredAt: occurredAt,
        ),
      );
    }
    return out;
  }

  Future<void> _refreshConversationsOnly() async {
    if (widget.doctorId.isEmpty) return;
    try {
      final list =
          await ApiService.getDoctorConversations(doctorId: widget.doctorId);
      if (!mounted) return;
      setState(() => _conversations = list);
    } catch (_) {}
  }

  void _handleDoctorNotification(Map<String, dynamic> data) {
    if (!mounted) return;
    final type = data['type']?.toString() ?? '';
    switch (type) {
      case 'teleconsult_request':
      case 'teleconsult_form':
        unawaited(_refreshConversationsOnly());
        unawaited(_refreshBadgesOnly());
        _playNotificationSound(isMessage: type == 'teleconsult_form');
        break;
      case 'blood_pressure_alert':
        final patientName =
            readablePatientName(data['patientName']?.toString());
        final patientId = data['patientId']?.toString() ?? '';
        final alertId = data['alertId']?.toString() ?? '';
        final conversationId = data['conversationId']?.toString() ?? '';
        final body = data['body']?.toString() ?? '';
        setState(() {
          _alertNotifications.removeWhere(
            (n) => n.sheetId == 'bp-$alertId' || n.sheetId == 'bp-$patientId-$alertId',
          );
          _alertNotifications.insert(
            0,
            _DoctorNotification(
              conversationId: conversationId.isNotEmpty
                  ? conversationId
                  : 'bp-$patientId',
              title: 'Alerte tension — $patientName',
              subtitle: body.isNotEmpty
                  ? body
                  : 'Nouvelle alerte tensiomètre pour ce patient.',
              patientName: patientName,
              patientId: patientId.isEmpty ? null : patientId,
              kind: DoctorNotificationVisualKind.urgent,
              occurredAt: DateTime.now(),
              alertDismissId: alertId.isNotEmpty ? alertId : patientId,
            ),
          );
        });
        _playNotificationSound();
        break;
      case 'waiting_room':
        // Le flux consultation:patient_waiting gère déjà l’UI salle d’attente.
        break;
      default:
        break;
    }
  }

  void _bindWaitingRoomStreams() {
    if (widget.doctorId.isEmpty) return;
    WebRtcService.instance.connectSocket(
      selfUserId: widget.doctorId,
      jwtToken: ApiService.jwtToken,
    );
    _waitingRoomSub?.cancel();
    _waitingRoomSub =
        WebRtcService.instance.consultationPatientWaiting.listen((data) {
      final cid = data['conversationId']?.toString() ?? '';
      if (cid.isEmpty) return;
      final name = readablePatientName(data['patientName']?.toString());
      final rawAt = data['enteredAt']?.toString();
      final dt = DateTime.tryParse(rawAt ?? '');
      final ms = dt?.millisecondsSinceEpoch ??
          DateTime.now().millisecondsSinceEpoch;
      if (!mounted) return;
      setState(() {
        _waitingByConv[cid] = _WaitingRoomActive(
          patientName: name,
          enteredAtMs: ms,
          patientId: data['patientId']?.toString(),
        );
      });
      _playNotificationSound();
    });
    _waitingLeftSub?.cancel();
    _waitingLeftSub =
        WebRtcService.instance.consultationPatientLeftWaiting.listen((data) {
      final cid = data['conversationId']?.toString() ?? '';
      if (cid.isEmpty) return;
      if (!mounted) return;
      setState(() => _waitingByConv.remove(cid));
    });
    _inboxNewMsgSub?.cancel();
    _inboxNewMsgSub =
        WebRtcService.instance.doctorInboxNewMessageEvents.listen((data) {
      if (!mounted) return;
      final notifType = data['notificationType']?.toString() ?? '';
      final isTeleconsult = notifType == 'teleconsult_request' ||
          notifType == 'teleconsult_form';
      if (!isTeleconsult) {
        setState(() {
          _inboxMessageBadge = (_inboxMessageBadge + 1).clamp(0, 99);
        });
        _playNotificationSound(isMessage: true);
      }
      unawaited(_refreshConversationsOnly());
      unawaited(_refreshBadgesOnly());
    });
    _doctorNotifSub?.cancel();
    _doctorNotifSub =
        WebRtcService.instance.doctorNotificationEvents.listen((data) {
      _handleDoctorNotification(data);
    });
  }

  Future<void> _playNotificationSound({bool isMessage = false}) async {
    if (_notifSoundInFlight) return;
    if (kIsWeb || defaultTargetPlatform == TargetPlatform.android) {
      try {
        await SystemSound.play(SystemSoundType.click);
      } catch (_) {
        // Son fallback non bloquant.
      }
      return;
    }
    _notifSoundInFlight = true;
    try {
      await _notifPlayer.stop();
      await _notifPlayer.play(
        UrlSource(isMessage ? _messageNotifSoundUrl : _notifSoundUrl),
      );
    } catch (_) {
      // Son non bloquant (web/réseau/politique autoplay).
    } finally {
      _notifSoundInFlight = false;
    }
  }

  void _decrementInboxMessageBadge([int by = 1]) {
    if (!mounted) return;
    final dec = by < 0 ? 0 : by;
    setState(() {
      _inboxMessageBadge = (_inboxMessageBadge - dec).clamp(0, 99);
    });
  }

  /// Icône messages (tableau de bord) : feuille « Discussions » puis chat au tap — pas l’écran Inbox complet.
  Future<void> _openMessagesDiscussionsSheet() async {
    await showDoctorDiscussionsSheet(
      context,
      doctorId: widget.doctorId,
      doctorName: _displayName.isNotEmpty ? _displayName : 'Médecin',
      onConversationOpened: _decrementInboxMessageBadge,
    );
    if (mounted) await _syncInboxBadgeFromApi();
  }

  /// Menu latéral : page Inbox avec recherche.
  Future<void> _openInboxFullPage() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => DoctorInboxScreen(
          doctorId: widget.doctorId,
          doctorName: _displayName.isNotEmpty ? _displayName : 'Médecin',
        ),
      ),
    );
    if (mounted) await _syncInboxBadgeFromApi();
  }

  Future<void> _openNotificationsPanel() async {
    final nonWaiting = List<_DoctorNotification>.from(
      _visibleNotifications().where((n) => !n.isWaitingRoom),
    );
    await _persistDismissNotifications(nonWaiting);
    if (!mounted) return;

    final visible = List<_DoctorNotification>.from(_visibleNotifications());
    await showDoctorNotificationsSheet(
      context,
      items: visible.map(_notificationToSheetItem).toList(),
      onDismissItem: (item) async {
        _DoctorNotification? match;
        for (final n in _visibleNotifications()) {
          if (n.sheetId == item.id) {
            match = n;
            break;
          }
        }
        if (match != null) {
          if (match.alertDismissId != null) {
            setState(() {
              _alertNotifications.removeWhere(
                (n) => n.alertDismissId == match!.alertDismissId,
              );
            });
          } else {
            await _persistDismissNotifications([match]);
          }
        }
        if (mounted) setState(() {});
      },
      onDismissAll: () async {
        await _persistDismissNotifications(
          List<_DoctorNotification>.from(
            _visibleNotifications().where((n) => !n.isBloodPressureAlert),
          ),
        );
        if (mounted) {
          setState(() => _alertNotifications.clear());
        }
      },
    );
    if (mounted) setState(() {});
  }

  DoctorNotificationSheetItem _notificationToSheetItem(_DoctorNotification n) {
    return DoctorNotificationSheetItem(
      id: n.sheetId,
      kind: n.kind,
      title: n.title,
      subtitle: n.subtitle,
      occurredAt: n.occurredAt,
      dismissible: n.isWaitingRoom || n.isBloodPressureAlert,
      onTap: n.isWaitingRoom
          ? () {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                _openChatFromWaitingNotification(n);
              });
            }
          : n.isBloodPressureAlert
              ? () {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => DoctorBloodPressureScreen(
                          doctorId: widget.doctorId,
                        ),
                      ),
                    );
                  });
                }
              : null,
    );
  }

  void _openCategory(_DoctorHomeCategory cat) {
    void onListConsulted() {
      if (mounted) _refreshBadgesOnly();
    }

    switch (cat) {
      case _DoctorHomeCategory.demande:
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => DoctorTeleconsultRequestsScreen(
              doctorId: widget.doctorId,
              onRefreshHome: _refresh,
              onListConsulted: onListConsulted,
            ),
          ),
        );
        break;
      case _DoctorHomeCategory.formulaire:
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => DoctorTeleconsultFormsScreen(
              doctorId: widget.doctorId,
              onRefreshHome: _refresh,
              onListConsulted: onListConsulted,
            ),
          ),
        );
        break;
    }
  }

  String? _avatarUrl() {
    if (_photoPath == null || _photoPath!.trim().isEmpty) return null;
    return ApiService.resolveMediaUrl(_photoPath);
  }

  Drawer _buildDrawer() {
    final drawerWidth = MediaQuery.sizeOf(context).width * 0.78;
    final displayName =
        (_displayName.isEmpty ? 'médecin' : _displayName).toLowerCase();

    return Drawer(
      width: drawerWidth.clamp(280, 340),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      backgroundColor: Colors.white,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
              decoration: const BoxDecoration(
                color: HeadsAppColors.brandPrimary,
                borderRadius: BorderRadius.only(
                  topRight: Radius.circular(24),
                ),
              ),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 34,
                    backgroundColor: Colors.white,
                    backgroundImage: _avatarUrl() != null
                        ? NetworkImage(_avatarUrl()!)
                        : null,
                    child: _avatarUrl() == null
                        ? Text(
                            doctorInitials(_displayName),
                            style: const TextStyle(
                              color: HeadsAppColors.brandPrimary,
                              fontWeight: FontWeight.w800,
                              fontSize: 22,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    displayName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                      letterSpacing: -0.2,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            _DoctorDrawerTile(
              icon: Icons.inbox_outlined,
              label: 'Inbox',
              onTap: () {
                Navigator.pop(context);
                _openInboxFullPage();
              },
            ),
            _DoctorDrawerTile(
              icon: Icons.calendar_month_outlined,
              label: 'Agenda',
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => AgendaPage(doctorId: widget.doctorId),
                  ),
                );
              },
            ),
            _DoctorDrawerTile(
              icon: Icons.settings_outlined,
              label: 'Paramètres',
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => DoctorSettingsScreen(
                      doctorId: widget.doctorId,
                      doctorName: _displayName,
                    ),
                  ),
                );
              },
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              child: Material(
                color: const Color(0xFFE8EFFA),
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  onTap: _promptLogout,
                  borderRadius: BorderRadius.circular(14),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(
                          Icons.logout_rounded,
                          color: HeadsAppColors.brandPrimary,
                          size: 22,
                        ),
                        SizedBox(width: 10),
                        Text(
                          'Se déconnecter',
                          style: TextStyle(
                            color: HeadsAppColors.brandPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
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

  Widget _buildChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: _dashChipBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: _dashNavy,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }

  String _greetingDoctorLabel() {
    var name = _displayName.trim();
    if (name.isEmpty) return 'Bonjour Docteur';
    name = name.replaceFirst(RegExp(r'^dr\.?\s*', caseSensitive: false), '').trim();
    final first = name.split(RegExp(r'\s+')).first;
    return 'Bonjour Dr. $first';
  }

  Widget _buildMessagesHeaderIcon() {
    return Badge(
      isLabelVisible: _inboxMessageBadge > 0,
      label: Text(
        _inboxMessageBadge > 99 ? '99+' : '$_inboxMessageBadge',
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
      ),
      backgroundColor: _dashIconBlue,
      offset: const Offset(6, -2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _openMessagesDiscussionsSheet,
          customBorder: const CircleBorder(),
          child: const SizedBox(
            width: 40,
            height: 40,
            child: Center(
              child: HeadsAppMessageBubbleIcon(
                size: 24,
                color: _dashChatBlue,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNotificationsHeaderIcon() {
    final notifCount = _visibleNotifications().length;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _openNotificationsPanel,
            customBorder: const CircleBorder(),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                border: Border.all(color: HeadsAppColors.border),
              ),
              alignment: Alignment.center,
              child: Icon(
                notifCount > 0
                    ? Icons.notifications_rounded
                    : Icons.notifications_outlined,
                size: 20,
                color: notifCount > 0
                    ? _accentRed
                    : HeadsAppColors.textPrimary.withValues(alpha: 0.85),
              ),
            ),
          ),
        ),
        if (notifCount > 0)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: HeadsAppColors.danger,
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _displayName = readableDoctorName(widget.initialDoctorName);
    _notifPlayer = AudioPlayer();
    _badgePollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) _refreshBadgesOnly();
    });
    _bindWaitingRoomStreams();
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _badgePollTimer?.cancel();
    _waitingRoomSub?.cancel();
    _waitingLeftSub?.cancel();
    _inboxNewMsgSub?.cancel();
    _doctorNotifSub?.cancel();
    _notifPlayer.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshBadgesOnly();
      _syncInboxBadgeFromApi();
      _syncWaitingRoomsFromServer();
    }
  }

  Future<void> _syncWaitingRoomsFromServer() async {
    if (widget.doctorId.isEmpty) return;
    try {
      final items =
          await ApiService.getDoctorWaitingRooms(doctorId: widget.doctorId);
      if (!mounted) return;
      setState(() {
        _waitingByConv.clear();
        for (final w in items) {
          final cid = w['conversationId']?.toString() ?? '';
          if (cid.isEmpty) continue;
          final name = readablePatientName(w['patientName']?.toString());
          final rawAt = w['enteredAt']?.toString();
          final dt = DateTime.tryParse(rawAt ?? '');
          final ms = dt?.millisecondsSinceEpoch ??
              DateTime.now().millisecondsSinceEpoch;
          _waitingByConv[cid] = _WaitingRoomActive(
            patientName: name,
            enteredAtMs: ms,
            patientId: w['patientId']?.toString(),
          );
        }
      });
    } catch (_) {}
  }

  String? _patientIdForConversation(String conversationId) {
    for (final c in _conversations) {
      if (c['conversationId']?.toString() == conversationId) {
        final p = c['patientId']?.toString();
        if (p != null && p.isNotEmpty) return p;
      }
    }
    return null;
  }

  void _openChatFromWaitingNotification(_DoctorNotification n) {
    final pid = n.patientId ?? _patientIdForConversation(n.conversationId);
    if (pid == null || pid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Impossible d’ouvrir la discussion : patient introuvable pour cette conversation.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ChatMedecinPage(
          conversationId: n.conversationId,
          patientId: pid,
          patientName: n.patientName,
          patientPhotoPath: n.patientPhotoPath,
          doctorId: widget.doctorId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      drawer: _buildDrawer(),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
              child: Row(
                children: [
                  Builder(
                    builder: (ctx) => IconButton(
                      onPressed: () => Scaffold.of(ctx).openDrawer(),
                      icon: const Icon(Icons.menu_rounded, size: 24),
                      color: _dashNavy,
                    ),
                  ),
                  Expanded(
                    child: HeadsAppLogoText(
                      textAlign: TextAlign.center,
                    ),
                  ),
                  _buildMessagesHeaderIcon(),
                  const SizedBox(width: 6),
                  _buildNotificationsHeaderIcon(),
                  const SizedBox(width: 8),
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _dashIconBlue,
                      shape: BoxShape.circle,
                    ),
                    child: ClipOval(
                      child: _avatarUrl() != null
                          ? Image.network(_avatarUrl()!, fit: BoxFit.cover)
                          : Center(
                              child: Text(
                                doctorInitials(_displayName),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _greetingDoctorLabel(),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: _dashNavy,
                          letterSpacing: -0.4,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Voici le récapitulatif de votre journée au cabinet.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: _dashMuted,
                          height: 1.4,
                        ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ColoredBox(
                color: _dashBg,
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: HeadsAppColors.brandPrimary,
                        ),
                      )
                    : RefreshIndicator(
                        color: HeadsAppColors.brandPrimary,
                        onRefresh: _refresh,
                        child: SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildChip('Tableau de bord'),
                              const SizedBox(height: 14),
                              _DoctorHomeDashboardCard(
                                icon: Icons.send_rounded,
                                title: 'Demandes',
                                subtitle:
                                    'Demandes de teleconsultation en attente',
                                count: _badgeDemande,
                                accentColor: _dashIconBlue,
                                iconBackgroundColor: _dashIconTileBg,
                                gradientColors: const [
                                  Color(0xFFFFFFFF),
                                  Color(0xFFE0E6ED),
                                ],
                                onTap: () =>
                                    _openCategory(_DoctorHomeCategory.demande),
                              ),
                              const SizedBox(height: 14),
                              _DoctorHomeDashboardCard(
                                icon: Icons.assignment_outlined,
                                title: 'Formulaires',
                                subtitle: 'Formulaires recus a valider',
                                count: _badgeForm,
                                accentColor: _dashIconBlue,
                                iconBackgroundColor: _dashIconTileBg,
                                gradientColors: const [
                                  Color(0xFFFFFFFF),
                                  Color(0xFFD1F2F7),
                                ],
                                onTap: () => _openCategory(
                                  _DoctorHomeCategory.formulaire,
                                ),
                              ),
                              const SizedBox(height: 14),
                              _DoctorHomeDashboardCard(
                                icon: Icons.monitor_heart_outlined,
                                title: 'Tensiomètre connecté',
                                subtitle:
                                    'Mesures patients, alertes et courbe d’évolution',
                                count: 0,
                                accentColor: _dashIconBlue,
                                iconBackgroundColor: _dashIconTileBg,
                                gradientColors: const [
                                  Color(0xFFFFFFFF),
                                  Color(0xFFD6EAF8),
                                ],
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) =>
                                          DoctorBloodPressureScreen(
                                        doctorId: widget.doctorId,
                                      ),
                                    ),
                                  );
                                },
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
}

enum _DoctorHomeCategory { demande, formulaire }

class _WaitingRoomActive {
  _WaitingRoomActive({
    required this.patientName,
    required this.enteredAtMs,
    this.patientId,
  });

  final String patientName;
  final int enteredAtMs;
  final String? patientId;
}

class _DoctorNotification {
  _DoctorNotification({
    required this.conversationId,
    required this.title,
    required this.subtitle,
    required this.patientName,
    required this.kind,
    this.patientId,
    this.patientPhotoPath,
    this.waitingEnteredAt,
    this.occurredAt,
    this.alertDismissId,
  });

  final String conversationId;
  final String title;
  final String subtitle;
  final String patientName;
  final String? patientId;
  final String? patientPhotoPath;
  final DoctorNotificationVisualKind kind;
  final DateTime? occurredAt;
  /// Si non null : notification « salle d’attente » (session identifiée par ce timestamp local).
  final int? waitingEnteredAt;
  final String? alertDismissId;

  bool get isWaitingRoom => waitingEnteredAt != null;
  bool get isBloodPressureAlert => alertDismissId != null;

  String get sheetId {
    if (isWaitingRoom) return 'wr-$conversationId-$waitingEnteredAt';
    if (isBloodPressureAlert) {
      return 'bp-${alertDismissId ?? conversationId}';
    }
    return 'conv-$conversationId';
  }
}

/// Grande carte dashboard (hover + clic) pour mobile/web/desktop.
class _DoctorHomeDashboardCard extends StatefulWidget {
  const _DoctorHomeDashboardCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.count,
    required this.onTap,
    required this.accentColor,
    required this.iconBackgroundColor,
    required this.gradientColors,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final int count;
  final VoidCallback onTap;
  final Color accentColor;
  final Color iconBackgroundColor;
  final List<Color> gradientColors;

  @override
  State<_DoctorHomeDashboardCard> createState() =>
      _DoctorHomeDashboardCardState();
}

class _DoctorHomeDashboardCardState extends State<_DoctorHomeDashboardCard> {
  bool _hovered = false;
  bool _pressed = false;

  bool get _active => _hovered || _pressed;

  @override
  Widget build(BuildContext context) {
    final displayCount = widget.count > 99 ? '99+' : '${widget.count}';
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          height: 120,
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: widget.gradientColors,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: widget.accentColor.withValues(alpha: _active ? 0.22 : 0.1),
            ),
            boxShadow: [
              BoxShadow(
                color: widget.accentColor.withValues(alpha: _active ? 0.14 : 0.08),
                blurRadius: _active ? 20 : 14,
                offset: Offset(0, _active ? 8 : 5),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: widget.iconBackgroundColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(widget.icon, size: 24, color: widget.accentColor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0D1B3E),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: Color(0xFF757575),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    displayCount,
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0D1B3E),
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: widget.accentColor,
                    size: 22,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DoctorDrawerTile extends StatelessWidget {
  const _DoctorDrawerTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      leading: Icon(icon, color: const Color(0xFF1A2740), size: 24),
      title: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF1A2740),
          fontWeight: FontWeight.w600,
          fontSize: 16,
        ),
      ),
      onTap: onTap,
    );
  }
}

class _DoctorLogoutDialog extends StatelessWidget {
  const _DoctorLogoutDialog();

  static const _logoutRed = Color(0xFFE85D5D);

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: Color(0xFFFEE2E2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.logout_rounded,
                color: _logoutRed,
                size: 30,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Déconnexion',
              style: TextStyle(
                color: Color(0xFF1A2740),
                fontWeight: FontWeight.w800,
                fontSize: 20,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Voulez-vous vraiment vous déconnecter ?',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF5F6F86),
                fontSize: 14,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: _logoutRed,
                  boxShadow: [
                    BoxShadow(
                      color: _logoutRed.withValues(alpha: 0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => Navigator.of(context).pop(true),
                    borderRadius: BorderRadius.circular(14),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Center(
                        child: Text(
                          'Déconnexion',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                style: TextButton.styleFrom(
                  backgroundColor: const Color(0xFFF1F3F5),
                  foregroundColor: const Color(0xFF1A2740),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Annuler',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
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
