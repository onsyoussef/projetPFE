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
import '../utils/doctor_category_badge_storage.dart';
import '../utils/doctor_notification_dismiss_storage.dart';
import '../utils/doctor_session_utils.dart';
import '../utils/doctor_ui_utils.dart';
import '../utils/doctor_waiting_room_dismiss_storage.dart';
import '../widgets/headsapp_brand_widgets.dart';
import 'doctor_inbox_screen.dart';
import 'doctor_blood_pressure_screen.dart';
import 'doctor_profile_screen.dart';
import 'doctor_request_workflow_screen.dart';
import 'doctor_settings_screen.dart';
import 'doctor_teleconsult_form_workflow_screen.dart';
import 'doctor_urgence_workflow_screen.dart';

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
  static const Color _primary = HeadsAppColors.brandAccent;
  static const Color _primaryDark = HeadsAppColors.brandPrimary;
  static const Color _surface = HeadsAppColors.surfaceSoft;
  static const Color _onSurface = HeadsAppColors.textPrimary;
  static const Color _onSurfaceVariant = HeadsAppColors.textSecondary;
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
  bool _loading = true;
  int _badgeUrgence = 0;
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
          _badgeUrgence = 0;
          _badgeDemande = 0;
          _badgeForm = 0;
          _inboxMessageBadge = 0;
        });
      }
      return;
    }
    try {
      final results = await Future.wait([
        ApiService.getDoctorUrgenceFormulaires(widget.doctorId),
        ApiService.getDoctorTeleconsultStats(widget.doctorId),
      ]);
      final urgList = results[0] as List<Map<String, dynamic>>;
      final stats = results[1] as Map<String, dynamic>;
      final lastU = await DoctorCategoryBadgeStorage.lastConsultedUtc(
        widget.doctorId,
        DoctorDashboardCategory.urgence,
      );
      if (!mounted) return;
      final req = stats['requests'];
      final frm = stats['forms'];
      int nCount(dynamic v) {
        if (v is int) return v;
        if (v is num) return v.toInt();
        return int.tryParse(v?.toString() ?? '') ?? 0;
      }

      setState(() {
        _badgeUrgence = countDashboardItemsSince(urgList, lastU);
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
        _badgeUrgence = 0;
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

  Future<void> _openProfile() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => DoctorProfileScreen(doctorId: widget.doctorId),
      ),
    );
    if (changed == true) await _refresh();
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
    if (c['urgenceFormulairePending'] == true) return true;
    final lastType = c['lastMessageType']?.toString() ?? '';
    final lastFrom = c['lastMessageFromType']?.toString() ?? '';
    return lastFrom == 'patient' &&
        (lastType == 'request_teleconsult' ||
            lastType == 'form_teleconsult');
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
          title: 'Salle d’attente — ${w.patientName}',
          subtitle: 'Le patient est en attente de téléconsultation.',
          patientName: w.patientName,
          patientId: w.patientId ?? _patientIdForConversation(cid),
          patientPhotoPath: _patientPhotoPathForConversation(cid),
          urgent: false,
          waitingEnteredAt: w.enteredAtMs,
        ),
      );
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
      final pending = c['urgenceFormulairePending'] == true;
      final lastType = c['lastMessageType']?.toString() ?? '';

      final String title;
      final String subtitle;
      var urgent = false;
      if (pending) {
        urgent = true;
        title = 'Urgence — $name';
        subtitle =
            last.isNotEmpty ? last : 'Nouveau formulaire d’urgence à traiter';
      } else if (lastType == 'request_teleconsult') {
        title = 'Demande — $name';
        subtitle =
            last.isNotEmpty ? last : 'Demande de téléconsultation';
      } else {
        title = 'Formulaire — $name';
        subtitle = last.isNotEmpty
            ? last
            : 'Formulaire de téléconsultation reçu';
      }

      out.add(
        _DoctorNotification(
          conversationId: id,
          title: title,
          subtitle: subtitle,
          patientName: name,
          patientId: c['patientId']?.toString(),
          patientPhotoPath: c['patientPhotoPath']?.toString(),
          urgent: urgent,
        ),
      );
    }
    return out;
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
        WebRtcService.instance.doctorInboxNewMessageEvents.listen((_) {
      if (!mounted) return;
      setState(() {
        _inboxMessageBadge = (_inboxMessageBadge + 1).clamp(0, 99);
      });
      _playNotificationSound(isMessage: true);
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
    final h = MediaQuery.of(context).size.height * 0.55;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final itemsToShow =
                List<_DoctorNotification>.from(_visibleNotifications());
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.viewInsetsOf(ctx).bottom
                      .clamp(0.0, double.infinity),
                ),
                child: SizedBox(
                  height: h,
                  child: Column(
                    children: [
                      const SizedBox(height: 8),
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                        child: Row(
                          children: [
                            const Text(
                              'Notifications',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '${itemsToShow.length} notification(s)',
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: itemsToShow.isEmpty
                            ? const Center(
                                child: Text(
                                    'Aucune notification pour le moment.'),
                              )
                            : ListView.separated(
                                itemCount: itemsToShow.length,
                                separatorBuilder: (_, _) =>
                                    const Divider(height: 1),
                                itemBuilder: (_, i) {
                                  final n = itemsToShow[i];
                                  if (n.isWaitingRoom) {
                                    return Dismissible(
                                      key: ValueKey<String>(
                                        'wr-${n.conversationId}-${n.waitingEnteredAt}',
                                      ),
                                      direction: DismissDirection.endToStart,
                                      background: Container(
                                        alignment: Alignment.centerRight,
                                        padding: const EdgeInsets.only(
                                            right: 20),
                                        color: Colors.red.shade100,
                                        child: Icon(
                                          Icons.delete_outline_rounded,
                                          color: Colors.red.shade700,
                                        ),
                                      ),
                                      onDismissed: (_) async {
                                        await _persistDismissNotifications(
                                            [n]);
                                        if (mounted) setState(() {});
                                        setModalState(() {});
                                      },
                                      child: ListTile(
                                        onTap: () {
                                          Navigator.of(sheetCtx).pop();
                                          WidgetsBinding.instance
                                              .addPostFrameCallback((_) {
                                            if (!mounted) return;
                                            _openChatFromWaitingNotification(
                                                n);
                                          });
                                        },
                                        leading: CircleAvatar(
                                          radius: 22,
                                          backgroundColor: _surface,
                                          child: Icon(
                                            Icons.sensor_door_rounded,
                                            color: _primaryDark,
                                            size: 26,
                                          ),
                                        ),
                                        title: Text(n.title),
                                        subtitle: Text(
                                          n.subtitle,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        trailing: IconButton(
                                          tooltip: 'Fermer',
                                          icon: const Icon(Icons.close_rounded),
                                          onPressed: () async {
                                            await _persistDismissNotifications(
                                                [n]);
                                            if (mounted) setState(() {});
                                            setModalState(() {});
                                          },
                                        ),
                                      ),
                                    );
                                  }
                                  return ListTile(
                                    leading: Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        patientAvatarForDoctor(
                                          name: n.patientName,
                                          patientPhotoPath: n.patientPhotoPath,
                                          radius: 22,
                                          backgroundColor: n.urgent
                                              ? Colors.red.shade50
                                              : _surface,
                                          accentColor: n.urgent
                                              ? _accentRed
                                              : _primaryDark,
                                        ),
                                        if (n.urgent)
                                          Positioned(
                                            right: -2,
                                            bottom: -2,
                                            child: Container(
                                              padding: const EdgeInsets.all(1),
                                              decoration: const BoxDecoration(
                                                color: Colors.white,
                                                shape: BoxShape.circle,
                                              ),
                                              child: Icon(
                                                Icons.emergency_rounded,
                                                size: 14,
                                                color: _accentRed,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    title: Text(n.title),
                                    subtitle: Text(
                                      n.subtitle,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  );
                                },
                              ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        child: SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: itemsToShow.isEmpty
                                ? null
                                : () async {
                                    final all = List<_DoctorNotification>.from(
                                        _visibleNotifications());
                                    await _persistDismissNotifications(all);
                                    if (sheetCtx.mounted) {
                                      Navigator.pop(sheetCtx);
                                    }
                                  },
                            child: const Text('Tout effacer'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
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
      case _DoctorHomeCategory.urgence:
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => DoctorUrgenceListScreen(
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
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
              color: _primaryDark,
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: Colors.white,
                    backgroundImage:
                        _avatarUrl() != null ? NetworkImage(_avatarUrl()!) : null,
                    child: _avatarUrl() == null
                        ? Text(
                            doctorInitials(_displayName),
                            style: const TextStyle(
                              color: _primaryDark,
                              fontWeight: FontWeight.w700,
                              fontSize: 22,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _displayName.isEmpty ? 'Médecin' : _displayName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.inbox_rounded),
              title: const Text('Inbox'),
              onTap: () {
                Navigator.pop(context);
                _openInboxFullPage();
              },
            ),
            ListTile(
              leading: const Icon(Icons.calendar_month_rounded),
              title: const Text('Agenda'),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => AgendaPage(doctorId: widget.doctorId),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings_rounded),
              title: const Text('Paramètres'),
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
            ListTile(
              leading: const Icon(Icons.logout_rounded, color: _accentRed),
              title: const Text(
                'Déconnexion',
                style: TextStyle(color: _accentRed),
              ),
              onTap: () {
                Navigator.pop(context);
                _logout();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChip(String text) {
    return HeadsAppStatusBadge(label: text, color: _primaryDark);
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
    final notifCount = _visibleNotifications().length;

    return Scaffold(
      backgroundColor: _surface,
      drawer: _buildDrawer(),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                children: [
                  Builder(
                    builder: (ctx) => IconButton(
                      onPressed: () => Scaffold.of(ctx).openDrawer(),
                      icon: const Icon(Icons.menu_rounded, size: 20),
                      color: _onSurface,
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white,
                        side: const BorderSide(color: HeadsAppColors.border),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: _openProfile,
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: HeadsAppColors.border),
                        boxShadow: [
                          BoxShadow(
                            color: _primary.withValues(alpha: 0.12),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: _avatarUrl() != null
                            ? Image.network(
                                _avatarUrl()!,
                                fit: BoxFit.cover,
                              )
                            : Center(
                                child: Text(
                                  doctorInitials(_displayName),
                                  style: const TextStyle(
                                    color: _primaryDark,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Mon espace',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: _onSurface,
                                letterSpacing: -0.3,
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Bonjour, ${_displayName.isEmpty ? '…' : _displayName}',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: _onSurfaceVariant),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
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
                    child: IconButton(
                      onPressed: _openMessagesDiscussionsSheet,
                      icon: Icon(
                        Icons.chat_bubble_rounded,
                        color: _inboxMessageBadge > 0
                            ? _primaryDark
                            : _onSurface,
                      ),
                      tooltip: 'Messages',
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: _onSurface,
                        side: const BorderSide(color: HeadsAppColors.border),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Badge(
                    isLabelVisible: notifCount > 0,
                    label: Text(
                      '$notifCount',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    backgroundColor: _accentRed,
                    child: IconButton(
                      onPressed: _openNotificationsPanel,
                      icon: Icon(
                        notifCount > 0
                            ? Icons.notifications_active_rounded
                            : Icons.notifications_rounded,
                        color: notifCount > 0 ? _accentRed : _onSurface,
                      ),
                      tooltip: 'Notifications',
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: _onSurface,
                        side: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: _buildChip('Tableau de bord'),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                      child: Column(
                        children: [
                          _DoctorHomeDashboardCard(
                            icon: Icons.emergency_rounded,
                            title: 'Formulaires d’urgence',
                            subtitle: 'Patients prioritaires a traiter rapidement',
                            count: _badgeUrgence,
                            accentColor: _accentRed,
                            onTap: () => _openCategory(_DoctorHomeCategory.urgence),
                          ),
                          const SizedBox(height: 14),
                          _DoctorHomeDashboardCard(
                            icon: Icons.send_rounded,
                            title: 'Demandes',
                            subtitle: 'Demandes de teleconsultation en attente',
                            count: _badgeDemande,
                            accentColor: _primaryDark,
                            onTap: () => _openCategory(_DoctorHomeCategory.demande),
                          ),
                          const SizedBox(height: 14),
                          _DoctorHomeDashboardCard(
                            icon: Icons.assignment_rounded,
                            title: 'Formulaires',
                            subtitle: 'Formulaires recus a valider',
                            count: _badgeForm,
                            accentColor: _primary,
                            onTap: () => _openCategory(_DoctorHomeCategory.formulaire),
                          ),
                          const SizedBox(height: 14),
                          _DoctorHomeDashboardCard(
                            icon: Icons.monitor_heart_rounded,
                            title: 'Tensiomètre connecté',
                            subtitle: 'Mesures patients, alertes et courbe d’évolution',
                            count: 0,
                            accentColor: const Color(0xFF0EA5E9),
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => DoctorBloodPressureScreen(
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
          ],
        ),
      ),
    );
  }
}

enum _DoctorHomeCategory { demande, urgence, formulaire }

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
    this.patientId,
    this.patientPhotoPath,
    this.urgent = false,
    this.waitingEnteredAt,
  });

  final String conversationId;
  final String title;
  final String subtitle;
  final String patientName;
  final String? patientId;
  final String? patientPhotoPath;
  final bool urgent;
  /// Si non null : notification « salle d’attente » (session identifiée par ce timestamp local).
  final int? waitingEnteredAt;

  bool get isWaitingRoom => waitingEnteredAt != null;
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
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final int count;
  final VoidCallback onTap;
  final Color accentColor;

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
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          transformAlignment: Alignment.center,
          transform: Matrix4.diagonal3Values(
            _active ? 1.05 : 1.0,
            _active ? 1.05 : 1.0,
            1.0,
          ),
          height: 124,
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white,
                widget.accentColor.withValues(alpha: _active ? 0.16 : 0.09),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: widget.accentColor.withValues(alpha: _active ? 0.36 : 0.22),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: _active ? 0.16 : 0.08),
                blurRadius: _active ? 24 : 12,
                offset: Offset(0, _active ? 12 : 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: widget.accentColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(widget.icon, size: 27, color: widget.accentColor),
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
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.25,
                        color: const Color(0xFF475569).withValues(alpha: 0.9),
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
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Icon(
                    Icons.arrow_forward_rounded,
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
