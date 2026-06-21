import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../chat_medecin_page.dart';
import '../headsapp_theme.dart';
import '../services/api_service.dart';
import '../utils/doctor_notifications_helper.dart';
import '../utils/doctor_ui_utils.dart';
import '../widgets/headsapp_logo_text.dart';

/// Feuille modale : liste des discussions puis ouverture du chat (sans écran Inbox complet).
Future<void> showDoctorDiscussionsSheet(
  BuildContext parentContext, {
  required String doctorId,
  required String doctorName,
  ValueChanged<int>? onConversationOpened,
}) async {
  await showModalBottomSheet<void>(
    context: parentContext,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) {
      final h = MediaQuery.sizeOf(parentContext).height * 0.72;
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: SizedBox(
          height: h,
          child: _DoctorDiscussionsSheetBody(
            parentContext: parentContext,
            sheetContext: sheetContext,
            doctorId: doctorId,
            doctorName: doctorName,
            onConversationOpened: onConversationOpened,
          ),
        ),
      );
    },
  );
}

class _DoctorDiscussionsSheetBody extends StatefulWidget {
  const _DoctorDiscussionsSheetBody({
    required this.parentContext,
    required this.sheetContext,
    required this.doctorId,
    required this.doctorName,
    this.onConversationOpened,
  });

  final BuildContext parentContext;
  final BuildContext sheetContext;
  final String doctorId;
  final String doctorName;
  final ValueChanged<int>? onConversationOpened;

  @override
  State<_DoctorDiscussionsSheetBody> createState() =>
      _DoctorDiscussionsSheetBodyState();
}

class _DoctorDiscussionsSheetBodyState extends State<_DoctorDiscussionsSheetBody> {
  List<Map<String, dynamic>> _conversations = [];
  bool _loading = true;
  String? _error;
  Map<String, String> _seenConversationMessageAt = <String, String>{};
  final TextEditingController _searchController = TextEditingController();
  _InboxFilter _filter = _InboxFilter.all;
  String? _doctorPhotoPath;
  int _notificationCount = 0;

  String get _seenKey =>
      'doctor_seen_conversation_message_at_${widget.doctorId}';

