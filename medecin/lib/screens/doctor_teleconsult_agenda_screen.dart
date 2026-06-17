import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

import '../services/api_service.dart';
import '../utils/doctor_ui_utils.dart';

/// Agenda téléconsultation après acceptation du formulaire (vue mois, mobile-first).
class DoctorTeleconsultAgendaScreen extends StatefulWidget {
  const DoctorTeleconsultAgendaScreen({
    super.key,
    required this.doctorId,
    required this.patientId,
    required this.patientName,
    this.patientPhotoPath,
    this.formulaireId,
    this.embeddedAsDialog = false,
    this.onClose,
  });

  final String doctorId;
  final String patientId;
  final String patientName;
  final String? patientPhotoPath;
  final String? formulaireId;
  /// Si vrai : en-tête avec fermeture (utilisé dans [showAsDialog]).
  final bool embeddedAsDialog;
  final VoidCallback? onClose;

  /// Popup centrée (calendrier + même flux qu’avant).
  static Future<void> showAsDialog(
    BuildContext context, {
    required String doctorId,
    required String patientId,
    required String patientName,
    String? patientPhotoPath,
    String? formulaireId,
  }) {
    final h = MediaQuery.sizeOf(context).height;
    final w = MediaQuery.sizeOf(context).width;
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: SizedBox(
            width: math.min(w - 28, 520),
            height: math.min(h * 0.9, 720),
            child: DoctorTeleconsultAgendaScreen(
              doctorId: doctorId,
              patientId: patientId,
              patientName: patientName,
              patientPhotoPath: patientPhotoPath,
              formulaireId: formulaireId,
              embeddedAsDialog: true,
              onClose: () => Navigator.of(ctx).pop(),
            ),
          ),
        );
      },
    );
  }

  @override
  State<DoctorTeleconsultAgendaScreen> createState() =>
      _DoctorTeleconsultAgendaScreenState();
}

class _RdvRow {
  _RdvRow.fromJson(Map<String, dynamic> j)
      : id = j['id']?.toString() ?? '',
        date = j['date']?.toString() ?? '',
        heure = j['heure']?.toString() ?? '',
        patientNom = j['patientNom']?.toString() ?? 'Patient',
        patientPhotoPath = j['patientPhotoPath']?.toString(),
        formulaireId = (j['formulaireId'] ?? j['formId'])?.toString(),
        statutEffectif = j['statutEffectif']?.toString() ??
            j['statut']?.toString() ??
            'confirme';

  final String id;
  final String date;
  final String heure;
  final String patientNom;
  final String? patientPhotoPath;
  final String? formulaireId;
  final String statutEffectif;
}

