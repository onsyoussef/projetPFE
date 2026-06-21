import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import 'chat_medecin_page.dart';
import 'headsapp_theme.dart';
import 'services/api_service.dart';
import 'utils/doctor_ui_utils.dart';
import 'widgets/headsapp_logo_text.dart';

class AgendaPage extends StatefulWidget {
  const AgendaPage({
    super.key,
    required this.doctorId,
    this.embeddedInShell = false,
  });

  final String doctorId;
  final bool embeddedInShell;

  @override
  State<AgendaPage> createState() => _AgendaPageState();
}

class _AgendaPageState extends State<AgendaPage> {
  static const Color _brandBlue = Color(0xFF2459A8);
  static const Color _background = Color(0xFFF5F9FC);
  static const Color _textPrimary = HeadsAppColors.textPrimary;
  static const Color _textSecondary = HeadsAppColors.textSecondary;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
  );
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('fr_FR', null);
    _load();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _load(silent: true),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final rows = await ApiService.getDoctorAgendaRendezVous(
        doctorId: widget.doctorId,
      );
      if (!mounted) return;
      setState(() {
        _items = rows
            .where((e) => (e['statut'] as String? ?? '') != 'annule')
            .map(
              (e) => <String, dynamic>{
                ...e,
                'agendaSource': 'tele',
              },
            )
            .toList();
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

  DateTime? _slotLocal(Map<String, dynamic> slot) {
    final iso = slot['dateHeure'] ?? slot['scheduledAt'];
    if (iso is! String || iso.isEmpty) return null;
    final dt = DateTime.tryParse(iso);
    return dt?.toLocal();
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _pad2(int v) => v.toString().padLeft(2, '0');

  String _fmtDate(DateTime d) => '${_pad2(d.day)}/${_pad2(d.month)}/${d.year}';
  String _fmtTime(DateTime d) => '${_pad2(d.hour)}:${_pad2(d.minute)}';
  String _ymd(DateTime d) => '${d.year}-${_pad2(d.month)}-${_pad2(d.day)}';

  List<Map<String, dynamic>> _eventsForDay(DateTime day) {
    return _items.where((s) {
      final local = _slotLocal(s);
      return local != null && _sameDay(local, day);
    }).toList();
  }

  bool _canJoin(DateTime start, int durationMin) {
    final now = DateTime.now();
    final end = start.add(Duration(minutes: durationMin));
    final open = start.subtract(const Duration(minutes: 15));
    return !now.isBefore(open) && now.isBefore(end);
  }

  String _slotId(Map<String, dynamic> slot) =>
      (slot['id'] ?? slot['_id'] ?? '').toString().trim();

  String _slotStatut(Map<String, dynamic> slot) =>
      (slot['statutEffectif'] ?? slot['statut'] ?? '').toString().trim();

  String _slotFormId(Map<String, dynamic> slot) =>
      (slot['formulaireId'] ?? slot['formId'] ?? '').toString().trim();

  bool _canManageSlot(Map<String, dynamic> slot) {
    final statut = _slotStatut(slot).toLowerCase();
    return statut != 'termine' && statut != 'annule';
  }

  Future<Set<String>> _occupiedHoursForDay(
    DateTime day, {
    String? excludeRdvId,
  }) async {
    try {
      final data = await ApiService.getRendezVousForDate(
        medecinId: widget.doctorId,
        dateYYYYMMDD: _ymd(day),
      );
      final raw = data['rendezvous'];
      final out = <String>{};
      if (raw is List) {
        for (final e in raw) {
          if (e is! Map) continue;
          final row = Map<String, dynamic>.from(e);
          final id = (row['id'] ?? row['_id'] ?? '').toString().trim();
          if (excludeRdvId != null && id == excludeRdvId) continue;
          final heure = row['heure']?.toString().trim() ?? '';
          if (heure.isNotEmpty) out.add(heure);
        }
      }
      return out;
    } catch (_) {
      return _eventsForDay(day)
          .where((slot) => _slotId(slot) != excludeRdvId)
          .map((slot) => _fmtTime(_slotLocal(slot) ?? day))
          .toSet();
    }
  }

  Future<void> _editSlot(Map<String, dynamic> slot) async {
    final rdvId = _slotId(slot);
    final current = _slotLocal(slot);
    if (rdvId.isEmpty || current == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rendez-vous invalide.')),
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
    final heure = _fmtTime(local);
    final occupied = await _occupiedHoursForDay(local, excludeRdvId: rdvId);
    if (!mounted) return;
    if (occupied.contains(heure)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Le créneau $date à $heure est déjà pris.')),
      );
      return;
    }

    try {
      await ApiService.putRendezVous(
        rendezvousId: rdvId,
        medecinId: widget.doctorId,
        dateYYYYMMDD: date,
        heureHHmm: heure,
        startAtIsoUtc: local.toUtc().toIso8601String(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Rendez-vous modifié: $date à $heure')),
      );
      await _load(silent: true);
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
    }
  }

  Future<void> _deleteSlot(Map<String, dynamic> slot) async {
    final rdvId = _slotId(slot);
    if (rdvId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rendez-vous invalide.')),
      );
      return;
    }
    final motifCtrl = TextEditingController();
    try {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Supprimer ce rendez-vous ?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${(slot['patientNom'] ?? slot['patientName'] ?? 'Patient').toString()} — '
                '${_fmtDate(_slotLocal(slot) ?? _selectedDay)} à ${_fmtTime(_slotLocal(slot) ?? _selectedDay)}',
              ),
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
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Supprimer'),
            ),
          ],
        ),
      );
      if (go != true || !mounted) return;
      await ApiService.deleteRendezVous(
        rendezvousId: rdvId,
        medecinId: widget.doctorId,
        motif: motifCtrl.text.trim(),
      );
      final formId = _slotFormId(slot);
      if (formId.isNotEmpty) {
        await ApiService.patchTeleconsultFormWorkflow(
          formId: formId,
          doctorId: widget.doctorId,
          status: 'pending',
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rendez-vous supprimé')),
      );
      await _load(silent: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      motifCtrl.dispose();
    }
  }

  Future<void> _joinTeleconsult(Map<String, dynamic> it) async {
    final conversationId = (it['conversationId'] as String? ?? '').trim();
    if (conversationId.isEmpty) return;
    var patientId = (it['patientId'] as String? ?? '').trim();
    if (patientId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Identifiant patient manquant. Mettez le backend à jour ou rouvrez l’agenda.',
          ),
        ),
      );
      return;
    }
    final patientName =
        (it['patientNom'] ?? it['patientName'] ?? 'Patient').toString().trim();
    final patientPhotoPath = it['patientPhotoPath']?.toString();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatMedecinPage(
          conversationId: conversationId,
          patientId: patientId,
          patientName: patientName.isEmpty ? 'Patient' : patientName,
          doctorId: widget.doctorId,
          patientPhotoPath: patientPhotoPath,
          autoStartAudioCall: true,
        ),
      ),
    );
  }

  List<Map<String, dynamic>> get _itemsSelectedDay {
    final items = _eventsForDay(_selectedDay);
    items.sort((a, b) {
      final da = _slotLocal(a);
      final db = _slotLocal(b);
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return da.compareTo(db);
    });
    return items;
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 16, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            color: _textPrimary,
            style: IconButton.styleFrom(
              backgroundColor: Colors.white,
              side: const BorderSide(color: HeadsAppColors.border),
            ),
          ),
          Expanded(
            child: HeadsAppLogoText(
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  String _formatDayHeader(DateTime d) {
    final raw = DateFormat('EEEE d MMMM', 'fr_FR').format(d);
    if (raw.isEmpty) return raw;
    return '${raw[0].toUpperCase()}${raw.substring(1)}';
  }

  Widget _buildCalendarCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: HeadsAppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: TableCalendar<Map<String, dynamic>>(
        locale: 'fr_FR',
        startingDayOfWeek: StartingDayOfWeek.monday,
        firstDay: DateTime.now().subtract(const Duration(days: 365)),
        lastDay: DateTime.now().add(const Duration(days: 365 * 2)),
        focusedDay: _focusedDay,
        selectedDayPredicate: (day) => _sameDay(day, _selectedDay),
        eventLoader: _eventsForDay,
        calendarFormat: CalendarFormat.month,
        availableCalendarFormats: const {CalendarFormat.month: 'Mois'},
        headerStyle: HeaderStyle(
          formatButtonVisible: false,
          titleCentered: true,
          leftChevronIcon: const Icon(
            Icons.chevron_left_rounded,
            color: _brandBlue,
            size: 26,
          ),
          rightChevronIcon: const Icon(
            Icons.chevron_right_rounded,
            color: _brandBlue,
            size: 26,
          ),
          titleTextStyle: const TextStyle(
            color: _textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
          headerPadding: const EdgeInsets.symmetric(vertical: 8),
        ),
        daysOfWeekStyle: DaysOfWeekStyle(
          weekdayStyle: TextStyle(
            fontSize: 12,
            color: _textSecondary.withValues(alpha: 0.85),
            fontWeight: FontWeight.w500,
          ),
          weekendStyle: TextStyle(
            fontSize: 12,
            color: _textSecondary.withValues(alpha: 0.85),
            fontWeight: FontWeight.w500,
          ),
        ),
        onDaySelected: (selectedDay, focusedDay) {
          setState(() {
            _selectedDay = DateTime(
              selectedDay.year,
              selectedDay.month,
              selectedDay.day,
            );
            _focusedDay = focusedDay;
          });
        },
        onPageChanged: (focusedDay) {
          setState(() => _focusedDay = focusedDay);
        },
        calendarStyle: CalendarStyle(
          outsideDaysVisible: true,
          cellMargin: const EdgeInsets.all(6),
          defaultTextStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            color: _textPrimary,
            fontSize: 14,
          ),
          weekendTextStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            color: _textPrimary,
            fontSize: 14,
          ),
          outsideTextStyle: TextStyle(
            fontWeight: FontWeight.w500,
            color: _textSecondary.withValues(alpha: 0.35),
            fontSize: 14,
          ),
          todayTextStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            color: _textPrimary,
            fontSize: 14,
          ),
          todayDecoration: BoxDecoration(
            color: _brandBlue.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          selectedDecoration: BoxDecoration(
            color: _brandBlue,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: _brandBlue.withValues(alpha: 0.35),
                blurRadius: 12,
                spreadRadius: 1,
              ),
            ],
          ),
          selectedTextStyle: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
          markerSize: 5,
          markerMargin: const EdgeInsets.only(top: 4),
          markersMaxCount: 1,
          markerDecoration: const BoxDecoration(
            color: HeadsAppColors.brandAccent,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }

  Widget _buildDaySectionHeader(int count) {
    return Row(
      children: [
        Expanded(
          child: Text(
            _formatDayHeader(_selectedDay),
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: _textPrimary,
            ),
          ),
        ),
        Text(
          '$count rendez-vous',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: _brandBlue,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyDayCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: HeadsAppColors.border),
      ),
      child: const Text(
        'Aucun rendez-vous pour ce jour.',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 14,
          color: _textSecondary,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildAppointmentCard(Map<String, dynamic> it) {
    final dt = _slotLocal(it);
    final dur = (it['duree'] as num?)?.toInt() ?? 30;
    final canJoin = dt != null && _canJoin(dt, dur);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: HeadsAppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            dt == null ? '--:--' : _fmtTime(dt),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: _brandBlue,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              patientAvatarForDoctor(
                name: (it['patientNom'] ?? it['patientName'])?.toString() ??
                    'Patient',
                patientPhotoPath: it['patientPhotoPath']?.toString(),
                radius: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  (it['patientNom'] ?? it['patientName'])?.toString() ??
                      'Patient',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: _textPrimary,
                  ),
                ),
              ),
              if (it['agendaSource'] == 'tele')
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: HeadsAppColors.brandHighlight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Téléconsultation',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _brandBlue,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            it['motif']?.toString().trim().isNotEmpty == true
                ? it['motif'].toString()
                : 'Téléconsultation',
            style: const TextStyle(
              fontSize: 12,
              color: _textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Modifier',
                  onPressed:
                      _canManageSlot(it) ? () => _editSlot(it) : null,
                  icon: const Icon(Icons.edit_rounded, color: _brandBlue),
                ),
                IconButton(
                  tooltip: 'Supprimer',
                  color: HeadsAppColors.danger,
                  onPressed:
                      _canManageSlot(it) ? () => _deleteSlot(it) : null,
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
                const SizedBox(width: 4),
                FilledButton.icon(
                  onPressed: canJoin ? () => _joinTeleconsult(it) : null,
                  icon: const Icon(Icons.videocam_rounded, size: 18),
                  label: const Text('Rejoindre'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _brandBlue,
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dayCount = _itemsSelectedDay.length;

    Widget bodyContent;
    if (_loading) {
      bodyContent = const Center(child: CircularProgressIndicator(color: _brandBlue));
    } else if (_error != null) {
      bodyContent = Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _load,
                child: const Text('Réessayer'),
              ),
            ],
          ),
        ),
      );
    } else {
      bodyContent = RefreshIndicator(
        onRefresh: _load,
        color: _brandBlue,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            _buildCalendarCard(),
            const SizedBox(height: 20),
            _buildDaySectionHeader(dayCount),
            const SizedBox(height: 12),
            if (dayCount == 0)
              _buildEmptyDayCard()
            else
              ..._itemsSelectedDay.map(_buildAppointmentCard),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            Expanded(child: bodyContent),
          ],
        ),
      ),
    );
  }
}
