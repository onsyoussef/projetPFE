import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'chat_page.dart';
import 'espace_patient_page.dart';
import 'headsapp_theme.dart';
import 'services/api_service.dart';
import 'utils/patient_ui_utils.dart';

class DiscussionsPatientPage extends StatefulWidget {
  const DiscussionsPatientPage({
    super.key,
    required this.patientId,
    required this.patientName,
    this.patientPhotoPath,
    this.onConversationOpened,
    this.asModalSheet = false,
  });

  final String patientId;
  final String patientName;
  final String? patientPhotoPath;
  final ValueChanged<int>? onConversationOpened;
  final bool asModalSheet;

  /// Ouvre la liste des discussions en panneau modal (icône messages).
  static Future<void> openAsSheet(
    BuildContext context, {
    required String patientId,
    required String patientName,
    String? patientPhotoPath,
    ValueChanged<int>? onConversationOpened,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (ctx) {
        final h = MediaQuery.sizeOf(ctx).height;
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(ctx).bottom,
          ),
          child: SizedBox(
            height: h * 0.68,
            child: DiscussionsPatientPage(
              patientId: patientId,
              patientName: patientName,
              patientPhotoPath: patientPhotoPath,
              onConversationOpened: onConversationOpened,
              asModalSheet: true,
            ),
          ),
        );
      },
    );
  }

  @override
  State<DiscussionsPatientPage> createState() => _DiscussionsPatientPageState();
}

class _DiscussionsPatientPageState extends State<DiscussionsPatientPage> {
  static const String _seenConversationMessageAtKey =
      'patient_seen_conversation_message_at';