class _DoctorTeleconsultAgendaScreenState
    extends State<DoctorTeleconsultAgendaScreen> {
  /// Aligné sur [DoctorHomeScreen] / thème `MedecinApp` (seed 0xFF4FA8D5).
  static const Color _skyDark = Color(0xFF4FA8D5);
  static const Color _surfaceCalm = Color(0xFFE8F6FC);
  static const Color _onSurfaceStrong = Color(0xFF2C3E50);
  /// Calendrier : même codes que le dialogue `showScheduleTeleconsultDialog`.
  static const Color _calInk = Color(0xFF0F172A);
  static const Color _calTodayText = Color(0xFF0369A1);
  static const Color _calMarkerDone = Color(0xFF16A34A);
  static const Color _calMarkerBusy = Color(0xFFF97316);
  static const Color _calShellBg = Color(0xFFF8FAFC);

  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  DateTime? _hoveredDay;
  List<_RdvRow> _monthList = [];
  bool _loading = true;
  String? _error;

  String _monthKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

  String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  DateTime _stripTime(DateTime d) => DateTime(d.year, d.month, d.day);

  bool _isPastDay(DateTime day) =>
      _stripTime(day).isBefore(_stripTime(DateTime.now()));

  @override
  void initState() {
    super.initState();
    _focusedDay = _stripTime(DateTime.now());
    _loadMonth();
  }

  Future<void> _loadMonth() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ApiService.getRendezVousMonth(
        medecinId: widget.doctorId,
        moisYYYYMM: _monthKey(_focusedDay),
      );
      final raw = data['rendezvous'];
      final list = <_RdvRow>[];
      if (raw is List) {
        for (final e in raw) {
          if (e is Map) list.add(_RdvRow.fromJson(Map<String, dynamic>.from(e)));
        }
      }
      if (mounted) {
        setState(() {
          _monthList = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  List<_RdvRow> _rdvsForDay(DateTime day) {
    final k = _dateKey(day);
    return _monthList.where((r) => r.date == k).toList();
  }

  String _humanDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  int get _countMonth => _monthList.length;

  static Widget _agendaLegendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.blueGrey.shade700,
          ),
        ),
      ],
    );
  }

  void _goToday() {
    final n = _stripTime(DateTime.now());
    setState(() {
      _focusedDay = n;
      _selectedDay = n;
    });
    _loadMonth();
  }

  Future<Set<String>> _occupiedHeuresForDay(DateTime day) async {
    final key = _dateKey(day);
    try {
      final data = await ApiService.getRendezVousForDate(
        medecinId: widget.doctorId,
        dateYYYYMMDD: key,
      );
      final raw = data['rendezvous'];
      final out = <String>{};
      if (raw is List) {
        for (final e in raw) {
          if (e is! Map) continue;
          final h = e['heure']?.toString();
          if (h != null && h.isNotEmpty) out.add(h);
        }
      }
      return out;
    } catch (_) {
      return _rdvsForDay(day).map((r) => r.heure).toSet();
    }
  }

  Future<void> _openQuickBookingClock(DateTime day) async {
    if (_isPastDay(day)) return;
    final occupied = await _occupiedHeuresForDay(day);
    if (!mounted) return;
    final picked = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 9, minute: 0),
      initialEntryMode: TimePickerEntryMode.dial,
      confirmText: 'Confirmer',
    );
    if (picked == null || !mounted) return;

    final heure =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    final local = DateTime(
      day.year,
      day.month,
      day.day,
      picked.hour,
      picked.minute,
    );
    final selectedDateLabel = '${day.day}/${day.month}/${day.year}';

    if (!local.isAfter(DateTime.now().subtract(const Duration(minutes: 1)))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choisissez un horaire dans le futur.')),
      );
      return;
    }

    if (occupied.contains(heure)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('⛔ $heure est déjà réservé.')),
      );
      return;
    }

    try {
      await ApiService.postRendezVous(
        medecinId: widget.doctorId,
        patientId: widget.patientId,
        formulaireId: widget.formulaireId,
        dateYYYYMMDD: _dateKey(day),
        heureHHmm: heure,
        startAtIsoUtc: local.toUtc().toIso8601String(),
      );
      if (widget.formulaireId != null && widget.formulaireId!.isNotEmpty) {
        await ApiService.patchTeleconsultFormWorkflow(
          formId: widget.formulaireId!,
          doctorId: widget.doctorId,
          status: 'scheduled',
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Rendez-vous fixé le $selectedDateLabel à $heure'),
        ),
      );
      await _loadMonth();
    } on RendezVousConflictException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Créneau déjà pris : ${e.date ?? _dateKey(day)} à ${e.heure ?? heure}.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  Widget _buildMainContent(double calMaxH) {
    final width = MediaQuery.sizeOf(context).width;
    final isPhone = width < 430;
    final isVeryCompact = width < 360;
    final baseRowHeight = isVeryCompact ? 38.0 : (isPhone ? 42.0 : 48.0);
    // Évite l'overflow du widget interne de TableCalendar quand la popup est basse.
    const reservedCalendarChrome = 88.0; // header + jours semaine + marges
    final maxRowHeightFromSpace = ((calMaxH - reservedCalendarChrome) / 6).clamp(26.0, 56.0);
    final rowHeight = math.min(baseRowHeight, maxRowHeightFromSpace);
    final horizontalPad = isVeryCompact ? 8.0 : (isPhone ? 10.0 : 12.0);

    if (_loading) {
      return Center(
        child: CircularProgressIndicator(
          color: Theme.of(context).colorScheme.primary,
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
        Padding(
          padding: EdgeInsets.fromLTRB(horizontalPad, 8, horizontalPad, 4),
          child: Text(
            'Patient : ${widget.patientName}',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: isVeryCompact ? 14 : (isPhone ? 15 : 16),
              color: _onSurfaceStrong,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(horizontalPad, 0, horizontalPad, 4),
          child: Row(
            children: [
              TextButton(
                style: TextButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  foregroundColor: _skyDark,
                ),
                onPressed: _goToday,
                child: const Text('Aujourd\'hui'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$_countMonth rendez-vous ce mois',
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.blueGrey.shade700,
                    fontWeight: FontWeight.w600,
                    fontSize: isVeryCompact ? 11 : (isPhone ? 12 : 13),
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(horizontalPad + 4, 0, horizontalPad + 4, 6),
          child: Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              _agendaLegendDot(_calMarkerDone, 'Terminé'),
              _agendaLegendDot(_calMarkerBusy, 'À venir / autre'),
            ],
          ),
        ),
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: calMaxH),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _calShellBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.blueGrey.shade100),
              ),
              child: TableCalendar<_RdvRow>(
                locale: 'fr_FR',
                firstDay: DateTime.utc(2020, 1, 1),
                lastDay: DateTime.utc(2035, 12, 31),
                focusedDay: _focusedDay,
                calendarFormat: CalendarFormat.month,
                availableCalendarFormats: const {
                  CalendarFormat.month: 'Mois',
                },
                sixWeekMonthsEnforced: false,
                headerVisible: true,
                daysOfWeekHeight: 28,
                daysOfWeekStyle: DaysOfWeekStyle(
                  weekdayStyle: TextStyle(
                    fontSize: isVeryCompact ? 10 : 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.blueGrey.shade600,
                  ),
                  weekendStyle: TextStyle(
                    fontSize: isVeryCompact ? 10 : 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.blueGrey.shade500,
                  ),
                ),
                headerStyle: HeaderStyle(
                  formatButtonVisible: false,
                  titleCentered: true,
                  titleTextStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: _calInk,
                  ),
                  leftChevronIcon: Icon(
                    Icons.chevron_left_rounded,
                    color: Colors.blueGrey.shade700,
                    size: isVeryCompact ? 24 : 28,
                  ),
                  rightChevronIcon: Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.blueGrey.shade700,
                    size: isVeryCompact ? 24 : 28,
                  ),
                  headerMargin: const EdgeInsets.only(bottom: 4),
                ),
                enabledDayPredicate: (d) => !_isPastDay(d),
                rowHeight: rowHeight,
                selectedDayPredicate: (d) =>
                    _selectedDay != null && isSameDay(d, _selectedDay),
                eventLoader: _rdvsForDay,
                startingDayOfWeek: StartingDayOfWeek.monday,
                onDaySelected: (sel, foc) async {
                  if (_isPastDay(sel)) return;
                  setState(() {
                    _selectedDay = _stripTime(sel);
                    _hoveredDay = _stripTime(sel);
                    _focusedDay = foc;
                  });
                },
                onPageChanged: (f) {
                  _focusedDay = f;
                  _hoveredDay = null;
                  _loadMonth();
                },
                calendarStyle: CalendarStyle(
                  outsideDaysVisible: false,
                  cellMargin: const EdgeInsets.all(2),
                  defaultTextStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _calInk,
                  ),
                  weekendTextStyle: TextStyle(
                    fontSize: isVeryCompact ? 12 : 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.blueGrey.shade500,
                  ),
                  outsideTextStyle: TextStyle(
                    fontSize: isVeryCompact ? 12 : 13,
                    color: Colors.blueGrey.shade300,
                  ),
                  selectedDecoration: const BoxDecoration(
                    color: _skyDark,
                    shape: BoxShape.circle,
                  ),
                  selectedTextStyle: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                  todayDecoration: BoxDecoration(
                    color: _skyDark.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _skyDark.withValues(alpha: 0.75),
                      width: 2,
                    ),
                  ),
                  todayTextStyle: const TextStyle(
                    color: _calTodayText,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                  markersMaxCount: 6,
                  markerDecoration: const BoxDecoration(
                    color: _calMarkerDone,
                    shape: BoxShape.circle,
                  ),
                  markersAlignment: Alignment.bottomCenter,
                  disabledTextStyle: TextStyle(
                    fontSize: isVeryCompact ? 12 : 13,
                    color: Colors.blueGrey.shade300,
                  ),
                ),
                calendarBuilders: CalendarBuilders<_RdvRow>(
                  defaultBuilder: (context, day, focusedDay) {
                    return MouseRegion(
                      onEnter: (_) {
                        if (!mounted) return;
                        setState(() => _hoveredDay = _stripTime(day));
                      },
                      onExit: (_) {
                        if (!mounted) return;
                        setState(() {
                          if (_hoveredDay != null && isSameDay(_hoveredDay, day)) {
                            _hoveredDay = null;
                          }
                        });
                      },
                      child: Center(
                        child: Text(
                          '${day.day}',
                          style: TextStyle(
                            fontSize: isVeryCompact ? 12 : 13,
                            fontWeight: FontWeight.w600,
                            color: _calInk,
                          ),
                        ),
                      ),
                    );
                  },
                  todayBuilder: (context, day, focusedDay) {
                    return MouseRegion(
                      onEnter: (_) {
                        if (!mounted) return;
                        setState(() => _hoveredDay = _stripTime(day));
                      },
                      onExit: (_) {
                        if (!mounted) return;
                        setState(() {
                          if (_hoveredDay != null && isSameDay(_hoveredDay, day)) {
                            _hoveredDay = null;
                          }
                        });
                      },
                      child: Center(
                        child: Container(
                          width: isVeryCompact ? 30 : 34,
                          height: isVeryCompact ? 30 : 34,
                          decoration: BoxDecoration(
                            color: _skyDark.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _skyDark.withValues(alpha: 0.75),
                              width: 2,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '${day.day}',
                            style: TextStyle(
                              color: _calTodayText,
                              fontWeight: FontWeight.w800,
                              fontSize: isVeryCompact ? 12 : 13,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                  selectedBuilder: (context, day, focusedDay) {
                    return MouseRegion(
                      onEnter: (_) {
                        if (!mounted) return;
                        setState(() => _hoveredDay = _stripTime(day));
                      },
                      onExit: (_) {
                        if (!mounted) return;
                        setState(() {
                          if (_hoveredDay != null && isSameDay(_hoveredDay, day)) {
                            _hoveredDay = null;
                          }
                        });
                      },
                      child: Center(
                        child: Container(
                          width: isVeryCompact ? 30 : 34,
                          height: isVeryCompact ? 30 : 34,
                          decoration: const BoxDecoration(
                            color: _skyDark,
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '${day.day}',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: isVeryCompact ? 12 : 13,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                  markerBuilder: (context, day, events) {
                    if (events.isEmpty) return null;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final e in events)
                            Container(
                              margin: const EdgeInsets.symmetric(horizontal: 1.5),
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: e.statutEffectif == 'termine'
                                    ? _calMarkerDone
                                    : _calMarkerBusy,
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
        if (_hoveredDay != null)
          Padding(
            padding: EdgeInsets.fromLTRB(horizontalPad, 8, horizontalPad, 4),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blueGrey.shade100),
              ),
              child: Builder(
                builder: (_) {
                  final day = _hoveredDay!;
                  final rows = _rdvsForDay(day)..sort((a, b) => a.heure.compareTo(b.heure));
                  if (rows.isEmpty) {
                    return Text(
                      'Aucun rendez-vous le ${_humanDate(day)}',
                      style: TextStyle(
                        fontSize: 13,
                        color: _onSurfaceStrong.withValues(alpha: 0.75),
                      ),
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Rendez-vous du ${_humanDate(day)}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: _onSurfaceStrong,
                        ),
                      ),
                      const SizedBox(height: 6),
                      for (final r in rows)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            '${r.patientNom} — ${_humanDate(day)} à ${r.heure}',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        Padding(
          padding: EdgeInsets.fromLTRB(horizontalPad, 8, horizontalPad, 12),
          child: Text(
            widget.embeddedAsDialog
                ? 'Choisissez une date, puis ouvrez le jour pour fixer ou modifier '
                    'un rendez-vous (date et heure modifiables via ✏️).'
                : 'Choisissez une date future pour voir les créneaux '
                    'et fixer ou modifier un rendez-vous.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: isVeryCompact ? 12 : (widget.embeddedAsDialog ? 13 : 14),
              color: _onSurfaceStrong.withValues(alpha: 0.88),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(horizontalPad, 0, horizontalPad, 12),
          child: Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: isPhone ? double.infinity : math.max(width * 0.42, 180),
                child: Text(
                  _selectedDay == null
                      ? 'Sélectionnez une date'
                      : '${_selectedDay!.day}/${_selectedDay!.month}/${_selectedDay!.year}',
                  style: TextStyle(
                    fontSize: isVeryCompact ? 12 : 13,
                    color: _onSurfaceStrong.withValues(alpha: 0.7),
                  ),
                ),
              ),
              Tooltip(
                message: (_selectedDay == null || _isPastDay(_selectedDay!))
                    ? 'Veuillez sélectionner une date'
                    : 'Fixer un rendez-vous',
                child: FilledButton(
                  onPressed: (_selectedDay == null || _isPastDay(_selectedDay!))
                      ? null
                      : () => _openQuickBookingClock(_selectedDay!),
                  style: FilledButton.styleFrom(
                    backgroundColor: _skyDark,
                    foregroundColor: Colors.white,
                    minimumSize: Size(
                      isPhone ? double.infinity : 180,
                      isVeryCompact ? 42 : 46,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Fixer un rendez-vous'),
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
    final sz = MediaQuery.sizeOf(context);
    final isVeryCompact = sz.width < 360;
    final calMaxH = widget.embeddedAsDialog
        ? math.min(isVeryCompact ? 340.0 : 400.0, sz.height * (isVeryCompact ? 0.48 : 0.52))
        : sz.height * (isVeryCompact ? 0.52 : 0.58);

    final body = _buildMainContent(calMaxH);

    if (widget.embeddedAsDialog) {
      return Material(
        color: _surfaceCalm,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: _skyDark,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: SafeArea(
                bottom: false,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Planifier la téléconsultation',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white),
                      constraints: const BoxConstraints(
                        minWidth: 48,
                        minHeight: 48,
                      ),
                      onPressed: widget.onClose,
                    ),
                  ],
                ),
              ),
            ),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: _surfaceCalm,
      appBar: AppBar(
        title: const Text('Planifier la téléconsultation'),
        backgroundColor: _skyDark,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(child: body),
    );
  }
}

class _DayAppointmentsSheet extends StatefulWidget {
  const _DayAppointmentsSheet({
    required this.maxHeight,
    required this.day,
    required this.doctorId,
    required this.patientId,
    required this.patientName,
    required this.initialList,
    required this.onChanged,
    required this.onRefreshDay,
  });

  final double maxHeight;
  final DateTime day;
  final String doctorId;
  final String patientId;
  final String patientName;
  final List<_RdvRow> initialList;
  final VoidCallback onChanged;
  final Future<List<_RdvRow>> Function() onRefreshDay;

  @override
  State<_DayAppointmentsSheet> createState() => _DayAppointmentsSheetState();
}

class _DayAppointmentsSheetState extends State<_DayAppointmentsSheet> {
  late List<_RdvRow> _list;
  bool _loading = false;
  static const _jours = [
    'lundi',
    'mardi',
    'mercredi',
    'jeudi',
    'vendredi',
    'samedi',
    'dimanche',
  ];
  static const _mois = [
    '',
    'janvier',
    'février',
    'mars',
    'avril',
    'mai',
    'juin',
    'juillet',
    'août',
    'septembre',
    'octobre',
    'novembre',
    'décembre',
  ];

  @override
  void initState() {
    super.initState();
    _list = List.of(widget.initialList);
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final fresh = await widget.onRefreshDay();
    if (mounted) {
      setState(() {
        _list = fresh;
        _loading = false;
      });
    }
  }

  String _titleDay() {
    final d = widget.day;
    return '${_jours[d.weekday - 1]} ${d.day} ${_mois[d.month]} ${d.year}';
  }

  String _dateKey() =>
      '${widget.day.year.toString().padLeft(4, '0')}-${widget.day.month.toString().padLeft(2, '0')}-${widget.day.day.toString().padLeft(2, '0')}';

  DateTime _stripDay(DateTime d) => DateTime(d.year, d.month, d.day);

  String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  DateTime? _parseYmd(String? s) {
    if (s == null || s.length < 10) return null;
    return DateTime.tryParse(s.substring(0, 10));
  }

  String _longTitleFor(DateTime d) {
    return '${_jours[d.weekday - 1]} ${d.day} ${_mois[d.month]} ${d.year}';
  }

  Future<Set<String>> _occupiedHeures(
    DateTime day, {
    String? excludeRdvId,
  }) async {
    final key = _ymd(_stripDay(day));
    try {
      final data = await ApiService.getRendezVousForDate(
        medecinId: widget.doctorId,
        dateYYYYMMDD: key,
      );
      final raw = data['rendezvous'];
      final out = <String>{};
      if (raw is List) {
        for (final e in raw) {
          if (e is! Map) continue;
          final id = e['id']?.toString() ?? '';
          if (excludeRdvId != null && id == excludeRdvId) continue;
          final h = e['heure']?.toString();
          if (h != null && h.isNotEmpty) out.add(h);
        }
      }
      return out;
    } catch (_) {
      if (key == _dateKey()) {
        return _list
            .where((r) => excludeRdvId == null || r.id != excludeRdvId)
            .map((r) => r.heure)
            .toSet();
      }
      return {};
    }
  }

  Future<void> _bookOrEdit({_RdvRow? existing}) async {
    final todayStart = _stripDay(DateTime.now());
    var dayForAppt = _stripDay(widget.day);

    if (existing != null) {
      final fromRdv = _parseYmd(existing.date);
      if (fromRdv != null) dayForAppt = _stripDay(fromRdv);
      if (!mounted) return;
      final pickedDate = await showDatePicker(
        context: context,
        initialDate: dayForAppt.isBefore(todayStart) ? todayStart : dayForAppt,
        firstDate: todayStart,
        lastDate: todayStart.add(const Duration(days: 365 * 2)),
        helpText: 'Nouvelle date du rendez-vous',
      );
      if (pickedDate == null || !mounted) return;
      dayForAppt = _stripDay(pickedDate);
    }

    final initial = existing != null
        ? _parseHeure(existing.heure)
        : TimeOfDay.now().replacing(minute: 0);
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context),
          child: child!,
        );
      },
    );
    if (picked == null || !mounted) return;

    final local = DateTime(
      dayForAppt.year,
      dayForAppt.month,
      dayForAppt.day,
      picked.hour,
      picked.minute,
    );
    if (!local.isAfter(DateTime.now().subtract(const Duration(minutes: 1)))) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Choisissez un horaire dans le futur.')),
        );
      }
      return;
    }

    final heure =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    final dateStr = _ymd(dayForAppt);

    final occupied = await _occupiedHeures(
      dayForAppt,
      excludeRdvId: existing?.id,
    );
    if (!mounted) return;
    if (occupied.contains(heure)) {
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Créneau déjà réservé'),
            content: Text('Le $dateStr à $heure est déjà pris.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
      return;
    }

    final slotsSameDay = dateStr == _dateKey() ? _list : <_RdvRow>[];

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'Confirmer' : 'Modifier le rendez-vous'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Date : ${_longTitleFor(dayForAppt)}'),
              Text('Heure : $heure'),
              const SizedBox(height: 8),
              Text('Patient : ${widget.patientName}'),
              const SizedBox(height: 8),
              const Text('Type : Téléconsultation'),
              if (slotsSameDay.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  'Créneaux occupés ce jour (liste du jour ouvert) :',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: slotsSameDay
                        .map(
                          (r) => Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Chip(
                              label: Text(
                                '${r.heure} • ${r.patientNom}',
                                overflow: TextOverflow.ellipsis,
                              ),
                              backgroundColor: Colors.red.shade50,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(existing == null ? 'Confirmer' : 'Enregistrer'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      if (existing == null) {
        await ApiService.postRendezVous(
          medecinId: widget.doctorId,
          patientId: widget.patientId,
          formulaireId: null,
          dateYYYYMMDD: dateStr,
          heureHHmm: heure,
          startAtIsoUtc: local.toUtc().toIso8601String(),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Rendez-vous confirmé pour ${widget.patientName} le $dateStr à $heure',
              ),
            ),
          );
        }
      } else {
        await ApiService.putRendezVous(
          rendezvousId: existing.id,
          medecinId: widget.doctorId,
          dateYYYYMMDD: dateStr,
          heureHHmm: heure,
          startAtIsoUtc: local.toUtc().toIso8601String(),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Rendez-vous mis à jour : $dateStr à $heure',
              ),
            ),
          );
        }
      }
      widget.onChanged();
    } on RendezVousConflictException catch (e) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Créneau déjà réservé'),
          content: Text(
            'Le ${e.date ?? dateStr} à ${e.heure ?? heure} est déjà pris'
            '${e.patientNom != null ? ' par ${e.patientNom}' : ''}.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Choisir une autre date ou heure'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  TimeOfDay _parseHeure(String h) {
    final p = h.split(':');
    if (p.length >= 2) {
      final hh = int.tryParse(p[0].trim()) ?? 9;
      final mm = int.tryParse(p[1].trim()) ?? 0;
      return TimeOfDay(hour: hh.clamp(0, 23), minute: mm.clamp(0, 59));
    }
    return const TimeOfDay(hour: 9, minute: 0);
  }

  Future<void> _cancel(_RdvRow r) async {
    final motifCtrl = TextEditingController();
    try {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Annuler ce rendez-vous ?'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${r.patientNom} — ${_dateKey()} à ${r.heure}'),
                const SizedBox(height: 12),
                TextField(
                  controller: motifCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Motif de l\'annulation (optionnel)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Non, garder'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Oui, annuler'),
            ),
          ],
        ),
      );
      if (go != true || !mounted) return;
      try {
        await ApiService.deleteRendezVous(
          rendezvousId: r.id,
          medecinId: widget.doctorId,
          motif: motifCtrl.text.trim(),
        );
        final formId = r.formulaireId?.trim() ?? '';
        if (formId.isNotEmpty) {
          await ApiService.patchTeleconsultFormWorkflow(
            formId: formId,
            doctorId: widget.doctorId,
            status: 'pending',
          );
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Rendez-vous annulé')),
          );
        }
        widget.onChanged();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content:
                    Text(e.toString().replaceFirst('Exception: ', ''))),
          );
        }
      }
    } finally {
      motifCtrl.dispose();
    }
  }

  String _badgeStatut(String s) {
    switch (s) {
      case 'termine':
        return 'Terminé';
      case 'annule':
        return 'Annulé';
      default:
        return 'Confirmé';
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.maxHeight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _titleDay(),
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF2C3E50),
                            ),
                      ),
                      Text(
                        '${_list.length} rendez-vous',
                        style: TextStyle(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _list.isEmpty
                    ? Center(
                        child: ListView(
                          shrinkWrap: true,
                          children: const [
                            Icon(Icons.event_busy_rounded, size: 56),
                            SizedBox(height: 12),
                            Text(
                              'Aucun rendez-vous ce jour',
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: _list.length,
                        itemBuilder: (context, i) {
                          final r = _list[i];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    r.heure,
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                      color: Theme.of(context).colorScheme.primary,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      patientAvatarForDoctor(
                                        name: r.patientNom,
                                        patientPhotoPath: r.patientPhotoPath,
                                        radius: 22,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          r.patientNom,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  const Text('Téléconsultation'),
                                  const SizedBox(height: 6),
                                  Chip(
                                    label: Text(_badgeStatut(r.statutEffectif)),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.edit_rounded),
                                        constraints: const BoxConstraints(
                                          minWidth: 48,
                                          minHeight: 48,
                                        ),
                                        onPressed: r.statutEffectif == 'termine'
                                            ? null
                                            : () => _bookOrEdit(existing: r),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline_rounded),
                                        color: Colors.red,
                                        constraints: const BoxConstraints(
                                          minWidth: 48,
                                          minHeight: 48,
                                        ),
                                        onPressed: r.statutEffectif == 'termine'
                                            ? null
                                            : () => _cancel(r),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    minimumSize: const Size(double.infinity, 48),
                  ),
                  onPressed: () => _bookOrEdit(),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Fixer un rendez-vous'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
