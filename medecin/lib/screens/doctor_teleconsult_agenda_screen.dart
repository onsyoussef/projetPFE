import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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
  static const Color _primaryBlue = Color(0xFF2459A8);
  static const Color _primaryBlueDark = Color(0xFF1A3D5F);
  static const Color _pageBg = Color(0xFFF5F7FA);
  static const Color _onSurfaceStrong = Color(0xFF1A2740);
  static const Color _textSecondary = Color(0xFF64748B);
  static const Color _infoBg = Color(0xFFE8F2FF);
  static const Color _slotsBg = Color(0xFFF1F5F9);
  static const Color _calMarkerDone = Color(0xFF16A34A);
  static const Color _calMarkerBusy = Color(0xFFF97316);

  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  List<_RdvRow> _monthList = [];
  bool _loading = true;
  String? _error;
  String? _selectedHeure;
  Set<String> _occupiedHeures = {};
  bool _loadingSlots = false;
  bool _booking = false;

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
    _selectedDay = _focusedDay;
    _loadMonth().then((_) => _refreshOccupiedSlots());
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

  Future<void> _refreshOccupiedSlots() async {
    final day = _selectedDay;
    if (day == null || _isPastDay(day)) {
      if (!mounted) return;
      setState(() {
        _occupiedHeures = {};
        _selectedHeure = null;
        _loadingSlots = false;
      });
      return;
    }
    setState(() => _loadingSlots = true);
    final occupied = await _occupiedHeuresForDay(day);
    if (!mounted) return;
    setState(() {
      _occupiedHeures = occupied;
      _loadingSlots = false;
      if (_selectedHeure != null &&
          (_occupiedHeures.contains(_selectedHeure) ||
              _isSlotPast(_selectedHeure!, day))) {
        _selectedHeure = null;
      }
    });
  }

  List<String> _generateSlots(int startHour, int startMin, int endHour, int endMin) {
    final out = <String>[];
    var cursor = DateTime(2000, 1, 1, startHour, startMin);
    final end = DateTime(2000, 1, 1, endHour, endMin);
    while (!cursor.isAfter(end)) {
      out.add(
        '${cursor.hour.toString().padLeft(2, '0')}:${cursor.minute.toString().padLeft(2, '0')}',
      );
      cursor = cursor.add(const Duration(minutes: 45));
    }
    return out;
  }

  bool _isSlotPast(String heure, DateTime day) {
    final parts = heure.split(':');
    if (parts.length < 2) return false;
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    final slotDt = DateTime(day.year, day.month, day.day, h, m);
    return slotDt.isBefore(DateTime.now());
  }

  bool _isSlotBlocked(String heure, DateTime day) =>
      _occupiedHeures.contains(heure) || _isSlotPast(heure, day);

  Future<void> _bookSlot(DateTime day, String heure) async {
    final local = DateTime(
      day.year,
      day.month,
      day.day,
      int.parse(heure.split(':')[0]),
      int.parse(heure.split(':')[1]),
    );
    final selectedDateLabel = '${day.day}/${day.month}/${day.year}';

    if (!local.isAfter(DateTime.now().subtract(const Duration(minutes: 1)))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choisissez un horaire dans le futur.')),
      );
      return;
    }

    if (_occupiedHeures.contains(heure)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('⛔ $heure est déjà réservé.')),
      );
      return;
    }

    setState(() => _booking = true);
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
      widget.onClose?.call();
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
    } finally {
      if (mounted) setState(() => _booking = false);
    }
  }

  Future<void> _confirmSelectedSlot() async {
    final day = _selectedDay;
    final heure = _selectedHeure;
    if (day == null || heure == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sélectionnez une date et un créneau horaire.'),
        ),
      );
      return;
    }
    await _bookSlot(day, heure);
  }

  Widget _buildPlanningHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 12, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: widget.onClose ?? () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            color: _primaryBlue,
          ),
          Text(
            'Planification',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: _primaryBlue,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoBox() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _infoBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: _primaryBlue, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Information importante',
                  style: TextStyle(
                    color: _primaryBlue,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Les créneaux déjà réservés ou passés ne sont pas sélectionnables. '
                  'Prévoyez environ 45 minutes pour la téléconsultation.',
                  style: TextStyle(
                    color: _primaryBlue.withValues(alpha: 0.9),
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeSlotChip(String heure, DateTime day) {
    final blocked = _isSlotBlocked(heure, day);
    final selected = _selectedHeure == heure;
    final occupied = _occupiedHeures.contains(heure);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: blocked
            ? null
            : () => setState(() => _selectedHeure = heure),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? _primaryBlue.withValues(alpha: 0.1) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? _primaryBlue
                  : blocked
                      ? const Color(0xFFE2E8F0)
                      : const Color(0xFFE2E8F0),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                heure,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: blocked
                      ? _textSecondary.withValues(alpha: 0.55)
                      : selected
                          ? _primaryBlue
                          : _onSurfaceStrong,
                  decoration: blocked ? TextDecoration.lineThrough : null,
                ),
              ),
              if (occupied) ...[
                const SizedBox(width: 6),
                Icon(
                  Icons.block_rounded,
                  size: 16,
                  color: _textSecondary.withValues(alpha: 0.5),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTimeSlotsSection() {
    final day = _selectedDay;
    if (day == null || _isPastDay(day)) {
      return const SizedBox.shrink();
    }

    final morning = _generateSlots(9, 0, 12, 0);
    final afternoon = _generateSlots(14, 0, 18, 0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _slotsBg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Horaires disponibles',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: _onSurfaceStrong,
            ),
          ),
          if (_loadingSlots)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else ...[
            const SizedBox(height: 14),
            Text(
              'MATINÉE',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: _textSecondary.withValues(alpha: 0.85),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: morning.map((h) => _buildTimeSlotChip(h, day)).toList(),
            ),
            const SizedBox(height: 16),
            Text(
              'APRÈS-MIDI',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: _textSecondary.withValues(alpha: 0.85),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children:
                  afternoon.map((h) => _buildTimeSlotChip(h, day)).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCalendarCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: TableCalendar<_RdvRow>(
        locale: 'fr_FR',
        firstDay: DateTime.utc(2020, 1, 1),
        lastDay: DateTime.utc(2035, 12, 31),
        focusedDay: _focusedDay,
        calendarFormat: CalendarFormat.month,
        availableCalendarFormats: const {CalendarFormat.month: 'Mois'},
        sixWeekMonthsEnforced: false,
        headerStyle: HeaderStyle(
          formatButtonVisible: false,
          titleCentered: true,
          titleTextFormatter: (date, locale) {
            final raw = DateFormat.yMMMM('fr_FR').format(date);
            if (raw.isEmpty) return raw;
            return '${raw[0].toUpperCase()}${raw.substring(1)}';
          },
          titleTextStyle: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: _onSurfaceStrong,
          ),
          leftChevronIcon: Icon(
            Icons.chevron_left_rounded,
            color: _textSecondary.withValues(alpha: 0.7),
            size: 26,
          ),
          rightChevronIcon: Icon(
            Icons.chevron_right_rounded,
            color: _textSecondary.withValues(alpha: 0.7),
            size: 26,
          ),
          headerPadding: const EdgeInsets.symmetric(vertical: 8),
        ),
        daysOfWeekHeight: 28,
        daysOfWeekStyle: DaysOfWeekStyle(
          weekdayStyle: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
            color: _textSecondary.withValues(alpha: 0.75),
          ),
          weekendStyle: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
            color: _textSecondary.withValues(alpha: 0.75),
          ),
        ),
        enabledDayPredicate: (d) => !_isPastDay(d),
        rowHeight: 42,
        selectedDayPredicate: (d) =>
            _selectedDay != null && isSameDay(d, _selectedDay),
        eventLoader: _rdvsForDay,
        startingDayOfWeek: StartingDayOfWeek.monday,
        onDaySelected: (sel, foc) {
          if (_isPastDay(sel)) return;
          setState(() {
            _selectedDay = _stripTime(sel);
            _focusedDay = foc;
            _selectedHeure = null;
          });
          _refreshOccupiedSlots();
        },
        onPageChanged: (f) {
          setState(() => _focusedDay = f);
          _loadMonth();
        },
        calendarStyle: CalendarStyle(
          outsideDaysVisible: true,
          cellMargin: const EdgeInsets.all(6),
          defaultTextStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: _onSurfaceStrong,
          ),
          weekendTextStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: _onSurfaceStrong,
          ),
          outsideTextStyle: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: _textSecondary.withValues(alpha: 0.35),
          ),
          todayDecoration: BoxDecoration(
            color: _primaryBlue.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          todayTextStyle: const TextStyle(
            color: _primaryBlue,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
          selectedDecoration: BoxDecoration(
            color: _primaryBlue,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: _primaryBlue.withValues(alpha: 0.35),
                blurRadius: 10,
                spreadRadius: 1,
              ),
            ],
          ),
          selectedTextStyle: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
          disabledTextStyle: TextStyle(
            fontSize: 14,
            color: _textSecondary.withValues(alpha: 0.35),
          ),
          markersMaxCount: 3,
          markerSize: 5,
          markerDecoration: const BoxDecoration(
            color: _calMarkerBusy,
            shape: BoxShape.circle,
          ),
        ),
        calendarBuilders: CalendarBuilders<_RdvRow>(
          dowBuilder: (context, day) {
            const labels = ['LUN', 'MAR', 'MER', 'JEU', 'VEN', 'SAM', 'DIM'];
            return Center(
              child: Text(
                labels[day.weekday - 1],
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: _textSecondary.withValues(alpha: 0.75),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildPlanifierButton() {
    final enabled = _selectedDay != null &&
        _selectedHeure != null &&
        !_booking &&
        !_isPastDay(_selectedDay!);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: BoxDecoration(
        color: _pageBg,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              colors: enabled
                  ? [_primaryBlue, _primaryBlueDark]
                  : [
                      _primaryBlue.withValues(alpha: 0.45),
                      _primaryBlueDark.withValues(alpha: 0.45),
                    ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: _primaryBlue.withValues(alpha: 0.35),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: enabled ? _confirmSelectedSlot : null,
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: Center(
                  child: _booking
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Planifier la séance',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: _primaryBlue),
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
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Prendre rendez-vous',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: _onSurfaceStrong,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Sélectionnez le créneau qui convient le mieux pour la téléconsultation avec ${widget.patientName}.',
            style: TextStyle(
              fontSize: 14,
              color: _textSecondary.withValues(alpha: 0.95),
              height: 1.45,
            ),
          ),
          const SizedBox(height: 20),
          _buildCalendarCard(),
          const SizedBox(height: 16),
          _buildInfoBox(),
          const SizedBox(height: 16),
          _buildTimeSlotsSection(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embeddedAsDialog) {
      return Material(
        color: _pageBg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SafeArea(bottom: false, child: _buildPlanningHeader()),
            Expanded(child: _buildMainContent()),
            _buildPlanifierButton(),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: _pageBg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildPlanningHeader(),
            Expanded(child: _buildMainContent()),
            _buildPlanifierButton(),
          ],
        ),
      ),
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