  static const Color _titleNavy = Color(0xFF1A458B);
  static const Color _textGrey = Color(0xFF757575);
  static const Color _dividerGrey = Color(0xFFEEEEEE);
  static const Color _avatarBg = Color(0xFFE8F0FE);
  static const Color _avatarIcon = Color(0xFF1A458B);
  static const Color _onlineGreen = Color(0xFF2ECC71);
  static const Color _searchBg = Color(0xFFF1F4F8);
  static const Color _searchBorder = Color(0xFFDDE4EE);
  static const Color _searchHint = Color(0xFF9CA3AF);

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  List<Map<String, dynamic>> _conversations = [];
  Map<String, String> _seenConversationMessageAt = <String, String>{};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text);
    });
    _boot();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    await _loadSeenConversations();
    await _loadConversations();
  }

  static bool _showOnlineDot(String status) => status == 'available';

  List<Map<String, dynamic>> get _filteredConversations {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return _conversations;
    return _conversations.where((item) {
      final name =
          readableDoctorName(item['doctorName'] as String?).toLowerCase();
      final msg = (item['lastMessage'] as String? ?? '').toLowerCase();
      return name.contains(q) || msg.contains(q);
    }).toList();
  }

  String? _patientPhotoUrl() =>
      ApiService.resolveMediaUrlOrNull(widget.patientPhotoPath);

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
    if (mounted) {
      setState(() => _seenConversationMessageAt = updated);
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_seenConversationMessageAtKey, jsonEncode(updated));
    } catch (_) {}
  }

  DateTime? _parseTime(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  String _formatDiscussionDate(String iso) {
    final d = _parseTime(iso)?.toLocal();
    if (d == null) return '';
    final yy = (d.year % 100).toString().padLeft(2, '0');
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/$yy';
  }

  Future<void> _loadConversations() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list =
          await ApiService.getPatientConversations(patientId: widget.patientId);
      list.sort((a, b) {
        final da = _parseTime(a['lastMessageAt']);
        final db = _parseTime(b['lastMessageAt']);
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        return db.compareTo(da);
      });
      if (!mounted) return;
      setState(() {
        _conversations = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  void _openConversation(Map<String, dynamic> item) {
    final conversationId = (item['conversationId'] as String?) ?? '';
    final doctorName = readableDoctorName(item['doctorName'] as String?);
    final doctorPhotoPath = item['doctorPhotoPath']?.toString();
    final doctorId = (item['doctorId'] as String?) ?? '';
    final lastMessageAt = (item['lastMessageAt'] ?? '').toString();
    final unreadCount = (item['unreadCount'] as num?)?.toInt() ?? 0;
    final hasUnreadFromDoctor = (item['hasUnreadFromDoctor'] as bool?) ?? false;
    final seenAt = _seenConversationMessageAt[conversationId];
    final isUnreadUntilOpen = hasUnreadFromDoctor &&
        conversationId.isNotEmpty &&
        lastMessageAt.isNotEmpty &&
        seenAt != lastMessageAt;

    _markConversationAsSeen(
      conversationId: conversationId,
      lastMessageAt: lastMessageAt,
    );
    final seenNow =
        unreadCount > 0 ? unreadCount : (isUnreadUntilOpen ? 1 : 0);
    widget.onConversationOpened?.call(seenNow);
    Navigator.of(context)
        .push(
      MaterialPageRoute<void>(
        builder: (_) => ChatPage(
          patientId: widget.patientId,
          doctorId: doctorId,
          doctorName: doctorName,
          doctorPhotoPath: doctorPhotoPath,
        ),
      ),
    )
        .then((_) => _loadConversations());
  }

  Future<void> _handleBack() async {
    if (widget.asModalSheet) {
      Navigator.of(context).pop();
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lastRoute', 'espace_patient');
    if (!mounted) return;
    final didPop = await Navigator.of(context).maybePop();
    if (didPop || !mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => EspacePatientPage(
          patientId: widget.patientId,
          patientName: widget.patientName,
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, widget.asModalSheet ? 0 : 4, 20, 14),
      child: Container(
        decoration: BoxDecoration(
          color: _searchBg,
          borderRadius: BorderRadius.circular(widget.asModalSheet ? 24 : 14),
          border: Border.all(color: _searchBorder, width: 1),
        ),
        child: TextField(
          controller: _searchController,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: _titleNavy,
                fontSize: 15,
              ),
          decoration: InputDecoration(
            hintText: 'Rechercher...',
            hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: _searchHint,
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                ),
            suffixIcon: const Icon(
              Icons.search_rounded,
              color: _searchHint,
              size: 22,
            ),
            filled: true,
            fillColor: _searchBg,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 14,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSheetHandle() {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 10, bottom: 6),
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: const Color(0xFFD0D5DD),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildSheetHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 16, 4),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              onPressed: _handleBack,
              icon: const Icon(Icons.close_rounded, size: 24),
              color: const Color(0xFF9E9E9E),
              tooltip: 'Fermer',
            ),
          ),
          Text(
            'Discussions',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: _titleNavy,
                  fontSize: 20,
                  letterSpacing: -0.2,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final displayName = readablePatientName(widget.patientName);
    final initials = doctorInitials(displayName);
    final photoUrl = _patientPhotoUrl();

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 12, 0),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              onPressed: _handleBack,
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
              color: _titleNavy,
              tooltip: 'Retour',
            ),
          ),
          Text(
            'Discussions',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: _titleNavy,
                  fontSize: 20,
                  letterSpacing: -0.2,
                ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: CircleAvatar(
              radius: 20,
              backgroundColor: _avatarBg,
              backgroundImage:
                  photoUrl != null ? NetworkImage(photoUrl) : null,
              child: photoUrl == null
                  ? Text(
                      initials,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: _avatarIcon,
                            fontWeight: FontWeight.w800,
                          ),
                    )
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: HeadsAppColors.danger),
          ),
        ),
      );
    }

    final conversations = _filteredConversations;
    if (conversations.isEmpty) {
      return Center(
        child: Text(
          _searchQuery.trim().isEmpty
              ? 'Aucune discussion pour le moment.'
              : 'Aucun résultat pour « ${_searchQuery.trim()} ».',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: _textGrey,
              ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadConversations,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        itemCount: conversations.length,
        separatorBuilder: (_, __) => widget.asModalSheet
            ? Padding(
                padding: const EdgeInsets.only(left: 90),
                child: const Divider(
                  height: 1,
                  thickness: 1,
                  color: _dividerGrey,
                ),
              )
            : const Divider(
                height: 1,
                thickness: 1,
                color: _dividerGrey,
              ),
        itemBuilder: (context, i) =>
            _buildConversationTile(conversations[i]),
      ),
    );
  }

  Widget _buildConversationTile(Map<String, dynamic> item) {
    final conversationId = (item['conversationId'] as String?) ?? '';
    final doctorName = readableDoctorName(item['doctorName'] as String?);
    final doctorPhotoPath = item['doctorPhotoPath']?.toString();
    final rawDoctorStatus = (item['doctorStatus'] as String?)?.trim();
    final doctorStatus = (rawDoctorStatus == null || rawDoctorStatus.isEmpty)
        ? 'available'
        : rawDoctorStatus;
    final lastMessage = item['lastMessage'] as String? ?? '—';
    final lastMessageAt = (item['lastMessageAt'] ?? '').toString();
    final hasUnreadFromDoctor = (item['hasUnreadFromDoctor'] as bool?) ?? false;
    final seenAt = _seenConversationMessageAt[conversationId];
    final isUnreadUntilOpen = hasUnreadFromDoctor &&
        conversationId.isNotEmpty &&
        lastMessageAt.isNotEmpty &&
        seenAt != lastMessageAt;
    final showOnlineDot = _showOnlineDot(doctorStatus);
    final dateLabel = _formatDiscussionDate(lastMessageAt);

    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: () => _openConversation(item),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  doctorAvatarForPatient(
                    name: doctorName,
                    doctorPhotoPath: doctorPhotoPath,
                    radius: 28,
                    backgroundColor: _avatarBg,
                    accentColor: _avatarIcon,
                    fallbackChild: const Icon(
                      Icons.person_rounded,
                      color: _avatarIcon,
                      size: 30,
                    ),
                  ),
                  if (showOnlineDot)
                    Positioned(
                      right: 2,
                      bottom: 2,
                      child: Container(
                        width: 11,
                        height: 11,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _onlineGreen,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            doctorName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(
                                  color: _titleNavy,
                                  fontWeight: isUnreadUntilOpen
                                      ? FontWeight.w800
                                      : FontWeight.w700,
                                  fontSize: 16,
                                  height: 1.2,
                                ),
                          ),
                        ),
                        if (dateLabel.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Text(
                            dateLabel,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: _textGrey,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w400,
                                ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      lastMessage,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: isUnreadUntilOpen
                                ? const Color(0xFF424242)
                                : _textGrey,
                            fontWeight: isUnreadUntilOpen
                                ? FontWeight.w600
                                : FontWeight.w400,
                            fontSize: 13,
                            height: 1.35,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.asModalSheet) ...[
          _buildSheetHandle(),
          _buildSheetHeader(),
        ] else
          _buildHeader(),
        _buildSearchBar(),
        Expanded(child: _buildBody()),
      ],
    );

    if (widget.asModalSheet) {
      return ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: Material(
          color: Colors.white,
          child: content,
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(child: content),
    );
  }
}
