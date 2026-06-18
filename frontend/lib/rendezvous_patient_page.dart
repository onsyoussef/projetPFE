import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';

import 'espace_patient_page.dart';
import 'services/api_service.dart';
import 'utils/patient_ui_utils.dart';

class RendezVousPatientPage extends StatelessWidget {
  const RendezVousPatientPage({
    super.key,
    required this.patientName,
    required this.patientId,
  });

  final String patientName;
  final String patientId;

  @override
  Widget build(BuildContext context) {
    return _RendezVousPatientBody(
      patientName: patientName,
      patientId: patientId,
    );
  }
}

class _RendezVousPatientBody extends StatefulWidget {
  const _RendezVousPatientBody({
    required this.patientName,
    required this.patientId,
  });

  final String patientName;
  final String patientId;

  @override
  State<_RendezVousPatientBody> createState() => _RendezVousPatientBodyState();
}

class _RendezVousPatientBodyState extends State<_RendezVousPatientBody> {
  static const Color _titleNavy = Color(0xFF1A458B);
  static const Color _pageBg = Color(0xFFF1F5F9);
  static const Color _chipBlue = Color(0xFF4A90E2);
  static const Color _chipCyan = Color(0xFF26A69A);
  static const Color _chipGrey = Color(0xFF9CA3AF);

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _slots = [];
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
  );

  @override
  void initState() {
    super.initState();
    _load();
  }

  DateTime? _slotLocal(Map<String, dynamic> slot) {
    final iso = slot['scheduledAt'];
    if (iso is! String || iso.isEmpty) return null;
    final dt = DateTime.tryParse(iso);
    return dt?.toLocal();
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _pad2(int v) => v.toString().padLeft(2, '0');

  String _fmtDate(DateTime d) => '${_pad2(d.day)}/${_pad2(d.month)}/${d.year}';

  String _fmtTime(DateTime d) => '${_pad2(d.hour)}:${_pad2(d.minute)}';

  List<Map<String, dynamic>> _eventsForDay(DateTime day) {
    return _slots.where((s) {
      final local = _slotLocal(s);
      return local != null && _sameDay(local, day);
    }).toList();
  }

  String _weekdayFr(DateTime d) {
    const names = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
    return names[d.weekday - 1];
  }

  _AppointmentStyle _styleForSlot(Map<String, dynamic> slot, DateTime d) {
    final se = slot['statutEffectif']?.toString() ?? '';
    if (se == 'annule') {
      return const _AppointmentStyle(
        label: 'Annulé',
        chipBg: Color(0xFFFEE2E2),
        chipText: Color(0xFFB91C1C),
        accent: Color(0xFFDC2626),
      );
    }
    if (se == 'termine') {
      return const _AppointmentStyle(
        label: 'Terminé',
        chipBg: Color(0xFFECFDF5),
        chipText: Color(0xFF15803D),
        accent: Color(0xFF22C55E),
      );
    }
    return _styleForDate(d);
  }

  _AppointmentStyle _styleForDate(DateTime d) {
    final now = DateTime.now();
    final dayOnly = DateTime(d.year, d.month, d.day);
    final todayOnly = DateTime(now.year, now.month, now.day);
    if (dayOnly == todayOnly) {
      return const _AppointmentStyle(
        label: 'Aujourd\'hui',
        chipBg: Color(0xFFE0F2FE),
        chipText: Color(0xFF0369A1),
        accent: Color(0xFF0284C7),
      );
    }
    if (d.isBefore(now)) {
      return const _AppointmentStyle(
        label: 'Passé',
        chipBg: Color(0xFFF1F5F9),
        chipText: Color(0xFF475569),
        accent: Color(0xFF64748B),
      );
    }
    return const _AppointmentStyle(
      label: 'À venir',
      chipBg: Color(0xFFECFDF5),
      chipText: Color(0xFF15803D),
      accent: Color(0xFF22C55E),
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        ApiService.getPatientScheduledTeleconsults(patientId: widget.patientId),
        ApiService.getPatientRendezVousApi(patientId: widget.patientId),
      ]);
      final fromChat = results[0] as List<Map<String, dynamic>>;
      final pack = results[1] as Map<String, dynamic>;
      final apiSlots = <Map<String, dynamic>>[];
      void pushList(dynamic L) {
        if (L is! List) return;
        for (final e in L) {
          if (e is! Map) continue;
          final m = Map<String, dynamic>.from(e);
          final iso = m['startAt']?.toString();
          if (iso == null || iso.isEmpty) continue;
          apiSlots.add({
            'scheduledAt': iso,
            'doctorName': readableDoctorName(m['medecinNom']?.toString()),
            'doctorPhotoPath': m['medecinPhotoPath']?.toString(),
            'content': 'Téléconsultation (agenda)',
            'statutEffectif': m['statutEffectif']?.toString() ?? 'confirme',
          });
        }
      }

      pushList(pack['aVenir']);
      pushList(pack['historique']);
      if (!mounted) return;
      setState(() {
        _slots = [...fromChat, ...apiSlots];
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

  List<Map<String, dynamic>> get _slotsSelectedDay {
    final items = _slots.where((s) {
      final local = _slotLocal(s);
      return local != null && _sameDay(local, _selectedDay);
    }).toList();
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
    final perDayCount = <DateTime, int>{};
    for (final s in _slots) {
      final local = _slotLocal(s);
      if (local == null) continue;
      final key = DateTime(local.year, local.month, local.day);
      perDayCount[key] = (perDayCount[key] ?? 0) + 1;
    }
    final daysWithAppointments = perDayCount.keys.toList()
      ..sort((a, b) => a.compareTo(b));
    final legendDays = daysWithAppointments.take(7).toList();

    return Scaffold(
      backgroundColor: _pageBg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(4, 4, 12, 12),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                      color: _titleNavy,
                      onPressed: () async {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setString('lastRoute', 'espace_patient');
                        if (!context.mounted) return;
                        final didPop = await Navigator.of(context).maybePop();
                        if (didPop || !context.mounted) return;
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute<void>(
                            builder: (_) => EspacePatientPage(
                              patientId: widget.patientId,
                              patientName: widget.patientName,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  Text(
                    'Mes rendez-vous',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: _titleNavy,
                          fontWeight: FontWeight.w700,
                          fontSize: 20,
                          letterSpacing: -0.2,
                        ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  children: [
                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFFFDECF2),
                            Color(0xFFE3F2FD),
                          ],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.calendar_month_rounded,
                              color: _titleNavy,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Bonjour ${readablePatientName(widget.patientName)}, consultez votre planning de téléconsultation fixé par le médecin.',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: const Color(0xFF374151),
                                    fontWeight: FontWeight.w500,
                                    height: 1.35,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: TableCalendar<Map<String, dynamic>>(
                        firstDay: DateTime.now().subtract(const Duration(days: 365)),
                        lastDay: DateTime.now().add(const Duration(days: 730)),
                        focusedDay: _focusedDay,
                        selectedDayPredicate: (day) => isSameDay(day, _selectedDay),
                        onDaySelected: (selectedDay, focusedDay) {
                          setState(() {
                            _selectedDay = selectedDay;
                            _focusedDay = focusedDay;
                          });
                        },
                        onPageChanged: (focusedDay) {
                          _focusedDay = focusedDay;
                        },
                        eventLoader: _eventsForDay,
                        headerStyle: HeaderStyle(
                          formatButtonVisible: false,
                          titleCentered: true,
                          titleTextStyle: Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: const Color(0xFF6B7280),
                                fontWeight: FontWeight.w600,
                              ) ??
                              const TextStyle(
                                color: Color(0xFF6B7280),
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                          leftChevronIcon: const Icon(
                            Icons.chevron_left_rounded,
                            color: Color(0xFF9CA3AF),
                          ),
                          rightChevronIcon: const Icon(
                            Icons.chevron_right_rounded,
                            color: Color(0xFF9CA3AF),
                          ),
                        ),
                        daysOfWeekStyle: const DaysOfWeekStyle(
                          weekdayStyle: TextStyle(
                            color: Color(0xFF9CA3AF),
                            fontWeight: FontWeight.w500,
                            fontSize: 13,
                          ),
                          weekendStyle: TextStyle(
                            color: Color(0xFF9CA3AF),
                            fontWeight: FontWeight.w500,
                            fontSize: 13,
                          ),
                        ),
                        calendarStyle: CalendarStyle(
                          outsideDaysVisible: true,
                          defaultTextStyle: const TextStyle(
                            color: Color(0xFF374151),
                            fontWeight: FontWeight.w500,
                          ),
                          weekendTextStyle: const TextStyle(
                            color: Color(0xFF374151),
                            fontWeight: FontWeight.w500,
                          ),
                          outsideTextStyle: const TextStyle(
                            color: Color(0xFFD1D5DB),
                            fontWeight: FontWeight.w400,
                          ),
                          todayDecoration: BoxDecoration(
                            color: _titleNavy.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          todayTextStyle: const TextStyle(
                            color: _titleNavy,
                            fontWeight: FontWeight.w700,
                          ),
                          selectedDecoration: const BoxDecoration(
                            color: _titleNavy,
                            shape: BoxShape.circle,
                          ),
                          selectedTextStyle: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                          markerDecoration: const BoxDecoration(
                            color: _titleNavy,
                            shape: BoxShape.circle,
                          ),
                          markerSize: 6,
                          markersMaxCount: 3,
                        ),
                        calendarBuilders: CalendarBuilders<Map<String, dynamic>>(
                          markerBuilder: (context, day, events) {
                            if (events.isEmpty) return const SizedBox.shrink();
                            final count = events.length > 3 ? 3 : events.length;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: List.generate(count, (index) {
                                  return Container(
                                    width: 5.5,
                                    height: 5.5,
                                    margin: const EdgeInsets.symmetric(horizontal: 1.3),
                                    decoration: const BoxDecoration(
                                      color: _titleNavy,
                                      shape: BoxShape.circle,
                                    ),
                                  );
                                }),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _Badge(
                          icon: Icons.calendar_today_rounded,
                          text: 'Date: ${_fmtDate(_selectedDay)}',
                          color: _chipBlue,
                          backgroundColor: const Color(0xFFE8F4FD),
                        ),
                        _Badge(
                          icon: Icons.event_note_rounded,
                          text: '${_slotsSelectedDay.length} rendez-vous ce jour',
                          color: _chipCyan,
                          backgroundColor: const Color(0xFFE0F7FA),
                        ),
                        _Badge(
                          icon: Icons.checklist_rounded,
                          text: '${_slots.length} total',
                          color: _chipGrey,
                          backgroundColor: const Color(0xFFF3F4F6),
                          bordered: false,
                        ),
                      ],
                    ),
            if (legendDays.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Jours avec des rendez-vous',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: _titleNavy,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 42,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemBuilder: (context, i) {
                    final d = legendDays[i];
                    final n = perDayCount[d] ?? 0;
                    final selected = _sameDay(d, _selectedDay);
                    return InkWell(
                      onTap: () => setState(() => _selectedDay = d),
                      borderRadius: BorderRadius.circular(999),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? const Color(0xFFE8F4FD)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: selected
                                ? _chipBlue.withValues(alpha: 0.45)
                                : const Color(0xFFE5E7EB),
                          ),
                        ),
                        child: Center(
                          child: Text(
                            '${_weekdayFr(d)} ${_pad2(d.day)} · $n',
                            style: TextStyle(
                              color: selected ? _titleNavy : const Color(0xFF6B7280),
                              fontWeight:
                                  selected ? FontWeight.w700 : FontWeight.w600,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 8),
                  itemCount: legendDays.length,
                ),
              ),
            ],
            const SizedBox(height: 18),
            Text(
              'Rendez-vous du jour',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: _titleNavy,
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 10),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              _ErrorCard(error: _error!, onRetry: _load)
            else if (_slots.isEmpty)
              const _EmptyCard(
                icon: Icons.event_busy_rounded,
                title: 'Aucun rendez-vous planifié',
                subtitle:
                    'Dès qu’un médecin fixe une téléconsultation, elle apparaîtra ici.',
              )
            else if (_slotsSelectedDay.isEmpty)
              const _EmptyCard(
                icon: Icons.calendar_view_day_rounded,
                title: 'Aucun rendez-vous ce jour',
                subtitle:
                    'Sélectionnez une autre date pour voir les téléconsultations planifiées.',
              )
            else
              ..._slotsSelectedDay.asMap().entries.map((entry) {
                final idx = entry.key;
                final slot = entry.value;
                final d = _slotLocal(slot);
                final doctor = readableDoctorName(slot['doctorName'] as String?);
                final text = (slot['content'] as String?) ?? '';
                if (d == null) return const SizedBox.shrink();
                final style = _styleForSlot(slot, d);
                return _TimelineAppointmentTile(
                  timeLabel: _fmtTime(d),
                  doctorName: doctor,
                  doctorPhotoPath: slot['doctorPhotoPath']?.toString(),
                  message: text,
                  statusLabel: style.label,
                  statusBg: style.chipBg,
                  statusText: style.chipText,
                  accent: style.accent,
                  isLast: idx == _slotsSelectedDay.length - 1,
                );
              }),
            if (!_loading && _error == null && _slots.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Jours avec rendez-vous: ${perDayCount.length}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF9CA3AF),
                    ),
              ),
            ],
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

class _AppointmentStyle {
  const _AppointmentStyle({
    required this.label,
    required this.chipBg,
    required this.chipText,
    required this.accent,
  });

  final String label;
  final Color chipBg;
  final Color chipText;
  final Color accent;
}

class _TimelineAppointmentTile extends StatelessWidget {
  const _TimelineAppointmentTile({
    required this.timeLabel,
    required this.doctorName,
    this.doctorPhotoPath,
    required this.message,
    required this.statusLabel,
    required this.statusBg,
    required this.statusText,
    required this.accent,
    required this.isLast,
  });

  final String timeLabel;
  final String doctorName;
  final String? doctorPhotoPath;
  final String message;
  final String statusLabel;
  final Color statusBg;
  final Color statusText;
  final Color accent;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Column(
              children: [
                Text(
                  timeLabel,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 7),
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.35),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
                if (!isLast)
                  Container(
                    width: 2,
                    height: 78,
                    margin: const EdgeInsets.only(top: 4),
                    color: const Color(0xFFE2E8F0),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.videocam_rounded,
                        size: 18,
                        color: Color(0xFF4FA8D5),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Téléconsultation',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF0F172A),
                              ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: statusBg,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          statusLabel,
                          style: TextStyle(
                            color: statusText,
                            fontWeight: FontWeight.w700,
                            fontSize: 11.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      doctorAvatarForPatient(
                        name: doctorName,
                        doctorPhotoPath: doctorPhotoPath,
                        radius: 18,
                        backgroundColor: const Color(0xFFE8F6FC),
                        accentColor: const Color(0xFF4FA8D5),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Médecin: $doctorName',
                          style: const TextStyle(
                            color: Color(0xFF334155),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (message.trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      message,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.icon,
    required this.text,
    required this.color,
    this.backgroundColor,
    this.bordered = true,
  });

  final IconData icon;
  final String text;
  final Color color;
  final Color? backgroundColor;
  final bool bordered;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: backgroundColor ?? color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: bordered
            ? Border.all(color: color.withValues(alpha: 0.28))
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.error, required this.onRetry});

  final String error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFED7AA)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Impossible de charger les rendez-vous',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: Color(0xFF9A3412),
            ),
          ),
          const SizedBox(height: 6),
          Text(error, style: const TextStyle(color: Color(0xFF9A3412))),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: onRetry,
            child: const Text('Réessayer'),
          ),
        ],
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Icon(icon, size: 28, color: const Color(0xFF9CA3AF)),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: Color(0xFF1A458B),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF6B7280),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

