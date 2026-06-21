import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../chat_medecin_page.dart';
import '../headsapp_theme.dart';
import '../services/api_service.dart';
import '../utils/doctor_ui_utils.dart';
import 'doctor_teleconsult_agenda_screen.dart';

const Color _screenBg = Color(0xFFF5F9FC);
const Color _headerBlue = Color(0xFF2459A8);
const Color _ctaBlue = Color(0xFF0066FF);

enum _FormListFilter { all, newOnes }

String _formReviewStatusLabel(String api) {
  switch (api) {
    case 'accepted':
      return 'Accepté';
    case 'rejected':
      return 'Rejeté';
    default:
      return 'En attente de décision';
  }
}

String _formWorkflowLabel(String api) {
  switch (api) {
    case 'scheduled':
      return 'Téléconsultation planifiée';
    case 'replied':
      return 'Répondu';
    default:
      return 'En attente';
  }
}

String _fullFormText(Map<String, dynamic> m) {
  final parts = <String>[];
  void add(String label, dynamic v) {
    final s = v?.toString().trim() ?? '';
    if (s.isNotEmpty) parts.add('$label\n$s');
  }

  add('Motif', m['motif']);
  add('Symptômes', m['symptomes']);
  add('Traitements', m['traitements']);
  add('Allergies', m['allergies']);
  final d = m['dateDerniereConsultation'];
  if (d != null && d.toString().isNotEmpty) {
    final dt = DateTime.tryParse(d.toString());
    if (dt != null) {
      parts.add(
        'Date dernière consultation\n${DateFormat('dd/MM/yyyy').format(dt.toLocal())}',
      );
    }
  }
  return parts.isEmpty ? '—' : parts.join('\n\n');
}

String _formPreviewFromMap(Map<String, dynamic> m) {
  final symptomes = m['symptomes']?.toString().trim() ?? '';
  if (symptomes.isNotEmpty) return doctorFormBodyPreview(symptomes);
  final motif = m['motif']?.toString().trim() ?? '';
  if (motif.isNotEmpty) return doctorFormBodyPreview(motif);
  return doctorFormBodyPreview(_fullFormText(m));
}

String _formStatusBadge(String status, String workflow) {
  if (status == 'pending') return 'NOUVEAU';
  if (status == 'rejected') return 'REJETÉ';
  return 'EN COURS';
}

({Color bg, Color fg}) _formBadgeColors(String badge) {
  switch (badge) {
    case 'NOUVEAU':
      return (
        bg: const Color(0xFFE8F2FF),
        fg: _headerBlue,
      );
    case 'REJETÉ':
      return (
        bg: HeadsAppColors.danger.withValues(alpha: 0.12),
        fg: HeadsAppColors.danger,
      );
    default:
      return (
        bg: const Color(0xFFF2F4F7),
        fg: HeadsAppColors.textSecondary,
      );
  }
}

String _formatFormListTime(DateTime dt) {
  final local = dt.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return DateFormat.Hm('fr_FR').format(local);
  if (diff == 1) return 'Hier';
  if (diff < 7) {
    final label = DateFormat.EEEE('fr_FR').format(local);
    if (label.isEmpty) return label;
    return '${label[0].toUpperCase()}${label.substring(1)}';
  }
  return DateFormat('d MMM', 'fr_FR').format(local);
}

String _formatFormSentLabel(DateTime dt) {
  final local = dt.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  final time = DateFormat.Hm('fr_FR').format(local);
  if (day == today) return 'Envoyé aujourd\'hui à $time';
  if (today.difference(day).inDays == 1) return 'Envoyé hier à $time';
  return 'Envoyé le ${DateFormat('d MMM yyyy', 'fr_FR').format(local)} à $time';
}

String? _symptomDurationLabel(Map<String, dynamic> m) {
  final text = '${m['symptomes'] ?? ''} ${m['motif'] ?? ''}'.toLowerCase();
  final dayMatch = RegExp(
    r'(?:il y a|depuis|apparues? il y a)\s*(\d+)\s*jours?',
  ).firstMatch(text);
  if (dayMatch != null) {
    final n = int.tryParse(dayMatch.group(1)!);
    if (n != null && n > 0) return '$n jour${n > 1 ? 's' : ''}';
  }
  final simpleDays = RegExp(r'(\d+)\s*jours?').firstMatch(text);
  if (simpleDays != null) {
    final n = int.tryParse(simpleDays.group(1)!);
    if (n != null && n > 0) return '$n jour${n > 1 ? 's' : ''}';
  }
  final weeks = RegExp(r'(\d+)\s*semaines?').firstMatch(text);
  if (weeks != null) {
    final n = int.tryParse(weeks.group(1)!);
    if (n != null && n > 0) return '$n semaine${n > 1 ? 's' : ''}';
  }
  return null;
}