  static const Color _textSecondary = HeadsAppColors.textSecondary;
  static const Color _borderLight = HeadsAppColors.border;
  static const Color _accent = Color(0xFF2459A8);
  static const Color _searchBg = Color(0xFFF2F4F7);

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    await _loadSeenConversations();
    await _loadDoctorPhoto();
    await _loadNotificationCount();
    await _load();
  }

  Future<void> _loadNotificationCount() async {
    try {
      final n = await countDoctorNotifications(widget.doctorId);
      if (mounted) setState(() => _notificationCount = n);
    } catch (_) {}
  }

  Future<void> _openNotifications() async {
    await showDoctorNotificationsPanel(
      widget.parentContext,
      doctorId: widget.doctorId,
    );
    if (mounted) await _loadNotificationCount();
  }

  Future<void> _loadDoctorPhoto() async {
    try {
      final profile = await ApiService.getDoctorProfile(widget.doctorId);
      if (!mounted) return;
      final photo = profile['photoPath']?.toString();
      if (photo != null && photo.isNotEmpty) {
        setState(() => _doctorPhotoPath = photo);
      }
    } catch (_) {}
  }

  Future<void> _loadSeenConversations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_seenKey);
      if (raw == null || raw.trim().isEmpty) return;
      final data = jsonDecode(raw);
      if (data is! Map) return;
      final parsed = <String, String>{};
      for (final e in data.entries) {
        final k = e.key.toString();
        final v = e.value?.toString() ?? '';
        if (k.isNotEmpty && v.isNotEmpty) parsed[k] = v;
      }
      if (!mounted) return;
      setState(() => _seenConversationMessageAt = parsed);
    } catch (_) {}
  }

  Future<void> _markConversationAsSeen({
    required String conversationId,
    required String lastMessageAt,
  }) async {
    if (conversationId.isEmpty || lastMessageAt.isEmpty) return;
    final updated = Map<String, String>.from(_seenConversationMessageAt);
    updated[conversationId] = lastMessageAt;
    if (mounted) setState(() => _seenConversationMessageAt = updated);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_seenKey, jsonEncode(updated));
    } catch (_) {}
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await ApiService.getDoctorConversations(
        doctorId: widget.doctorId,
        filter: 'all',
      );
      final sorted = List<Map<String, dynamic>>.from(list);
      sorted.sort((a, b) {
        final ad = _DoctorInboxScreenState._conversationSortDate(a);
        final bd = _DoctorInboxScreenState._conversationSortDate(b);
        if (ad == null && bd == null) return 0;
        if (ad == null) return 1;
        if (bd == null) return -1;
        return bd.compareTo(ad);
      });
      if (mounted) {
        setState(() {
          _conversations = sorted;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _conversations = [];
          _loading = false;
        });
      }
    }
  }

  List<Map<String, dynamic>> get _filteredConversations {
    Iterable<Map<String, dynamic>> list = _conversations;
    switch (_filter) {
      case _InboxFilter.newOnes:
        list = list.where((c) {
          final from =
              (c['lastMessageFromType'] as String? ?? '').trim().toLowerCase();
          return from == 'patient' &&
              (c['hasUnreadFromPatient'] as bool? ?? false);
        });
        break;
      case _InboxFilter.unread:
        list = list.where(_isConversationUnread);
        break;
      case _InboxFilter.all:
        break;
    }

    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return list.toList();
    return list.where((c) {
      final patientName =
          readablePatientName(c['patientName'] as String?).toLowerCase();
      final lastMessage = (c['lastMessage'] as String? ?? '').toLowerCase();
      final summary =
          _DoctorInboxScreenState._inboxMessagePreview(c).toLowerCase();
      return patientName.contains(q) ||
          lastMessage.contains(q) ||
          summary.contains(q);
    }).toList();
  }

  bool _isConversationUnread(Map<String, dynamic> c) {
    final conversationId = c['conversationId'] as String? ?? '';
    final hasUnreadFromPatient =
        (c['hasUnreadFromPatient'] as bool?) ?? false;
    final lastMessageAtStr = (c['lastMessageAt'] ?? '').toString();
    final seenAt = _seenConversationMessageAt[conversationId];
    return hasUnreadFromPatient &&
        conversationId.isNotEmpty &&
        lastMessageAtStr.isNotEmpty &&
        seenAt != lastMessageAtStr;
  }

  Widget _buildSheetHeader() {
    final photoUrl = ApiService.resolveMediaUrl(_doctorPhotoPath);
    final initials = doctorInitials(
      widget.doctorName.isNotEmpty ? widget.doctorName : 'Médecin',
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 16, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(widget.sheetContext).pop(),
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            color: _accent,
            padding: const EdgeInsets.all(8),
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
          HeadsAppLogoText(),
          const Spacer(),
          Stack(
            clipBehavior: Clip.none,
            children: [
              _DiscussionsSheetHeaderButton(
                onTap: _openNotifications,
                child: Icon(
                  Icons.notifications_outlined,
                  size: 20,
                  color: HeadsAppColors.textPrimary.withValues(alpha: 0.85),
                ),
              ),
              if (_notificationCount > 0)
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
          ),
          const SizedBox(width: 8),
          _DiscussionsSheetHeaderButton(
            child: photoUrl.isNotEmpty
                ? ClipOval(
                    child: Image.network(
                      photoUrl,
                      width: 36,
                      height: 36,
                      fit: BoxFit.cover,
                    ),
                  )
                : Center(
                    child: Text(
                      initials,
                      style: const TextStyle(
                        color: _accent,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
      child: Row(
        children: [
          _InboxFilterChip(
            label: 'Tous',
            selected: _filter == _InboxFilter.all,
            onTap: () => setState(() => _filter = _InboxFilter.all),
          ),
          const SizedBox(width: 8),
          _InboxFilterChip(
            label: 'Nouveaux',
            selected: _filter == _InboxFilter.newOnes,
            onTap: () => setState(() => _filter = _InboxFilter.newOnes),
          ),
          const SizedBox(width: 8),
          _InboxFilterChip(
            label: 'Non lues',
            selected: _filter == _InboxFilter.unread,
            onTap: () => setState(() => _filter = _InboxFilter.unread),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibleConversations = _filteredConversations;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 10),
        Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFDCE3EC),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
        _buildSheetHeader(),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
          child: Text(
            'Discussions',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: HeadsAppColors.textPrimary,
                  letterSpacing: -0.4,
                ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Rechercher un patient, un médecin...',
              hintStyle: TextStyle(
                color: _textSecondary.withValues(alpha: 0.9),
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
              filled: true,
              fillColor: _searchBg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(999),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(999),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(999),
                borderSide: BorderSide(
                  color: _accent.withValues(alpha: 0.35),
                  width: 1.5,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 14,
              ),
              prefixIcon: Icon(
                Icons.search_rounded,
                color: _textSecondary.withValues(alpha: 0.85),
                size: 22,
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(height: 14),
        _buildFilterChips(),
        const SizedBox(height: 8),
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(
                    color: Color(0xFF0056D2),
                  ),
                )
              : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _error!,
                          style: const TextStyle(color: HeadsAppColors.danger),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : visibleConversations.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.chat_bubble_outline_rounded,
                                size: 56,
                                color: HeadsAppColors.border,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _searchController.text.trim().isNotEmpty
                                    ? 'Aucun résultat pour cette recherche'
                                    : 'Aucune discussion pour le moment',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyLarge
                                    ?.copyWith(color: _textSecondary),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          color: _accent,
                          child: ListView.separated(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            itemCount: visibleConversations.length,
                            separatorBuilder: (_, _) => Divider(
                              height: 1,
                              thickness: 1,
                              color: _borderLight.withValues(alpha: 0.7),
                            ),
                            itemBuilder: (context, index) {
                              final c = visibleConversations[index];
                              final conversationId =
                                  c['conversationId'] as String? ?? '';
                              final patientId =
                                  c['patientId'] as String? ?? '';
                              final patientName =
                                  readablePatientName(c['patientName'] as String?);
                              final patientPhotoPath =
                                  c['patientPhotoPath'] as String? ??
                                      c['photoPath'] as String?;
                              final updatedAt = c['updatedAt'];
                              final messagePreview =
                                  _DoctorInboxScreenState._inboxMessagePreview(c);
                              final unreadCount =
                                  c['unreadCount'] as int? ?? 0;
                              final hasUnreadFromPatient =
                                  (c['hasUnreadFromPatient'] as bool?) ??
                                      (unreadCount > 0);
                              final lastMessageAt = c['lastMessageAt'];
                              final lastMessageAtStr =
                                  (lastMessageAt ?? '').toString();
                              final seenAt =
                                  _seenConversationMessageAt[conversationId];
                              final isUnreadUntilOpen =
                                  hasUnreadFromPatient &&
                                      conversationId.isNotEmpty &&
                                      lastMessageAtStr.isNotEmpty &&
                                      seenAt != lastMessageAtStr;
                              final timeStr =
                                  _DoctorInboxScreenState._formatInboxTime(
                                      lastMessageAt ?? updatedAt);
                              return _ConversationTile(
                                conversationId: conversationId,
                                patientId: patientId,
                                patientName: patientName,
                                patientPhotoPath: patientPhotoPath,
                                messagePreview: messagePreview,
                                timeStr: timeStr,
                                unreadCount: unreadCount,
                                hasUnreadFromPatient: isUnreadUntilOpen,
                                showOnlineIndicator:
                                    _DoctorInboxScreenState._isPatientRecentlyActive(c),
                                showImageIcon:
                                    _DoctorInboxScreenState._lastMessageIsImage(c),
                                doctorId: widget.doctorId,
                                onOpenConversation: () async {
                                  await _markConversationAsSeen(
                                    conversationId: conversationId,
                                    lastMessageAt: lastMessageAtStr,
                                  );
                                },
                                onReturnFromChat: () => _load(),
                                onTapOverride: () async {
                                  await _markConversationAsSeen(
                                    conversationId: conversationId,
                                    lastMessageAt: lastMessageAtStr,
                                  );
                                  final seenNow = unreadCount > 0
                                      ? unreadCount
                                      : (isUnreadUntilOpen ? 1 : 0);
                                  widget.onConversationOpened?.call(seenNow);
                                  if (!widget.sheetContext.mounted) return;
                                  Navigator.of(widget.sheetContext).pop();
                                  if (!widget.parentContext.mounted) return;
                                  await Navigator.of(widget.parentContext)
                                      .push<void>(
                                    MaterialPageRoute<void>(
                                      builder: (_) => ChatMedecinPage(
                                        conversationId: conversationId,
                                        patientId: patientId,
                                        patientName: patientName,
                                        patientPhotoPath: patientPhotoPath,
                                        doctorId: widget.doctorId,
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ),
        ),
      ],
    );
  }
}

/// Liste des discussions médecin–patient (recherche).
class DoctorInboxScreen extends StatefulWidget {
  const DoctorInboxScreen({
    super.key,
    required this.doctorId,
    this.doctorName = '',
    this.embeddedInShell = false,
    this.inboxReloadTick,
  });

  final String doctorId;
  final String doctorName;
  final bool embeddedInShell;
  final ValueNotifier<int>? inboxReloadTick;

  @override
  State<DoctorInboxScreen> createState() => _DoctorInboxScreenState();
}

class _DiscussionsSheetHeaderButton extends StatelessWidget {
  const _DiscussionsSheetHeaderButton({
    required this.child,
    this.onTap,
  });

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(color: HeadsAppColors.border),
      ),
      alignment: Alignment.center,
      child: child,
    );
    if (onTap == null) return box;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: box,
      ),
    );
  }
}

/// Filtre local de la liste des discussions (chips UI).
enum _InboxFilter { all, newOnes, unread }

class _DoctorInboxScreenState extends State<DoctorInboxScreen> {
  List<Map<String, dynamic>> _conversations = [];
  bool _loading = true;
  String? _error;
  final TextEditingController _searchController = TextEditingController();
  Map<String, String> _seenConversationMessageAt = <String, String>{};
  _InboxFilter _filter = _InboxFilter.all;
  String? _doctorPhotoPath;
  int _notificationCount = 0;

  String get _seenConversationMessageAtKey =>
      'doctor_seen_conversation_message_at_${widget.doctorId}';

  static const Color _textSecondary = HeadsAppColors.textSecondary;
  static const Color _borderLight = HeadsAppColors.border;
  static const Color _searchBg = Color(0xFFF2F4F7);
  static const Color _accent = Color(0xFF2459A8);
  static const Color _chipSelected = Color(0xFF1A3D5F);
  static const Color _unreadBadgeBlue = Color(0xFF0066FF);
  static const Color _onlineGreen = Color(0xFF22C55E);

  @override
  void initState() {
    super.initState();
    widget.inboxReloadTick?.addListener(_onInboxReloadTick);
    _boot();
  }

  void _onInboxReloadTick() {
    if (!mounted) return;
    _loadSeenConversations().then((_) {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    widget.inboxReloadTick?.removeListener(_onInboxReloadTick);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    await _loadSeenConversations();
    await _loadDoctorPhoto();
    await _loadNotificationCount();
    await _load();
  }

  Future<void> _loadNotificationCount() async {
    try {
      final n = await countDoctorNotifications(widget.doctorId);
      if (mounted) setState(() => _notificationCount = n);
    } catch (_) {}
  }

  Future<void> _openNotifications() async {
    await showDoctorNotificationsPanel(
      context,
      doctorId: widget.doctorId,
    );
    if (mounted) await _loadNotificationCount();
  }

  Future<void> _loadDoctorPhoto() async {
    try {
      final profile = await ApiService.getDoctorProfile(widget.doctorId);
      if (!mounted) return;
      final photo = profile['photoPath']?.toString();
      if (photo != null && photo.isNotEmpty) {
        setState(() => _doctorPhotoPath = photo);
      }
    } catch (_) {}
  }

  Future<void> _loadSeenConversations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_seenConversationMessageAtKey);
      if (raw == null || raw.trim().isEmpty) return;
      final data = jsonDecode(raw);
      if (data is! Map) return;
      final parsed = <String, String>{};
      for (final e in data.entries) {
        final k = e.key.toString();
        final v = e.value?.toString() ?? '';
        if (k.isNotEmpty && v.isNotEmpty) parsed[k] = v;
      }
      if (!mounted) return;
      setState(() {
        _seenConversationMessageAt = parsed;
      });
    } catch (_) {}
  }

  Future<void> _markConversationAsSeen({
    required String conversationId,
    required String lastMessageAt,
  }) async {
    if (conversationId.isEmpty || lastMessageAt.isEmpty) return;
    final updated = Map<String, String>.from(_seenConversationMessageAt);
    updated[conversationId] = lastMessageAt;
    if (mounted) {
      setState(() {
        _seenConversationMessageAt = updated;
      });
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_seenConversationMessageAtKey, jsonEncode(updated));
    } catch (_) {}
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await ApiService.getDoctorConversations(
        doctorId: widget.doctorId,
        filter: 'all',
      );
      final sorted = List<Map<String, dynamic>>.from(list);
      sorted.sort((a, b) {
        final ad = _conversationSortDate(a);
        final bd = _conversationSortDate(b);
        if (ad == null && bd == null) return 0;
        if (ad == null) return 1;
        if (bd == null) return -1;
        return bd.compareTo(ad);
      });
      if (mounted) {
        setState(() {
          _conversations = sorted;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _conversations = [];
          _loading = false;
        });
      }
    }
  }

  List<Map<String, dynamic>> get _filteredConversations {
    Iterable<Map<String, dynamic>> list = _conversations;
    switch (_filter) {
      case _InboxFilter.newOnes:
        list = list.where((c) {
          final from =
              (c['lastMessageFromType'] as String? ?? '').trim().toLowerCase();
          return from == 'patient' &&
              (c['hasUnreadFromPatient'] as bool? ?? false);
        });
        break;
      case _InboxFilter.unread:
        list = list.where((c) => _isConversationUnread(c));
        break;
      case _InboxFilter.all:
        break;
    }

    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return list.toList();
    return list.where((c) {
      final patientName =
          readablePatientName(c['patientName'] as String?).toLowerCase();
      final lastMessage = (c['lastMessage'] as String? ?? '').toLowerCase();
      final summary = _inboxMessagePreview(c).toLowerCase();
      return patientName.contains(q) ||
          lastMessage.contains(q) ||
          summary.contains(q);
    }).toList();
  }

  bool _isConversationUnread(Map<String, dynamic> c) {
    final conversationId = c['conversationId'] as String? ?? '';
    final hasUnreadFromPatient =
        (c['hasUnreadFromPatient'] as bool?) ?? false;
    final lastMessageAtStr = (c['lastMessageAt'] ?? '').toString();
    final seenAt = _seenConversationMessageAt[conversationId];
    return hasUnreadFromPatient &&
        conversationId.isNotEmpty &&
        lastMessageAtStr.isNotEmpty &&
        seenAt != lastMessageAtStr;
  }

  /// Aperçu court d’une ligne inbox (maquette).
  static String _inboxMessagePreview(Map<String, dynamic> c) {
    final msgType =
        (c['lastMessageType'] as String? ?? 'text').toString().trim().toLowerCase();
    final raw = (c['lastMessage'] as String? ?? '').trim();
    final from =
        (c['lastMessageFromType'] as String? ?? '').trim().toLowerCase();

    if (msgType == 'file') {
      final lower = raw.toLowerCase();
      if (lower.contains('.jpg') ||
          lower.contains('.jpeg') ||
          lower.contains('.png') ||
          lower.contains('.webp') ||
          lower.contains('photo') ||
          lower.contains('image')) {
        return from == 'doctor'
            ? 'Vous avez envoyé une photo'
            : 'a envoyé une photo';
      }
      return from == 'doctor'
          ? 'Vous avez envoyé un fichier'
          : 'a envoyé un fichier';
    }

    if (msgType == 'call_event') {
      return from == 'doctor'
          ? 'Vous avez passé un appel'
          : 'a passé un appel';
    }

    if (raw.isNotEmpty) {
      final line = raw.replaceAll('\n', ' ').trim();
      if (from == 'doctor') {
        return line.length > 52 ? 'Vous : ${line.substring(0, 52)}…' : 'Vous : $line';
      }
      return line.length > 58 ? '${line.substring(0, 58)}…' : line;
    }

    return _inboxActivitySummary(c);
  }

  static bool _isPatientRecentlyActive(Map<String, dynamic> c) {
    final at = _conversationSortDate(c);
    if (at == null) return false;
    final from =
        (c['lastMessageFromType'] as String? ?? '').trim().toLowerCase();
    return from == 'patient' &&
        DateTime.now().difference(at).inMinutes < 45;
  }

  static bool _lastMessageIsImage(Map<String, dynamic> c) {
    final msgType =
        (c['lastMessageType'] as String? ?? '').toString().trim().toLowerCase();
    if (msgType != 'file') return false;
    final raw = (c['lastMessage'] as String? ?? '').toLowerCase();
    return raw.contains('.jpg') ||
        raw.contains('.jpeg') ||
        raw.contains('.png') ||
        raw.contains('.webp') ||
        raw.contains('photo') ||
        raw.contains('image');
  }

  /// Texte lisible : qui a envoyé le dernier message et de quel type il s’agit.
  static String _inboxMessageTypeDescription(String msgType, String rawContent) {
    final t = msgType.trim().toLowerCase();
    switch (t) {
      case 'request_teleconsult':
        return 'demande de téléconsultation';
      case 'teleconsult_scheduled':
        return 'téléconsultation planifiée';
      case 'form_teleconsult':
        return 'formulaire téléconsultation';
      case 'form_teleconsult_prompt':
        return 'demande de remplir un formulaire';
      case 'file':
        if (rawContent.isNotEmpty) return 'fichier : $rawContent';
        return 'fichier ou photo joint(e)';
      case 'call_event':
        return 'appel vocal ou vidéo';
      case 'question_physique':
        return 'question / symptômes';
      case 'teleconsultation':
        return 'message téléconsultation';
      case 'accept_request':
        return rawContent.isNotEmpty ? rawContent : 'demande acceptée';
      case 'text':
      case '':
        return rawContent.isNotEmpty ? rawContent : 'message texte';
      default:
        if (rawContent.isNotEmpty) return rawContent;
        return 'message ($t)';
    }
  }

  static String _inboxActivitySummary(Map<String, dynamic> c) {
    final from =
        (c['lastMessageFromType'] as String? ?? '').trim().toLowerCase();
    final msgType = (c['lastMessageType'] as String? ?? 'text')
        .toString()
        .trim()
        .toLowerCase();
    final raw = (c['lastMessage'] as String? ?? '').trim();
    final tags = (c['tags'] as List<dynamic>?)
            ?.map((e) => e.toString().toLowerCase())
            .toSet() ??
        {};

    final prefix = switch (from) {
      'patient' => 'Le patient vous a envoyé',
      'doctor' => 'Vous avez envoyé',
      _ => 'Dernière activité',
    };

    final extras = <String>[];
    if (tags.contains('urgent')) extras.add('urgence');
    if (tags.contains('demande') && msgType != 'request_teleconsult') {
      extras.add('demande téléconsultation');
    }

    String core;
    if (msgType == 'text' || msgType.isEmpty) {
      core = raw.isNotEmpty ? raw : 'message texte';
    } else {
      final desc = _inboxMessageTypeDescription(msgType, raw);
      if (raw.isNotEmpty &&
          raw != desc &&
          !desc.contains(raw) &&
          raw.length < 100) {
        core = '$desc — $raw';
      } else {
        core = desc;
      }
    }

    var line = '$prefix : $core';
    if (extras.isNotEmpty) {
      line += ' · ${extras.join(' · ')}';
    }
    return line;
  }

  static DateTime? _conversationSortDate(Map<String, dynamic> c) {
    final lastMessageAt = c['lastMessageAt']?.toString() ?? '';
    final updatedAt = c['updatedAt']?.toString() ?? '';
    final d1 = DateTime.tryParse(lastMessageAt);
    if (d1 != null) return d1;
    return DateTime.tryParse(updatedAt);
  }

  static String _formatTimeAgo(dynamic updatedAt) => _formatInboxTime(updatedAt);

  static String _formatInboxTime(dynamic updatedAt) {
    if (updatedAt == null) return '';
    final dt = DateTime.tryParse(updatedAt.toString());
    if (dt == null) return '';
    final local = dt.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDay = DateTime(local.year, local.month, local.day);
    final dayDiff = today.difference(msgDay).inDays;
    if (dayDiff == 0) return DateFormat.Hm('fr_FR').format(local);
    if (dayDiff == 1) return 'Hier';
    if (dayDiff < 7) {
      final day = DateFormat.EEEE('fr_FR').format(local);
      if (day.isEmpty) return day;
      return '${day[0].toUpperCase()}${day.substring(1)}';
    }
    return DateFormat('d MMM', 'fr_FR').format(local);
  }

  Widget _buildAppHeader(BuildContext context) {
    final doctorName = widget.doctorName.isNotEmpty
        ? widget.doctorName
        : 'Médecin';
    final photoUrl = ApiService.resolveMediaUrl(_doctorPhotoPath);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 16, 12),
          child: Row(
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                color: _accent,
                padding: const EdgeInsets.all(8),
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
              const HeadsAppLogoText(),
              const Spacer(),
              Stack(
                clipBehavior: Clip.none,
                children: [
                  _DiscussionsSheetHeaderButton(
                    onTap: _openNotifications,
                    child: const Icon(
                      Icons.notifications_outlined,
                      size: 20,
                      color: HeadsAppColors.textPrimary,
                    ),
                  ),
                  if (_notificationCount > 0)
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
              ),
              const SizedBox(width: 8),
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: _borderLight),
                ),
                child: ClipOval(
                  child: photoUrl.isNotEmpty
                      ? Image.network(photoUrl, fit: BoxFit.cover)
                      : Center(
                          child: Text(
                            doctorInitials(doctorName),
                            style: const TextStyle(
                              color: _accent,
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
        Divider(height: 1, thickness: 1, color: _borderLight.withValues(alpha: 0.7)),
      ],
    );
  }

  Widget _buildFilterChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
      child: Row(
        children: [
          _InboxFilterChip(
            label: 'Tous',
            selected: _filter == _InboxFilter.all,
            onTap: () => setState(() => _filter = _InboxFilter.all),
          ),
          const SizedBox(width: 8),
          _InboxFilterChip(
            label: 'Nouveaux',
            selected: _filter == _InboxFilter.newOnes,
            onTap: () => setState(() => _filter = _InboxFilter.newOnes),
          ),
          const SizedBox(width: 8),
          _InboxFilterChip(
            label: 'Non lues',
            selected: _filter == _InboxFilter.unread,
            onTap: () => setState(() => _filter = _InboxFilter.unread),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibleConversations = _filteredConversations;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        top: !widget.embeddedInShell,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!widget.embeddedInShell) _buildAppHeader(context),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Text(
                'Discussions',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: HeadsAppColors.textPrimary,
                      letterSpacing: -0.4,
                    ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Rechercher un patient, un médecin...',
                  hintStyle: TextStyle(
                    color: _textSecondary.withValues(alpha: 0.9),
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                  filled: true,
                  fillColor: _searchBg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(999),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(999),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(999),
                    borderSide: BorderSide(
                      color: _accent.withValues(alpha: 0.35),
                      width: 1.5,
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: _textSecondary.withValues(alpha: 0.85),
                    size: 22,
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(height: 14),
            _buildFilterChips(),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: _accent))
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.error_outline_rounded,
                                    size: 56, color: Colors.red.shade700),
                                const SizedBox(height: 16),
                                Text(
                                  _error!,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.red.shade900),
                                ),
                                const SizedBox(height: 16),
                                FilledButton.icon(
                                  onPressed: _load,
                                  icon: const Icon(Icons.refresh_rounded),
                                  label: const Text('Réessayer'),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: _accent,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : visibleConversations.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.chat_bubble_outline_rounded,
                                      size: 64, color: Colors.grey.shade400),
                                  const SizedBox(height: 16),
                                  Text(
                                    _searchController.text.trim().isNotEmpty
                                        ? 'Aucun résultat pour cette recherche'
                                        : 'Aucune discussion pour le moment',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyLarge
                                        ?.copyWith(color: _textSecondary),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Les patients qui vous contactent apparaîtront ici.',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(color: _textSecondary),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: _load,
                              color: _accent,
                              child: ListView.separated(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 4),
                                itemCount: visibleConversations.length,
                                separatorBuilder: (context, index) => Divider(
                                  height: 1,
                                  thickness: 1,
                                  color: _borderLight,
                                ),
                                itemBuilder: (context, index) {
                                  final c = visibleConversations[index];
                                  final conversationId =
                                      c['conversationId'] as String? ?? '';
                                  final patientId =
                                      c['patientId'] as String? ?? '';
                                  final patientName =
                                      readablePatientName(c['patientName'] as String?);
                                  final patientPhotoPath =
                                      c['patientPhotoPath'] as String? ??
                                          c['photoPath'] as String?;
                                  final updatedAt = c['updatedAt'];
                                  final messagePreview =
                                      _inboxMessagePreview(c);
                                  final unreadCount =
                                      c['unreadCount'] as int? ?? 0;
                                  final hasUnreadFromPatient =
                                      (c['hasUnreadFromPatient'] as bool?) ??
                                          (unreadCount > 0);
                                  final lastMessageAt = c['lastMessageAt'];
                                  final lastMessageAtStr =
                                      (lastMessageAt ?? '').toString();
                                  final seenAt = _seenConversationMessageAt[
                                      conversationId];
                                  final isUnreadUntilOpen =
                                      hasUnreadFromPatient &&
                                          conversationId.isNotEmpty &&
                                          lastMessageAtStr.isNotEmpty &&
                                          seenAt != lastMessageAtStr;
                                  final timeStr = _formatInboxTime(
                                      lastMessageAt ?? updatedAt);
                                  return _ConversationTile(
                                    conversationId: conversationId,
                                    patientId: patientId,
                                    patientName: patientName,
                                    patientPhotoPath: patientPhotoPath,
                                    messagePreview: messagePreview,
                                    timeStr: timeStr,
                                    unreadCount: unreadCount,
                                    hasUnreadFromPatient: isUnreadUntilOpen,
                                    showOnlineIndicator:
                                        _isPatientRecentlyActive(c),
                                    showImageIcon: _lastMessageIsImage(c),
                                    doctorId: widget.doctorId,
                                    onOpenConversation: () async {
                                      await _markConversationAsSeen(
                                        conversationId: conversationId,
                                        lastMessageAt: lastMessageAtStr,
                                      );
                                    },
                                    onReturnFromChat: () => _load(),
                                  );
                                },
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.conversationId,
    required this.patientId,
    required this.patientName,
    required this.patientPhotoPath,
    required this.messagePreview,
    required this.timeStr,
    required this.unreadCount,
    required this.hasUnreadFromPatient,
    required this.showOnlineIndicator,
    required this.showImageIcon,
    required this.doctorId,
    required this.onOpenConversation,
    required this.onReturnFromChat,
    this.onTapOverride,
  });

  final String conversationId;
  final String patientId;
  final String patientName;
  final String? patientPhotoPath;
  final String messagePreview;
  final String timeStr;
  final int unreadCount;
  final bool hasUnreadFromPatient;
  final bool showOnlineIndicator;
  final bool showImageIcon;
  final String doctorId;
  final Future<void> Function() onOpenConversation;
  final VoidCallback onReturnFromChat;
  /// Si défini : fermeture feuille + navigation gérées ailleurs (ex. tableau de bord).
  final Future<void> Function()? onTapOverride;

  static const Color _textPrimary = HeadsAppColors.textPrimary;
  static const Color _textSecondary = HeadsAppColors.textSecondary;
  static const Color _skyBlue = HeadsAppColors.brandPrimary;
  static const Color _unreadBadgeBlue = Color(0xFF0066FF);
  static const Color _onlineGreen = Color(0xFF22C55E);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: () async {
          if (onTapOverride != null) {
            await onTapOverride!();
            return;
          }
          await onOpenConversation();
          if (!context.mounted) return;
          await Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => ChatMedecinPage(
                conversationId: conversationId,
                patientId: patientId,
                patientName: patientName,
                patientPhotoPath: patientPhotoPath,
                doctorId: doctorId,
              ),
            ),
          );
          onReturnFromChat();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  patientAvatarForDoctor(
                    name: patientName,
                    patientPhotoPath: patientPhotoPath,
                    radius: 26,
                    backgroundColor: _skyBlue.withValues(alpha: 0.14),
                    accentColor: _skyBlue,
                  ),
                  if (showOnlineIndicator)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: _onlineGreen,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      patientName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: hasUnreadFromPatient
                            ? FontWeight.w800
                            : FontWeight.w700,
                        color: _textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (showImageIcon) ...[
                          Icon(
                            Icons.image_outlined,
                            size: 16,
                            color: _textSecondary.withValues(alpha: 0.9),
                          ),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: Text(
                            messagePreview,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              color: hasUnreadFromPatient
                                  ? _textPrimary.withValues(alpha: 0.82)
                                  : _textSecondary,
                              fontWeight: hasUnreadFromPatient
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (timeStr.isNotEmpty)
                    Text(
                      timeStr,
                      style: TextStyle(
                        fontSize: 13,
                        color: _textSecondary,
                        fontWeight: hasUnreadFromPatient
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  if (hasUnreadFromPatient && unreadCount > 0) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: 22,
                      height: 22,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: _unreadBadgeBlue,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        unreadCount > 9 ? '9+' : '$unreadCount',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InboxFilterChip extends StatelessWidget {
  const _InboxFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  static const Color _chipSelected = Color(0xFF1A3D5F);
  static const Color _chipUnselectedBg = Color(0xFFF2F4F7);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? _chipSelected : _chipUnselectedBg,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : HeadsAppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
