import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../headsapp_theme.dart';
import '../models/doctor_blood_pressure_alert.dart';
import '../models/doctor_blood_pressure_measurement.dart';
import '../models/doctor_patient_brief.dart';
import '../providers/doctor_blood_pressure_provider.dart';

const Color _screenBg = Color(0xFFF5F9FC);
const Color _headerBlue = Color(0xFF2459A8);

class DoctorBloodPressureScreen extends StatefulWidget {
  const DoctorBloodPressureScreen({
    super.key,
    required this.doctorId,
  });

  final String doctorId;

  @override
  State<DoctorBloodPressureScreen> createState() => _DoctorBloodPressureScreenState();
}

class _DoctorBloodPressureScreenState extends State<DoctorBloodPressureScreen> {
  late final DoctorBloodPressureProvider _provider;

  @override
  void initState() {
    super.initState();
    _provider = DoctorBloodPressureProvider(doctorId: widget.doctorId);
    _provider.initialize();
  }

  @override
  void dispose() {
    _provider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _provider,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: _screenBg,
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _HeadsAppBackHeader(title: 'Tensiomètre connecté'),
                Expanded(
                  child: _provider.loading
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: HeadsAppColors.brandPrimary,
                          ),
                        )
                      : RefreshIndicator(
                          color: HeadsAppColors.brandPrimary,
                          onRefresh: _provider.refresh,
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                            children: [
                              _HubCard(
                                title: 'Historiques',
                                subtitle:
                                    'Patients, mesures individuelles et graphe d’évolution',
                                icon: Icons.history_rounded,
                                accentColor: HeadsAppColors.brandPrimary,
                                gradientColors: const [
                                  Color(0xFFF4F8FD),
                                  Color(0xFFEEF6FF),
                                ],
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => _DoctorHistoriesPage(
                                        provider: _provider,
                                      ),
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 14),
                              _HubCard(
                                title: 'Alertes',
                                subtitle:
                                    'Alertes patients avec filtrage nom, prénom et date',
                                icon: Icons.warning_amber_rounded,
                                accentColor: HeadsAppColors.warning,
                                gradientColors: const [
                                  Color(0xFFFFFBF5),
                                  Color(0xFFFFF4E8),
                                ],
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => _DoctorAlertsPage(
                                        provider: _provider,
                                      ),
                                    ),
                                  );
                                },
                              ),
                              if (_provider.error != null) ...[
                                const SizedBox(height: 14),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: HeadsAppColors.surface,
                                    borderRadius: BorderRadius.circular(
                                      HeadsAppMetrics.compactRadius,
                                    ),
                                    border: Border.all(
                                      color: HeadsAppColors.warning
                                          .withValues(alpha: 0.35),
                                    ),
                                  ),
                                  child: Text(
                                    _provider.error!,
                                    style: const TextStyle(
                                      color: HeadsAppColors.warning,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
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
      },
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
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: _headerBlue,
                letterSpacing: -0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HubCard extends StatefulWidget {
  const _HubCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
    required this.gradientColors,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accentColor;
  final List<Color> gradientColors;
  final VoidCallback onTap;

  @override
  State<_HubCard> createState() => _HubCardState();
}

class _HubCardState extends State<_HubCard> {
  bool _hovered = false;
  bool _pressed = false;

  bool get _active => _hovered || _pressed;

  @override
  Widget build(BuildContext context) {
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
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          height: 118,
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: widget.gradientColors,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: widget.accentColor.withValues(alpha: _active ? 0.28 : 0.14),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: _active ? 0.1 : 0.05),
                blurRadius: _active ? 18 : 10,
                offset: Offset(0, _active ? 8 : 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: HeadsAppColors.brandHighlight,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(widget.icon, size: 24, color: widget.accentColor),
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
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: HeadsAppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.3,
                        color: HeadsAppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_rounded,
                color: widget.accentColor,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DoctorHistoriesPage extends StatefulWidget {
  const _DoctorHistoriesPage({required this.provider});
  final DoctorBloodPressureProvider provider;

  @override
  State<_DoctorHistoriesPage> createState() => _DoctorHistoriesPageState();
}

class _DoctorHistoriesPageState extends State<_DoctorHistoriesPage> {
  final TextEditingController _nomCtrl = TextEditingController();
  final TextEditingController _prenomCtrl = TextEditingController();
  DateTime? _dateFilter;

  @override
  void dispose() {
    _nomCtrl.dispose();
    _prenomCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('dd/MM/yyyy');
    return Scaffold(
      backgroundColor: _screenBg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _HeadsAppBackHeader(title: 'Historiques des patients'),
            Expanded(
              child: AnimatedBuilder(
                animation: widget.provider,
                builder: (context, _) {
                  final patients = widget.provider.patients.where((p) {
                    final nom = p.lastName.toLowerCase();
                    final prenom = p.firstName.toLowerCase();
                    final nomQuery = _nomCtrl.text.trim().toLowerCase();
                    final prenomQuery = _prenomCtrl.text.trim().toLowerCase();
                    final nomOk = nomQuery.isEmpty || nom.contains(nomQuery);
                    final prenomOk =
                        prenomQuery.isEmpty || prenom.contains(prenomQuery);
                    final date = _dateFilter;
                    final dateOk = date == null ||
                        widget.provider.measurements.any((m) {
                          if (m.patientId != p.id) return false;
                          return m.measuredAt.year == date.year &&
                              m.measuredAt.month == date.month &&
                              m.measuredAt.day == date.day;
                        });
                    return nomOk && prenomOk && dateOk;
                  }).toList();

                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                    children: [
                      const _SectionHeader(
                        icon: Icons.history_rounded,
                        title: 'Historiques',
                        subtitle:
                            'Consultez les patients et leurs mesures tensionnelles.',
                      ),
                      const SizedBox(height: 12),
                      _FilterByNameDateCard(
                        nomCtrl: _nomCtrl,
                        prenomCtrl: _prenomCtrl,
                        dateFilter: _dateFilter,
                        dateFmt: dateFmt,
                        onChanged: () => setState(() {}),
                        onPickDate: () async {
                          final now = DateTime.now();
                          final picked = await showDatePicker(
                            context: context,
                            firstDate: DateTime(now.year - 2),
                            lastDate: now,
                            initialDate: _dateFilter ?? now,
                          );
                          if (picked != null && mounted) {
                            setState(() => _dateFilter = picked);
                          }
                        },
                        onReset: () {
                          _nomCtrl.clear();
                          _prenomCtrl.clear();
                          setState(() => _dateFilter = null);
                        },
                      ),
                      const SizedBox(height: 12),
                      if (patients.isEmpty)
                        const _EmptyLine(text: 'Aucun patient trouvé.')
                      else
                        ...patients.map(
                          (p) => _SurfaceListTile(
                            leading: Icon(
                              Icons.person_rounded,
                              color: HeadsAppColors.brandPrimary,
                            ),
                            title: p.name,
                            subtitle:
                                'Prénom: ${p.firstName} • Nom: ${p.lastName}',
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => _PatientMeasurementsPage(
                                    provider: widget.provider,
                                    patient: p,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DoctorAlertsPage extends StatefulWidget {
  const _DoctorAlertsPage({required this.provider});
  final DoctorBloodPressureProvider provider;

  @override
  State<_DoctorAlertsPage> createState() => _DoctorAlertsPageState();
}

class _DoctorAlertsPageState extends State<_DoctorAlertsPage> {
  final TextEditingController _nomCtrl = TextEditingController();
  final TextEditingController _prenomCtrl = TextEditingController();
  DateTime? _dateFilter;

  @override
  void dispose() {
    _nomCtrl.dispose();
    _prenomCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('dd/MM/yyyy');
    final dateTimeFmt = DateFormat('dd/MM/yyyy • HH:mm');
    return Scaffold(
      backgroundColor: _screenBg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _HeadsAppBackHeader(title: 'Alertes des patients'),
            Expanded(
              child: AnimatedBuilder(
                animation: widget.provider,
                builder: (context, _) {
                  final filtered = widget.provider.alerts.where((a) {
                    final parts = a.patientName
                        .trim()
                        .split(RegExp(r'\s+'))
                        .where((p) => p.isNotEmpty)
                        .toList();
                    final firstName =
                        parts.isEmpty ? '' : parts.first.toLowerCase();
                    final lastName = parts.length <= 1
                        ? ''
                        : parts.sublist(1).join(' ').toLowerCase();
                    final nomQuery = _nomCtrl.text.trim().toLowerCase();
                    final prenomQuery = _prenomCtrl.text.trim().toLowerCase();
                    final nomOk = nomQuery.isEmpty || lastName.contains(nomQuery);
                    final prenomOk =
                        prenomQuery.isEmpty || firstName.contains(prenomQuery);
                    final date = _dateFilter;
                    final dateOk = date == null ||
                        (a.createdAt.year == date.year &&
                            a.createdAt.month == date.month &&
                            a.createdAt.day == date.day);
                    return nomOk && prenomOk && dateOk;
                  }).toList();

                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                    children: [
                      const _SectionHeader(
                        icon: Icons.warning_amber_rounded,
                        title: 'Alertes',
                        subtitle:
                            'Surveillez les alertes critiques par patient.',
                      ),
                      const SizedBox(height: 12),
                      _FilterByNameDateCard(
                        nomCtrl: _nomCtrl,
                        prenomCtrl: _prenomCtrl,
                        dateFilter: _dateFilter,
                        dateFmt: dateFmt,
                        onChanged: () => setState(() {}),
                        onPickDate: () async {
                          final now = DateTime.now();
                          final picked = await showDatePicker(
                            context: context,
                            firstDate: DateTime(now.year - 2),
                            lastDate: now,
                            initialDate: _dateFilter ?? now,
                          );
                          if (picked != null && mounted) {
                            setState(() => _dateFilter = picked);
                          }
                        },
                        onReset: () {
                          _nomCtrl.clear();
                          _prenomCtrl.clear();
                          setState(() => _dateFilter = null);
                        },
                      ),
                      const SizedBox(height: 12),
                      if (filtered.isEmpty)
                        const _EmptyLine(text: 'Aucune alerte trouvée.')
                      else
                        ...filtered.map(
                          (a) => _AlertTile(
                            alert: a,
                            dateTimeFmt: dateTimeFmt,
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PatientMeasurementsPage extends StatefulWidget {
  const _PatientMeasurementsPage({
    required this.provider,
    required this.patient,
  });

  final DoctorBloodPressureProvider provider;
  final DoctorPatientBrief patient;

  @override
  State<_PatientMeasurementsPage> createState() =>
      _PatientMeasurementsPageState();
}

class _PatientMeasurementsPageState extends State<_PatientMeasurementsPage> {
  bool _showGraph = false;

  @override
  Widget build(BuildContext context) {
    final dateTimeFmt = DateFormat('dd/MM/yyyy • HH:mm');
    final patientMeasures = widget.provider.measurements
        .where((m) => m.patientId == widget.patient.id)
        .toList()
      ..sort((a, b) => b.measuredAt.compareTo(a.measuredAt));

    return Scaffold(
      backgroundColor: _screenBg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _HeadsAppBackHeader(title: 'Mesures • ${widget.patient.name}'),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => setState(() => _showGraph = !_showGraph),
                  icon: Icon(
                    _showGraph
                        ? Icons.view_list_rounded
                        : Icons.show_chart_rounded,
                    size: 18,
                  ),
                  label: Text(_showGraph ? 'Liste' : 'Graphe'),
                  style: TextButton.styleFrom(
                    foregroundColor: HeadsAppColors.brandPrimary,
                    textStyle: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                children: [
                  const _SectionHeader(
                    icon: Icons.monitor_heart_outlined,
                    title: 'Mesures individuelles',
                    subtitle:
                        'Basculer entre liste et graphe via le bouton en haut.',
                  ),
                  const SizedBox(height: 12),
                  if (_showGraph)
                    _EvolutionChartCard(measurements: patientMeasures)
                  else if (patientMeasures.isEmpty)
                    const _EmptyLine(text: 'Aucune mesure pour ce patient.')
                  else
                    ...patientMeasures.map(
                      (m) => _MeasurementTile(
                        measurement: m,
                        dateTimeFmt: dateTimeFmt,
                      ),
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

class _FilterByNameDateCard extends StatelessWidget {
  const _FilterByNameDateCard({
    required this.nomCtrl,
    required this.prenomCtrl,
    required this.dateFilter,
    required this.dateFmt,
    required this.onChanged,
    required this.onPickDate,
    required this.onReset,
  });

  final TextEditingController nomCtrl;
  final TextEditingController prenomCtrl;
  final DateTime? dateFilter;
  final DateFormat dateFmt;
  final VoidCallback onChanged;
  final VoidCallback onPickDate;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.of(context).size.width < 420;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: HeadsAppColors.surface,
        borderRadius: BorderRadius.circular(HeadsAppMetrics.compactRadius),
        border: Border.all(color: HeadsAppColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: HeadsAppColors.brandHighlight,
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.tune_rounded,
                  size: 14,
                  color: HeadsAppColors.brandPrimary,
                ),
                SizedBox(width: 6),
                Text(
                  'Filtres',
                  style: TextStyle(
                    color: HeadsAppColors.brandPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          isCompact
              ? Column(
                  children: [
                    _FilterField(
                      controller: nomCtrl,
                      label: 'Filtre Nom',
                      icon: Icons.badge_outlined,
                      onChanged: onChanged,
                    ),
                    const SizedBox(height: 8),
                    _FilterField(
                      controller: prenomCtrl,
                      label: 'Filtre Prénom',
                      icon: Icons.person_outline_rounded,
                      onChanged: onChanged,
                    ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(
                      child: _FilterField(
                        controller: nomCtrl,
                        label: 'Filtre Nom',
                        icon: Icons.badge_outlined,
                        onChanged: onChanged,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _FilterField(
                        controller: prenomCtrl,
                        label: 'Filtre Prénom',
                        icon: Icons.person_outline_rounded,
                        onChanged: onChanged,
                      ),
                    ),
                  ],
                ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: onPickDate,
                icon: const Icon(Icons.date_range_rounded, size: 18),
                label: Text(
                  dateFilter == null
                      ? 'Filtrer par date'
                      : dateFmt.format(dateFilter!),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: HeadsAppColors.brandPrimary,
                  side: const BorderSide(color: HeadsAppColors.border),
                  backgroundColor: HeadsAppColors.surfaceMuted,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: onReset,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Réinitialiser'),
                style: TextButton.styleFrom(
                  foregroundColor: HeadsAppColors.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FilterField extends StatelessWidget {
  const _FilterField({
    required this.controller,
    required this.label,
    required this.icon,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: (_) => onChanged(),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: HeadsAppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: HeadsAppColors.brandPrimary,
            width: 1.4,
          ),
        ),
        isDense: true,
        filled: true,
        fillColor: const Color(0xFFF2F4F7),
      ),
    );
  }
}

class _SurfaceListTile extends StatelessWidget {
  const _SurfaceListTile({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  final Widget leading;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: HeadsAppColors.surface,
        borderRadius: BorderRadius.circular(HeadsAppMetrics.compactRadius),
        border: Border.all(color: HeadsAppColors.border),
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(HeadsAppMetrics.compactRadius),
        ),
        leading: leading,
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: HeadsAppColors.textPrimary,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(color: HeadsAppColors.textSecondary),
        ),
        trailing: trailing,
        onTap: onTap,
      ),
    );
  }
}

class _MeasurementTile extends StatelessWidget {
  const _MeasurementTile({
    required this.measurement,
    required this.dateTimeFmt,
  });

  final DoctorBloodPressureMeasurement measurement;
  final DateFormat dateTimeFmt;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: HeadsAppColors.surface,
        borderRadius: BorderRadius.circular(HeadsAppMetrics.compactRadius),
        border: Border.all(color: HeadsAppColors.border),
      ),
      child: ListTile(
        leading: const Icon(
          Icons.monitor_heart_outlined,
          color: HeadsAppColors.brandPrimary,
        ),
        title: Text(
          measurement.patientName,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: HeadsAppColors.textPrimary,
          ),
        ),
        subtitle: Text(
          '${dateTimeFmt.format(measurement.measuredAt)}\nPAS ${measurement.systolic} / PAD ${measurement.diastolic}'
          '${measurement.heartRate != null ? ' • FC ${measurement.heartRate}' : ''}',
          style: const TextStyle(color: HeadsAppColors.textSecondary),
        ),
        isThreeLine: true,
      ),
    );
  }
}

class _AlertTile extends StatelessWidget {
  const _AlertTile({
    required this.alert,
    required this.dateTimeFmt,
  });

  final DoctorBloodPressureAlert alert;
  final DateFormat dateTimeFmt;

  @override
  Widget build(BuildContext context) {
    final color =
        alert.isHypertension ? HeadsAppColors.danger : HeadsAppColors.warning;
    final label = alert.isHypertension ? 'Hypertension' : 'Hypotension';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: HeadsAppColors.surface,
        borderRadius: BorderRadius.circular(HeadsAppMetrics.compactRadius),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: ListTile(
        leading: Icon(Icons.warning_amber_rounded, color: color),
        title: Row(
          children: [
            Expanded(
              child: Text(
                '${alert.patientName} • ${alert.type}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: HeadsAppColors.textPrimary,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
          ],
        ),
        subtitle: Text(
          'PAS ${alert.systolic} / PAD ${alert.diastolic}\n${dateTimeFmt.format(alert.createdAt)}',
          style: const TextStyle(color: HeadsAppColors.textSecondary),
        ),
        isThreeLine: true,
      ),
    );
  }
}

class _EvolutionChartCard extends StatelessWidget {
  const _EvolutionChartCard({required this.measurements});

  final List<DoctorBloodPressureMeasurement> measurements;

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.of(context).size.width < 380;
    if (measurements.isEmpty) {
      return const _EmptyLine(
        text: 'Pas assez de données pour afficher la courbe.',
      );
    }

    final points = measurements.reversed.toList();
    final systolicSpots = <FlSpot>[];
    final diastolicSpots = <FlSpot>[];
    for (var i = 0; i < points.length; i++) {
      systolicSpots.add(FlSpot(i.toDouble(), points[i].systolic.toDouble()));
      diastolicSpots.add(FlSpot(i.toDouble(), points[i].diastolic.toDouble()));
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: HeadsAppColors.surface,
        borderRadius: BorderRadius.circular(HeadsAppMetrics.compactRadius),
        border: Border.all(color: HeadsAppColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: SizedBox(
        height: isCompact ? 210 : 240,
        child: LineChart(
          LineChartData(
            minY: 40,
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              getDrawingHorizontalLine: (value) => FlLine(
                color: HeadsAppColors.border.withValues(alpha: 0.8),
                strokeWidth: 1,
              ),
            ),
            titlesData: FlTitlesData(
              rightTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  interval: points.length > 8 ? 2 : 1,
                  getTitlesWidget: (value, meta) {
                    final i = value.toInt();
                    if (i < 0 || i >= points.length) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        DateFormat('dd/MM').format(points[i].measuredAt),
                        style: const TextStyle(
                          fontSize: 10,
                          color: HeadsAppColors.textSecondary,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            borderData: FlBorderData(
              show: true,
              border: Border.all(color: HeadsAppColors.border),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: systolicSpots,
                color: HeadsAppColors.danger,
                barWidth: 2.5,
                dotData: const FlDotData(show: false),
              ),
              LineChartBarData(
                spots: diastolicSpots,
                color: HeadsAppColors.brandPrimary,
                barWidth: 2.5,
                dotData: const FlDotData(show: false),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: HeadsAppColors.surface,
        borderRadius: BorderRadius.circular(HeadsAppMetrics.compactRadius),
        border: Border.all(color: HeadsAppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: HeadsAppColors.brandHighlight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: HeadsAppColors.brandPrimary, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: HeadsAppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: HeadsAppColors.textSecondary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyLine extends StatelessWidget {
  const _EmptyLine({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: HeadsAppColors.surface,
        borderRadius: BorderRadius.circular(HeadsAppMetrics.compactRadius),
        border: Border.all(color: HeadsAppColors.border),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: HeadsAppColors.textSecondary,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