String _symptomQuoteText(Map<String, dynamic> m) {
  final symptomes = m['symptomes']?.toString().trim() ?? '';
  if (symptomes.isNotEmpty) return symptomes;
  final motif = m['motif']?.toString().trim() ?? '';
  if (motif.isNotEmpty) return motif;
  return '—';
}

List<String> _antecedentLines(Map<String, dynamic> m) {
  final out = <String>[];
  void addField(String? raw) {
    final s = raw?.trim() ?? '';
    if (s.isEmpty) return;
    for (final line in s.split(RegExp(r'[\n\r•]+'))) {
      final t = line.trim();
      if (t.isNotEmpty) out.add(t);
    }
  }

  addField(m['traitements']?.toString());
  addField(m['allergies']?.toString());
  return out;
}

String? _patientAgeLabel(Map<String, dynamic> m) {
  final raw = m['patientBirthDate'] ?? m['birthDate'];
  if (raw == null) return null;
  final bd = DateTime.tryParse(raw.toString());
  if (bd == null) return null;
  final now = DateTime.now();
  var age = now.year - bd.year;
  if (now.month < bd.month ||
      (now.month == bd.month && now.day < bd.day)) {
    age--;
  }
  if (age < 0 || age > 130) return null;
  return '$age ans';
}

String _formatAttachmentSize(num? bytes) {
  if (bytes == null || bytes <= 0) return '';
  if (bytes < 1024) return '${bytes.round()} o';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String _attachmentKindLabel(String? mimetype, String filename) {
  final mt = (mimetype ?? '').toLowerCase();
  if (mt.startsWith('image/')) return 'IMAGE';
  if (mt.contains('pdf')) return 'PDF';
  final parts = filename.split('.');
  if (parts.length > 1) return parts.last.toUpperCase();
  return 'FICHIER';
}

class _FormHistoryEntry {
  const _FormHistoryEntry({required this.date, required this.title});

  final DateTime date;
  final String title;
}

Color _initialsAvatarColor(String name) {
  const palette = [
    Color(0xFFDCEBFF),
    Color(0xFFFFE8DC),
    Color(0xFFE8E0FF),
    Color(0xFFE0F5EE),
    Color(0xFFFFF0DC),
  ];
  var hash = 0;
  for (final c in name.codeUnits) {
    hash = (hash + c) % palette.length;
  }
  return palette[hash];
}

/// Liste des formulaires de téléconsultation.
class DoctorTeleconsultFormsScreen extends StatefulWidget {
  const DoctorTeleconsultFormsScreen({
    super.key,
    required this.doctorId,
    this.onRefreshHome,
    this.onListConsulted,
  });

  final String doctorId;
  final Future<void> Function()? onRefreshHome;
  final VoidCallback? onListConsulted;

  @override
  State<DoctorTeleconsultFormsScreen> createState() =>
      _DoctorTeleconsultFormsScreenState();
}

class _DoctorTeleconsultFormsScreenState
    extends State<DoctorTeleconsultFormsScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;
  _FormListFilter _filter = _FormListFilter.all;

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<Map<String, dynamic>> get _visibleItems {
    if (_filter == _FormListFilter.newOnes) {
      return _items
          .where((it) => (it['status']?.toString() ?? 'pending') == 'pending')
          .toList();
    }
    return _items;
  }

  Future<void> _openDetail(Map<String, dynamic> it) async {
    final id = it['id']?.toString() ?? '';
    if (id.isEmpty) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => DoctorTeleconsultFormDetailScreen(
          doctorId: widget.doctorId,
          formId: id,
        ),
      ),
    );
    if (changed == true && mounted) {
      await _load();
      await widget.onRefreshHome?.call();
    }
  }

  Future<void> _load() async {
    if (widget.doctorId.isEmpty) {
      setState(() {
        _loading = false;
        _items = [];
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await ApiService.getDoctorTeleconsultForms(widget.doctorId);
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
      });
      if (mounted) widget.onListConsulted?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleItems;
    return Scaffold(
      backgroundColor: _screenBg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _HeadsAppBackHeader(title: 'Formulaire'),
            Divider(
              height: 1,
              thickness: 1,
              color: HeadsAppColors.border.withValues(alpha: 0.8),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: _FormTabBar(
                filter: _filter,
                onChanged: (f) => setState(() => _filter = f),
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                color: HeadsAppColors.brandPrimary,
                onRefresh: () async {
                  await _load();
                  await widget.onRefreshHome?.call();
                },
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: HeadsAppColors.brandPrimary,
                        ),
                      )
                    : _error != null
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.all(24),
                            children: [
                              Text(_error!, textAlign: TextAlign.center),
                            ],
                          )
                        : visible.isEmpty
                            ? ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.all(24),
                                children: const [
                                  SizedBox(height: 48),
                                  Text(
                                    'Aucun formulaire de téléconsultation reçu.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: HeadsAppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              )
                            : ListView.separated(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 16, 16, 24),
                                itemCount: visible.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: 12),
                                itemBuilder: (context, i) {
                                  final it = visible[i];
                                  final name = readablePatientName(
                                    it['patientName']?.toString(),
                                  );
                                  final preview = _formPreviewFromMap(it);
                                  final st =
                                      it['status']?.toString() ?? 'pending';
                                  final wf = it['workflowStatus']?.toString() ??
                                      'pending';
                                  final badge = _formStatusBadge(st, wf);
                                  final badgeColors = _formBadgeColors(badge);
                                  final attRaw = it['attachments'];
                                  final attCount =
                                      attRaw is List ? attRaw.length : 0;
                                  DateTime? dt;
                                  final at = it['createdAt'];
                                  if (at != null) {
                                    dt = DateTime.tryParse(at.toString());
                                  }
                                  return _FormSubmissionCard(
                                    patientName: name,
                                    patientPhotoPath:
                                        it['patientPhotoPath']?.toString(),
                                    timeLabel: dt == null
                                        ? ''
                                        : _formatFormListTime(dt),
                                    preview: preview == '—' ? '' : preview,
                                    attachmentCount: attCount,
                                    statusBadge: badge,
                                    badgeBg: badgeColors.bg,
                                    badgeFg: badgeColors.fg,
                                    onTap: () => _openDetail(it),
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

class _HeadsAppBackHeader extends StatelessWidget {
  const _HeadsAppBackHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            color: _headerBlue,
          ),
          Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: _headerBlue,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _FormTabBar extends StatelessWidget {
  const _FormTabBar({
    required this.filter,
    required this.onChanged,
  });

  final _FormListFilter filter;
  final ValueChanged<_FormListFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFE8ECF0),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: _FormTabChip(
              label: 'Toutes',
              selected: filter == _FormListFilter.all,
              onTap: () => onChanged(_FormListFilter.all),
            ),
          ),
          Expanded(
            child: _FormTabChip(
              label: 'Nouvelles',
              selected: filter == _FormListFilter.newOnes,
              onTap: () => onChanged(_FormListFilter.newOnes),
            ),
          ),
        ],
      ),
    );
  }
}

