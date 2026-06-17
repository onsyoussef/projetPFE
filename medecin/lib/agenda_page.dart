import 'dart:async';

import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

import 'chat_medecin_page.dart';
import 'headsapp_theme.dart';
import 'services/api_service.dart';
import 'utils/doctor_ui_utils.dart';

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
  static const Color _primary = HeadsAppColors.brandPrimary;
  static const Color _bg = HeadsAppColors.surfaceAlt;

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

  @override
  Widget build(BuildContext context) {
    final todayCount = _eventsForDay(DateTime.now()).length;

    return Scaffold(
      backgroundColor: _bg,
      appBar: widget.embeddedInShell
          ? null
          : AppBar(
              elevation: 0,
              scrolledUnderElevation: 0,
              centerTitle: true,
              title: Text(
                'Agenda · $todayCount rendez-vous aujourd\'hui',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
              ),
            ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? ListView(
                children: const [
                  SizedBox(height: 240),
                  Center(child: CircularProgressIndicator()),
                ],
              )
            : _error != null
                ? ListView(
                    children: [
                      const SizedBox(height: 120),
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Text(_error!, textAlign: TextAlign.center),
                        ),
                      ),
                    ],
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
                    children: [
                      if (widget.embeddedInShell) ...[
                        Text(
                          'Agenda · $todayCount rendez-vous aujourd\'hui',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: _primary,
                              ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      Container(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              _primary.withValues(alpha: 0.22),
                              const Color(0xFF87CEEB).withValues(alpha: 0.18),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _primary.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.92),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.calendar_month_rounded,
                                color: _primary,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Rendez-vous enregistrés (téléconsultation)',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color: const Color(0xFF2C3E50),
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x1A000000),
                              blurRadius: 8,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: TableCalendar<Map<String, dynamic>>(
                          firstDay: DateTime.now().subtract(
                            const Duration(days: 365),
                          ),
                          lastDay: DateTime.now().add(
                            const Duration(days: 365 * 2),
                          ),
                          focusedDay: _focusedDay,
                          selectedDayPredicate: (day) =>
                              _sameDay(day, _selectedDay),
                          eventLoader: _eventsForDay,
                          calendarFormat: CalendarFormat.month,
                          availableCalendarFormats: const {
                            CalendarFormat.month: 'Mois',
                          },
                          headerStyle: const HeaderStyle(
                            formatButtonVisible: false,
                            titleCentered: true,
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
                            _focusedDay = focusedDay;
                          },
                          calendarStyle: CalendarStyle(
                            markerDecoration: const BoxDecoration(
                              color: Color(0xFFE1395F),
                              shape: BoxShape.circle,
                            ),
                            todayDecoration: BoxDecoration(
                              color: _primary.withValues(alpha: 0.25),
                              shape: BoxShape.circle,
                            ),
                            selectedDecoration: const BoxDecoration(
                              color: _primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Rendez-vous du ${_fmtDate(_selectedDay)}',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 10),
                      if (_itemsSelectedDay.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: HeadsAppColors.surface,
                            borderRadius: BorderRadius.circular(HeadsAppMetrics.compactRadius),
                            border: Border.all(color: HeadsAppColors.border),
                          ),
                          child: const Text(
                            'Aucun rendez-vous pour ce jour.',
                            textAlign: TextAlign.center,
                          ),
                        )
                      else
                        ..._itemsSelectedDay.map((it) {
                          final dt = _slotLocal(it);
                          final dur = (it['duree'] as num?)?.toInt() ?? 30;
                          final canJoin = dt != null && _canJoin(dt, dur);
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: HeadsAppColors.surface,
                              borderRadius: BorderRadius.circular(HeadsAppMetrics.compactRadius),
                              border: Border.all(color: HeadsAppColors.border),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x1A000000),
                                  blurRadius: 8,
                                  offset: Offset(0, 2),
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
                                    color: _primary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    patientAvatarForDoctor(
                                      name: (it['patientNom'] ??
                                              it['patientName'])
                                          ?.toString() ??
                                          'Patient',
                                      patientPhotoPath: it['patientPhotoPath']
                                          ?.toString(),
                                      radius: 20,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        (it['patientNom'] ?? it['patientName'])
                                                ?.toString() ??
                                            'Patient',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
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
                                          color: const Color(0xFF4FA8D5)
                                              .withValues(alpha: 0.15),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: const Text(
                                          'Téléconsultation',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF4FA8D5),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  it['motif']?.toString().trim().isNotEmpty ==
                                          true
                                      ? it['motif'].toString()
                                      : 'Téléconsultation',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: 'Modifier',
                                        onPressed: _canManageSlot(it)
                                            ? () => _editSlot(it)
                                            : null,
                                        icon: const Icon(Icons.edit_rounded),
                                      ),
                                      IconButton(
                                        tooltip: 'Supprimer',
                                        color: Colors.red,
                                        onPressed: _canManageSlot(it)
                                            ? () => _deleteSlot(it)
                                            : null,
                                        icon:
                                            const Icon(Icons.delete_outline_rounded),
                                      ),
                                      const SizedBox(width: 4),
                                      FilledButton.icon(
                                        onPressed: canJoin
                                            ? () => _joinTeleconsult(it)
                                            : null,
                                        icon: const Icon(Icons.videocam_rounded),
                                        label: const Text('Rejoindre'),
                                        style: FilledButton.styleFrom(
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
                        }),
                    ],
                  ),
      ),
    );
  }
}
