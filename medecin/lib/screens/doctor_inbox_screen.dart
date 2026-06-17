import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../chat_medecin_page.dart';
import '../espace_medecin_shell.dart';
import '../headsapp_theme.dart';
import '../services/api_service.dart';
import '../utils/doctor_ui_utils.dart';

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
    backgroundColor: HeadsAppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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

  String get _seenKey =>
      'doctor_seen_conversation_message_at_${widget.doctorId}';

  static const Color _textSecondary = HeadsAppColors.textSecondary;
  static const Color _borderLight = HeadsAppColors.border;
  static const Color _accent = HeadsAppColors.brandPrimary;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    await _loadSeenConversations();
    await _load();
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

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: HeadsAppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(
            children: [
              Text(
                'Discussions',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: _accent,
                    ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                color: _textSecondary,
                onPressed: () => Navigator.of(widget.sheetContext).pop(),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: _accent))
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
                  : _conversations.isEmpty
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
                                'Aucune discussion pour le moment',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyLarge
                                    ?.copyWith(color: _textSecondary),
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          color: _accent,
                          child: ListView.separated(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            itemCount: _conversations.length,
                            separatorBuilder: (_, _) => Divider(
                              height: 1,
                              thickness: 1,
                              color: _borderLight,
                            ),
                            itemBuilder: (context, index) {
                              final c = _conversations[index];
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
                              final activitySummary =
                                  _DoctorInboxScreenState._inboxActivitySummary(
                                      c);
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
                                  _DoctorInboxScreenState._formatTimeAgo(
                                      lastMessageAt ?? updatedAt);
                              return _ConversationTile(
                                conversationId: conversationId,
                                patientId: patientId,
                                patientName: patientName,
                                patientPhotoPath: patientPhotoPath,
                                activitySummary: activitySummary,
                                timeStr: timeStr,
                                unreadCount: unreadCount,
                                hasUnreadFromPatient: isUnreadUntilOpen,
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

class _DoctorInboxScreenState extends State<DoctorInboxScreen> {
  List<Map<String, dynamic>> _conversations = [];
  bool _loading = true;
  String? _error;
  final TextEditingController _searchController = TextEditingController();
  Map<String, String> _seenConversationMessageAt = <String, String>{};

  String get _seenConversationMessageAtKey =>
      'doctor_seen_conversation_message_at_${widget.doctorId}';

  static const Color _textSecondary = HeadsAppColors.textSecondary;
  static const Color _borderLight = HeadsAppColors.border;
  static const Color _searchBg = HeadsAppColors.surfaceMuted;
  static const Color _accent = HeadsAppColors.brandPrimary;

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
    await _load();
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
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return _conversations;
    return _conversations.where((c) {
      final patientName = readablePatientName(c['patientName'] as String?).toLowerCase();
      final lastMessage = (c['lastMessage'] as String? ?? '').toLowerCase();
      final summary = _inboxActivitySummary(c).toLowerCase();
      return patientName.contains(q) ||
          lastMessage.contains(q) ||
          summary.contains(q);
    }).toList();
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

  static String _formatTimeAgo(dynamic updatedAt) {
    if (updatedAt == null) return '';
    final dt = DateTime.tryParse(updatedAt.toString());
    if (dt == null) return '';
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'À l\'instant';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min';
    if (diff.inHours < 24) return '${diff.inHours} h';
    if (diff.inDays == 1) return '1 j';
    if (diff.inDays < 30) return '${diff.inDays} j';
    if (diff.inDays < 365) return '${(diff.inDays / 30).floor()} m';
    return '${(diff.inDays / 365).floor()} an';
  }

  @override
  Widget build(BuildContext context) {
    final visibleConversations = _filteredConversations;
    return Scaffold(
      backgroundColor: HeadsAppColors.surfaceAlt,
      body: SafeArea(
        top: !widget.embeddedInShell,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!widget.embeddedInShell)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded,
                          size: 22),
                      style: IconButton.styleFrom(
                        backgroundColor: HeadsAppColors.surfaceSoft,
                        foregroundColor: _accent,
                      ),
                      onPressed: () async {
                        final didPop = await Navigator.of(context).maybePop();
                        if (didPop || !context.mounted) return;
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute<void>(
                            builder: (_) => EspaceMedecinShell(
                              doctorId: widget.doctorId,
                              doctorName: widget.doctorName.isNotEmpty
                                  ? widget.doctorName
                                  : 'Médecin',
                            ),
                          ),
                        );
                      },
                    ),
                    const Expanded(
                      child: Text(
                        'Messages',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: _accent,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  'Messages',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: _accent,
                      ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText:
                      'Rechercher (nom, texte, type de message…)',
                  hintStyle:
                      const TextStyle(color: _textSecondary, fontSize: 15),
                  filled: true,
                  fillColor: _searchBg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: _borderLight),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: _accent, width: 1.5),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  suffixIcon: const Icon(Icons.search_rounded,
                      color: _accent, size: 22),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(height: 16),
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
                                  final activitySummary =
                                      _DoctorInboxScreenState._inboxActivitySummary(
                                          c);
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
                                  final timeStr = _formatTimeAgo(
                                      lastMessageAt ?? updatedAt);
                                  return _ConversationTile(
                                    conversationId: conversationId,
                                    patientId: patientId,
                                    patientName: patientName,
                                    patientPhotoPath: patientPhotoPath,
                                    activitySummary: activitySummary,
                                    timeStr: timeStr,
                                    unreadCount: unreadCount,
                                    hasUnreadFromPatient: isUnreadUntilOpen,
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
    required this.activitySummary,
    required this.timeStr,
    required this.unreadCount,
    required this.hasUnreadFromPatient,
    required this.doctorId,
    required this.onOpenConversation,
    required this.onReturnFromChat,
    this.onTapOverride,
  });

  final String conversationId;
  final String patientId;
  final String patientName;
  final String? patientPhotoPath;
  final String activitySummary;
  final String timeStr;
  final int unreadCount;
  final bool hasUnreadFromPatient;
  final String doctorId;
  final Future<void> Function() onOpenConversation;
  final VoidCallback onReturnFromChat;
  /// Si défini : fermeture feuille + navigation gérées ailleurs (ex. tableau de bord).
  final Future<void> Function()? onTapOverride;

  static const Color _textPrimary = HeadsAppColors.textPrimary;
  static const Color _textSecondary = HeadsAppColors.textSecondary;
  static const Color _skyBlue = HeadsAppColors.brandPrimary;
  static const Color _unreadBadge = HeadsAppColors.success;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: HeadsAppColors.surface,
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              patientAvatarForDoctor(
                name: patientName,
                patientPhotoPath: patientPhotoPath,
                radius: 28,
                backgroundColor: _skyBlue.withValues(alpha: 0.2),
                accentColor: _skyBlue,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            patientName,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: hasUnreadFromPatient
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              color: _textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (hasUnreadFromPatient && unreadCount > 0) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _unreadBadge,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              unreadCount > 99 ? '99+' : '$unreadCount',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      activitySummary,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: hasUnreadFromPatient
                            ? _textPrimary
                            : _textSecondary,
                        fontWeight: hasUnreadFromPatient
                            ? FontWeight.w600
                            : FontWeight.w500,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (timeStr.isNotEmpty)
                Text(
                  timeStr,
                  style: TextStyle(
                    fontSize: 13,
                    color: hasUnreadFromPatient
                        ? _textPrimary
                        : _textSecondary,
                    fontWeight: hasUnreadFromPatient
                        ? FontWeight.w700
                        : FontWeight.w400,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