class _FormTabChip extends StatelessWidget {
  const _FormTabChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: selected
                ? const [
                    BoxShadow(
                      color: Color(0x0A000000),
                      blurRadius: 6,
                      offset: Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: selected ? _headerBlue : HeadsAppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _FormSubmissionCard extends StatelessWidget {
  const _FormSubmissionCard({
    required this.patientName,
    required this.patientPhotoPath,
    required this.timeLabel,
    required this.preview,
    this.attachmentCount = 0,
    required this.statusBadge,
    required this.badgeBg,
    required this.badgeFg,
    required this.onTap,
  });

  final String patientName;
  final String? patientPhotoPath;
  final String timeLabel;
  final String preview;
  final int attachmentCount;
  final String statusBadge;
  final Color badgeBg;
  final Color badgeFg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final photoUrl = ApiService.resolveMediaUrl(patientPhotoPath);
    final initials = doctorInitials(patientName);
    final avatarBg = _initialsAvatarColor(patientName);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      elevation: 0,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0D000000),
                blurRadius: 16,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (photoUrl.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        photoUrl,
                        width: 44,
                        height: 44,
                        fit: BoxFit.cover,
                      ),
                    )
                  else
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: avatarBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        initials,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: _headerBlue.withValues(alpha: 0.85),
                        ),
                      ),
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
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: HeadsAppColors.textPrimary,
                          ),
                        ),
                        if (timeLabel.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                Icons.schedule_rounded,
                                size: 14,
                                color: HeadsAppColors.textSecondary
                                    .withValues(alpha: 0.85),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                timeLabel,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: HeadsAppColors.textSecondary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: badgeBg,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      statusBadge,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                        color: badgeFg,
                      ),
                    ),
                  ),
                ],
              ),
              if (preview.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF2F4F7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    preview,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      color: HeadsAppColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
              if (attachmentCount > 0) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(
                      Icons.attach_file_rounded,
                      size: 16,
                      color: _ctaBlue.withValues(alpha: 0.9),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '$attachmentCount pièce${attachmentCount > 1 ? 's' : ''} jointe${attachmentCount > 1 ? 's' : ''}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _ctaBlue,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class DoctorTeleconsultFormDetailScreen extends StatefulWidget {
  const DoctorTeleconsultFormDetailScreen({
    super.key,
    required this.doctorId,
    required this.formId,
  });

  final String doctorId;
  final String formId;

  @override
  State<DoctorTeleconsultFormDetailScreen> createState() =>
      _DoctorTeleconsultFormDetailScreenState();
}

class _DoctorTeleconsultFormDetailScreenState
    extends State<DoctorTeleconsultFormDetailScreen> {
  Map<String, dynamic>? _data;
  Map<String, dynamic>? _scheduledSlot;
  List<_FormHistoryEntry> _recentHistory = [];
  bool _loading = true;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await ApiService.getTeleconsultFormForDoctor(
        formId: widget.formId,
        doctorId: widget.doctorId,
      );
      if (!mounted) return;
      final scheduled = await _findScheduledSlot(d);
      if (!mounted) return;
      final history = await _loadPatientHistory(d);
      if (!mounted) return;
      setState(() {
        _data = d;
        _scheduledSlot = scheduled;
        _recentHistory = history;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _scheduledSlot = null;
        _loading = false;
      });
    }
  }

  DateTime? _slotLocal(Map<String, dynamic> slot) {
    final iso = slot['dateHeure'] ??
        slot['scheduledAt'] ??
        slot['startAt'] ??
        slot['startAtUtc'];
    if (iso is String && iso.isNotEmpty) {
      return DateTime.tryParse(iso)?.toLocal();
    }
    final date = slot['date']?.toString() ?? '';
    final heure = slot['heure']?.toString() ?? '';
    if (date.isNotEmpty && heure.isNotEmpty) {
      return DateTime.tryParse('${date}T$heure:00')?.toLocal();
    }
    return null;
  }

  String _slotId(Map<String, dynamic> slot) =>
      (slot['id'] ??
              slot['_id'] ??
              slot['rendezvousId'] ??
              slot['rendezVousId'] ??
              '')
          .toString()
          .trim();

  String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _hhmm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  String _fmtLocal(DateTime d) => DateFormat('dd/MM/yyyy à HH:mm').format(d);

  Future<Map<String, dynamic>?> _findScheduledSlot(
    Map<String, dynamic> formData,
  ) async {
    final patientId = formData['patientId']?.toString() ?? '';
    if (patientId.isEmpty) return null;
    try {
      final rows = await ApiService.getDoctorAgendaRendezVous(
        doctorId: widget.doctorId,
      );
      final formId = widget.formId;
      final filtered = rows.where((raw) {
        final e = Map<String, dynamic>.from(raw);
        final statut = (e['statut'] ?? '').toString().toLowerCase();
        if (statut == 'annule') return false;
        if ((e['patientId']?.toString() ?? '') != patientId) return false;
        final fId = e['formulaireId']?.toString() ?? '';
        if (fId.isNotEmpty) return fId == formId;
        return true;
      }).map((e) => Map<String, dynamic>.from(e)).toList();
      if (filtered.isEmpty) return null;
      final withId = filtered.where((e) => _slotId(e).isNotEmpty).toList();
      if (withId.isEmpty) return null;

      // Priorité 1: RDV lié explicitement au formulaire (formulaireId == formId).
      final exact = withId.where(
        (e) => (e['formulaireId']?.toString() ?? '') == formId,
      );
      if (exact.isNotEmpty) {
        final exactList = exact.toList();
        exactList.sort((a, b) {
          final da = _slotLocal(a);
          final db = _slotLocal(b);
          if (da == null && db == null) return 0;
          if (da == null) return 1;
          if (db == null) return -1;
          return da.compareTo(db);
        });
        return exactList.first;
      }

      // Priorité 2: prochain RDV actif du patient (non terminé/annulé) le plus proche.
      final now = DateTime.now();
      final active = withId.where((e) {
        final s = (e['statutEffectif'] ?? e['statut'] ?? '').toString().toLowerCase();
        return s != 'termine' && s != 'annule';
      }).toList();
      final upcoming = active.where((e) {
        final dt = _slotLocal(e);
        return dt != null && !dt.isBefore(now);
      }).toList();
      if (upcoming.isNotEmpty) {
        upcoming.sort((a, b) => _slotLocal(a)!.compareTo(_slotLocal(b)!));
        return upcoming.first;
      }

      // Priorité 3: fallback sur le dernier RDV connu du patient.
      withId.sort((a, b) {
        final da = _slotLocal(a);
        final db = _slotLocal(b);
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        return db.compareTo(da);
      });
      return withId.first;
    } catch (_) {
      return null;
    }
  }

  Future<List<_FormHistoryEntry>> _loadPatientHistory(
    Map<String, dynamic> formData,
  ) async {
    final out = <_FormHistoryEntry>[];
    final patientId = formData['patientId']?.toString() ?? '';

    final dlc = formData['dateDerniereConsultation'];
    if (dlc != null && dlc.toString().isNotEmpty) {
      final dt = DateTime.tryParse(dlc.toString());
      if (dt != null) {
        out.add(
          _FormHistoryEntry(
            date: dt.toLocal(),
            title: 'Consultation déclarée par le patient',
          ),
        );
      }
    }

    if (patientId.isEmpty) {
      out.sort((a, b) => b.date.compareTo(a.date));
      return out.take(4).toList();
    }

    try {
      final rows = await ApiService.getDoctorAgendaRendezVous(
        doctorId: widget.doctorId,
      );
      final now = DateTime.now();
      for (final raw in rows) {
        final e = Map<String, dynamic>.from(raw);
        if ((e['patientId']?.toString() ?? '') != patientId) continue;
        final statut =
            (e['statutEffectif'] ?? e['statut'] ?? '').toString().toLowerCase();
        if (statut == 'annule') continue;
        final dt = _slotLocal(e);
        if (dt == null) continue;
        if (dt.add(const Duration(minutes: 30)).isAfter(now)) continue;
        final type = (e['type'] ?? 'teleconsultation').toString().toLowerCase();
        final label = type.contains('tele')
            ? 'Téléconsultation'
            : 'Consultation';
        out.add(_FormHistoryEntry(date: dt, title: label));
      }
    } catch (_) {}

    out.sort((a, b) => b.date.compareTo(a.date));
    final seen = <String>{};
    final deduped = <_FormHistoryEntry>[];
    for (final entry in out) {
      final key =
          '${entry.date.year}-${entry.date.month}-${entry.date.day}-${entry.title}';
      if (seen.add(key)) deduped.add(entry);
    }
    return deduped.take(4).toList();
  }

  Future<void> _openAttachmentUrl(String rawUrl) async {
    final url = ApiService.resolveMediaUrl(rawUrl);
    if (url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _decideForm(bool accept) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ApiService.decideTeleconsultForm(
        formId: widget.formId,
        doctorId: widget.doctorId,
        accept: accept,
      );
      if (!mounted) return;
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              accept
                  ? 'Formulaire accepté.'
                  : 'Formulaire rejeté. Le patient est informé.',
            ),
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
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scheduleTeleconsult() async {
    if (_busy || _data == null) return;
    final patientId = _data!['patientId']?.toString() ?? '';
    if (patientId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Patient introuvable pour ce dossier.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    final patientName = readablePatientName(_data!['patientName']?.toString());
    final photo = _data!['patientPhotoPath']?.toString();

    if (!mounted) return;
    await DoctorTeleconsultAgendaScreen.showAsDialog(
      context,
      doctorId: widget.doctorId,
      patientId: patientId,
      patientName: patientName,
      patientPhotoPath: photo,
      formulaireId: widget.formId,
    );
    if (mounted) await _load();
  }

  Future<Set<String>> _occupiedHoursForDate(
    DateTime day, {
    String? excludeRdvId,
  }) async {
    final out = <String>{};
    try {
      final data = await ApiService.getRendezVousForDate(
        medecinId: widget.doctorId,
        dateYYYYMMDD: _ymd(day),
      );
      final raw = data['rendezvous'];
      if (raw is List) {
        for (final e in raw) {
          if (e is! Map) continue;
          final row = Map<String, dynamic>.from(e);
          final id = (row['id'] ?? row['_id'] ?? '').toString().trim();
          if (excludeRdvId != null && id == excludeRdvId) continue;
          final h = row['heure']?.toString().trim() ?? '';
          if (h.isNotEmpty) out.add(h);
        }
      }
    } catch (_) {}
    return out;
  }

  Future<void> _editScheduledSlot() async {
    final slot = _scheduledSlot;
    if (slot == null || _busy) return;
    final rdvId = _slotId(slot);
    final current = _slotLocal(slot);
    if (rdvId.isEmpty || current == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rendez-vous introuvable.')),
      );
      return;
    }

    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: current.isBefore(now) ? now : current,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 2, 12, 31),
      helpText: 'Nouvelle date du rendez-vous',
    );
    if (pickedDate == null || !mounted) return;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current.hour, minute: current.minute),
      confirmText: 'Enregistrer',
    );
    if (pickedTime == null || !mounted) return;

    final local = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );
    if (!local.isAfter(DateTime.now().subtract(const Duration(minutes: 1)))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choisissez un horaire dans le futur.')),
      );
      return;
    }

    final date = _ymd(local);
    final heure = _hhmm(local);
    final occupied = await _occupiedHoursForDate(local, excludeRdvId: rdvId);
    if (!mounted) return;
    if (occupied.contains(heure)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Le créneau $date à $heure est déjà pris.')),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      await ApiService.putRendezVous(
        rendezvousId: rdvId,
        medecinId: widget.doctorId,
        dateYYYYMMDD: date,
        heureHHmm: heure,
        startAtIsoUtc: local.toUtc().toIso8601String(),
      );
      if (!mounted) return;
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Rendez-vous modifié: $date à $heure')),
        );
      }
    } on RendezVousConflictException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Créneau déjà pris: ${e.date ?? date} à ${e.heure ?? heure}.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteScheduledSlot() async {
    final slot = _scheduledSlot;
    if (slot == null || _busy) return;
    final rdvId = _slotId(slot);
    if (rdvId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rendez-vous introuvable.')),
      );
      return;
    }
    final motifCtrl = TextEditingController();
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Supprimer ce rendez-vous ?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_slotLocal(slot) != null)
                Text('Téléconsultation du ${_fmtLocal(_slotLocal(slot)!)}'),
              const SizedBox(height: 12),
              TextField(
                controller: motifCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Motif (optionnel)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Supprimer'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      setState(() => _busy = true);
      await ApiService.deleteRendezVous(
        rendezvousId: rdvId,
        medecinId: widget.doctorId,
        motif: motifCtrl.text.trim(),
      );
      if (!mounted) return;
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rendez-vous supprimé')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      motifCtrl.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _replyByMessage() async {
    if (_busy || _data == null) return;
    final patientId = _data!['patientId']?.toString() ?? '';
    final name = _data!['patientName']?.toString() ?? 'Patient';
    if (patientId.isEmpty) return;

    setState(() => _busy = true);
    try {
      await ApiService.patchTeleconsultFormWorkflow(
        formId: widget.formId,
        doctorId: widget.doctorId,
        status: 'replied',
      );
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      final convId = _data!['conversationId']?.toString() ?? '';
      if (convId.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Conversation introuvable après enregistrement. Réessayez.',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => ChatMedecinPage(
            conversationId: convId,
            patientId: patientId,
            patientName: name,
            doctorId: widget.doctorId,
            patientPhotoPath:
                _data!['patientPhotoPath']?.toString(),
          ),
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Vous pouvez répondre au patient dans le chat.',
            ),
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
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _buildDetailBottomActions({
    required bool needsDecision,
    required bool canWorkflow,
    required String review,
  }) {
    if (needsDecision) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: _ctaBlue,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: _busy ? null : () => _decideForm(true),
                icon: const Icon(Icons.check_rounded),
                label: const Text(
                  'Accepter le dossier',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 52,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  backgroundColor: const Color(0xFFF2F4F7),
                  foregroundColor: HeadsAppColors.textPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: _busy ? null : () => _decideForm(false),
                icon: const Icon(Icons.close_rounded),
                label: const Text(
                  'Rejeter',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ),
            ),
          ],
        ),
      );
    }
    if (canWorkflow) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1F4E5F),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: _busy ? null : _scheduleTeleconsult,
                icon: const Icon(Icons.videocam_rounded),
                label: const Text(
                  'Démarrer une téléconsultation',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ),
            ),
            const SizedBox(height: 10),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0066FF), Color(0xFF0052CC)],
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: SizedBox(
                height: 52,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    foregroundColor: Colors.white,
                    shadowColor: Colors.transparent,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: _busy ? null : _replyByMessage,
                  icon: const Icon(Icons.chat_bubble_outline_rounded),
                  label: const Text(
                    'Répondre par message',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    if (review == 'rejected') {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: HeadsAppColors.danger.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Text(
            'Ce dossier a été rejeté. Aucune autre action sur ce formulaire.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: HeadsAppColors.danger,
            ),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final review = _data?['status']?.toString() ?? 'pending';
    final wf = _data?['workflowStatus']?.toString() ?? 'pending';
    final slot = _scheduledSlot;
    final slotDt = slot == null ? null : _slotLocal(slot);
    final slotStatus = (slot?['statutEffectif'] ?? slot?['statut'] ?? '')
        .toString()
        .toLowerCase();
    final canManageScheduled =
        slot != null && slotStatus != 'annule' && slotStatus != 'termine';
    final needsDecision = review == 'pending';
    final canWorkflow = review == 'accepted' && wf == 'pending';
    final attachments = _data?['attachments'];
    final attList = attachments is List ? attachments : const [];
    final data = _data;

    return Scaffold(
      backgroundColor: _screenBg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context, true),
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                    color: _headerBlue,
                  ),
                  const Expanded(
                    child: Text(
                      'Détails de la formulaire',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: _headerBlue,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Divider(
              height: 1,
              thickness: 1,
              color: HeadsAppColors.border.withValues(alpha: 0.8),
            ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: HeadsAppColors.brandPrimary,
                      ),
                    )
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              _error!,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : data == null
                          ? const SizedBox.shrink()
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  child: SingleChildScrollView(
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      16,
                                      16,
                                      8,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        _FormDetailMainCard(
                                          patientName: readablePatientName(
                                            data['patientName']?.toString(),
                                          ),
                                          patientPhotoPath:
                                              data['patientPhotoPath']
                                                  ?.toString(),
                                          ageLabel: _patientAgeLabel(data),
                                          sentLabel: data['createdAt'] == null
                                              ? null
                                              : _formatFormSentLabel(
                                                  DateTime.parse(
                                                    data['createdAt']
                                                        .toString(),
                                                  ),
                                                ),
                                          symptomText: _symptomQuoteText(data),
                                          durationLabel:
                                              _symptomDurationLabel(data),
                                          antecedents: _antecedentLines(data),
                                        ),
                                        if (attList.isNotEmpty) ...[
                                          const SizedBox(height: 20),
                                          Text(
                                            'DOCUMENTS JOINTS (${attList.length})',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: 0.6,
                                              color: HeadsAppColors
                                                  .textSecondary
                                                  .withValues(alpha: 0.9),
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                          ...attList.map<Widget>((raw) {
                                            final m = Map<String, dynamic>.from(
                                              raw as Map,
                                            );
                                            final name =
                                                m['filename']?.toString() ??
                                                    'Fichier';
                                            final path =
                                                m['path']?.toString() ?? '';
                                            final mimetype =
                                                m['mimetype']?.toString();
                                            final size = m['size'];
                                            return Padding(
                                              padding: const EdgeInsets.only(
                                                bottom: 10,
                                              ),
                                              child: _FormDetailDocumentCard(
                                                filename: name,
                                                kindLabel: _attachmentKindLabel(
                                                  mimetype,
                                                  name,
                                                ),
                                                sizeLabel: _formatAttachmentSize(
                                                  size is num ? size : null,
                                                ),
                                                isImage: (mimetype ?? '')
                                                    .toLowerCase()
                                                    .startsWith('image/'),
                                                imagePath: path,
                                                onTap: path.isEmpty
                                                    ? null
                                                    : () =>
                                                        _openAttachmentUrl(
                                                          path,
                                                        ),
                                              ),
                                            );
                                          }),
                                        ],
                                        if (_recentHistory.isNotEmpty) ...[
                                          const SizedBox(height: 10),
                                          _FormDetailHistoryCard(
                                            entries: _recentHistory,
                                          ),
                                        ],
                                        if (wf == 'scheduled') ...[
                                          const SizedBox(height: 16),
                                          _DetailSurfaceCard(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                const Text(
                                                  'Rendez-vous planifié',
                                                  style: TextStyle(
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w800,
                                                    color: _headerBlue,
                                                  ),
                                                ),
                                                const SizedBox(height: 8),
                                                if (slotDt != null)
                                                  Text(
                                                    'Date/heure : ${_fmtLocal(slotDt)}',
                                                    style: const TextStyle(
                                                      fontSize: 14,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                  )
                                                else
                                                  const Text(
                                                    'Rendez-vous existant mais date indisponible.',
                                                    style: TextStyle(
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                if (slot == null) ...[
                                                  const SizedBox(height: 8),
                                                  const Text(
                                                    'Impossible de retrouver le rendez-vous dans l’agenda.',
                                                    style: TextStyle(
                                                      fontSize: 13,
                                                    ),
                                                  ),
                                                ],
                                                if (slot != null) ...[
                                                  const SizedBox(height: 12),
                                                  Row(
                                                    children: [
                                                      Expanded(
                                                        child: OutlinedButton.icon(
                                                          onPressed: (_busy ||
                                                                  !canManageScheduled)
                                                              ? null
                                                              : _editScheduledSlot,
                                                          icon: const Icon(
                                                            Icons.edit_rounded,
                                                          ),
                                                          label: const Text(
                                                            'Modifier',
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 10),
                                                      Expanded(
                                                        child: FilledButton.icon(
                                                          style: FilledButton
                                                              .styleFrom(
                                                            backgroundColor:
                                                                HeadsAppColors
                                                                    .danger,
                                                            foregroundColor:
                                                                Colors.white,
                                                          ),
                                                          onPressed: (_busy ||
                                                                  !canManageScheduled)
                                                              ? null
                                                              : _deleteScheduledSlot,
                                                          icon: const Icon(
                                                            Icons
                                                                .delete_outline_rounded,
                                                          ),
                                                          label: const Text(
                                                            'Supprimer',
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                        ] else if (!needsDecision &&
                                            !canWorkflow &&
                                            review != 'rejected') ...[
                                          const SizedBox(height: 16),
                                          _DetailSurfaceCard(
                                            child: Text(
                                              'Suivi final : ${_formWorkflowLabel(wf)}',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 15,
                                                color: wf == 'scheduled'
                                                    ? _headerBlue
                                                    : HeadsAppColors.success,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                                _buildDetailBottomActions(
                                  needsDecision: needsDecision,
                                  canWorkflow: canWorkflow,
                                  review: review,
                                ),
                              ],
                            ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FormDetailMainCard extends StatelessWidget {
  const _FormDetailMainCard({
    required this.patientName,
    required this.patientPhotoPath,
    required this.ageLabel,
    required this.sentLabel,
    required this.symptomText,
    required this.durationLabel,
    required this.antecedents,
  });

  final String patientName;
  final String? patientPhotoPath;
  final String? ageLabel;
  final String? sentLabel;
  final String symptomText;
  final String? durationLabel;
  final List<String> antecedents;

  @override
  Widget build(BuildContext context) {
    final photoUrl = ApiService.resolveMediaUrl(patientPhotoPath);
    final initials = doctorInitials(patientName);
    final avatarBg = _initialsAvatarColor(patientName);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 18,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (photoUrl.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.network(
                    photoUrl,
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                  ),
                )
              else
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: avatarBg,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    initials,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: _headerBlue.withValues(alpha: 0.85),
                    ),
                  ),
                ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      patientName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: HeadsAppColors.textPrimary,
                      ),
                    ),
                    if (ageLabel != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        ageLabel!,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: HeadsAppColors.textPrimary,
                        ),
                      ),
                    ],
                    if (sentLabel != null) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            Icons.schedule_rounded,
                            size: 14,
                            color: HeadsAppColors.textSecondary
                                .withValues(alpha: 0.85),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              sentLabel!,
                              style: const TextStyle(
                                fontSize: 12,
                                color: HeadsAppColors.textSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          const _FormDetailSectionTitle(
            label: 'DESCRIPTION DES SYMPTÔMES',
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF2F4F7),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '"$symptomText"',
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.45,
                    fontStyle: FontStyle.italic,
                    color: HeadsAppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (durationLabel != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _FormDetailInfoChip(
                        label: 'Durée',
                        value: durationLabel!,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (antecedents.isNotEmpty) ...[
            const SizedBox(height: 22),
            const _FormDetailSectionTitle(
              label: 'ANTÉCÉDENTS MÉDICAUX',
            ),
            const SizedBox(height: 10),
            ...antecedents.map(
              (line) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: _ctaBlue.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        size: 14,
                        color: _ctaBlue,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        line,
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.35,
                          color: HeadsAppColors.textPrimary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FormDetailSectionTitle extends StatelessWidget {
  const _FormDetailSectionTitle({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.6,
        color: _headerBlue,
      ),
    );
  }
}

class _FormDetailInfoChip extends StatelessWidget {
  const _FormDetailInfoChip({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(
            fontSize: 12,
            color: HeadsAppColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
          children: [
            TextSpan(text: '$label: '),
            TextSpan(
              text: value,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: _ctaBlue,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FormDetailDocumentCard extends StatelessWidget {
  const _FormDetailDocumentCard({
    required this.filename,
    required this.kindLabel,
    required this.sizeLabel,
    required this.isImage,
    this.imagePath,
    required this.onTap,
  });

  final String filename;
  final String kindLabel;
  final String sizeLabel;
  final bool isImage;
  final String? imagePath;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final subtitle = sizeLabel.isEmpty ? kindLabel : '$kindLabel • $sizeLabel';
    final imageUrl = (isImage && (imagePath ?? '').trim().isNotEmpty)
        ? ApiService.resolveMediaUrl(imagePath!.trim())
        : '';
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0A000000),
                blurRadius: 12,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              if (imageUrl.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    imageUrl,
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 56,
                      height: 56,
                      color: const Color(0xFFF2F4F7),
                      child: const Icon(
                        Icons.broken_image_outlined,
                        color: _ctaBlue,
                      ),
                    ),
                  ),
                )
              else
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF2F4F7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isImage
                        ? Icons.image_outlined
                        : Icons.description_outlined,
                    color: _ctaBlue,
                  ),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      filename,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: HeadsAppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                        color: HeadsAppColors.textSecondary,
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
}

class _FormDetailHistoryCard extends StatelessWidget {
  const _FormDetailHistoryCard({required this.entries});

  final List<_FormHistoryEntry> entries;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F4F7),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Historique récent',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: HeadsAppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 14),
          ...List.generate(entries.length, (i) {
            final entry = entries[i];
            final isFirst = i == 0;
            final dateLabel = DateFormat('d MMM yyyy', 'fr_FR').format(
              entry.date.toLocal(),
            );
            return Padding(
              padding: EdgeInsets.only(bottom: i == entries.length - 1 ? 0 : 14),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Column(
                      children: [
                        Container(
                          width: 3,
                          height: 18,
                          decoration: BoxDecoration(
                            color: isFirst
                                ? _ctaBlue
                                : const Color(0xFFD0D5DD),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        if (i != entries.length - 1)
                          Expanded(
                            child: Container(
                              width: 3,
                              color: const Color(0xFFD0D5DD),
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
                            dateLabel,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: isFirst
                                  ? HeadsAppColors.textPrimary
                                  : HeadsAppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            entry.title,
                            style: const TextStyle(
                              fontSize: 13,
                              color: HeadsAppColors.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _DetailSurfaceCard extends StatelessWidget {
  const _DetailSurfaceCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}
