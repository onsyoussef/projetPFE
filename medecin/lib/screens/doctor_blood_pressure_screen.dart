import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../headsapp_theme.dart';
import '../models/doctor_blood_pressure_alert.dart';
import '../models/doctor_blood_pressure_measurement.dart';
import '../models/doctor_patient_brief.dart';
import '../providers/doctor_blood_pressure_provider.dart';

const Color _bpPrimary = HeadsAppColors.brandPrimary;
const Color _bpSurface = HeadsAppColors.surfaceAlt;
const Color _bpText = HeadsAppColors.textPrimary;

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
          backgroundColor: _bpSurface,
          appBar: AppBar(
            title: const Text('Tensiomètre connecté'),
          ),
          body: _provider.loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _provider.refresh,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _HubCard(
                        title: 'Historiques',
                        subtitle: 'Patients, mesures individuelles et graphe d’évolution',
                        icon: Icons.history_rounded,
                        color: const Color(0xFF2563EB),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => _DoctorHistoriesPage(provider: _provider),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      _HubCard(
                        title: 'Alertes',
                        subtitle: 'Alertes patients avec filtrage nom, prénom et date',
                        icon: Icons.warning_amber_rounded,
                        color: const Color(0xFFF97316),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => _DoctorAlertsPage(provider: _provider),
                            ),
                          );
                        },
                      ),
                      if (_provider.error != null) ...[
                        const SizedBox(height: 14),
                        Text(
                          _provider.error!,
                          style: const TextStyle(color: HeadsAppColors.warning, fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ),
        );
      },
    );
  }
}

class _HubCard extends StatefulWidget {
  const _HubCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  State<_HubCard> createState() => _HubCardState();
}

class _HubCardState extends State<_HubCard> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.of(context).size.width < 380;
    final scale = _pressed ? 0.98 : (_hovered ? 1.02 : 1.0);
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
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          transform: Matrix4.diagonal3Values(scale, scale, 1),
          height: isCompact ? 116 : 132,
          width: double.infinity,
          padding: EdgeInsets.all(isCompact ? 12 : 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.white, widget.color.withValues(alpha: _hovered ? 0.16 : 0.10)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: widget.color.withValues(alpha: 0.26)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: _hovered ? 0.12 : 0.08),
                blurRadius: _hovered ? 18 : 10,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: isCompact ? 42 : 48,
                height: isCompact ? 42 : 48,
                decoration: BoxDecoration(
                  color: widget.color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(widget.icon, color: widget.color, size: isCompact ? 20 : 24),
              ),
              SizedBox(width: isCompact ? 10 : 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: HeadsAppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.subtitle,
                      maxLines: isCompact ? 2 : 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: isCompact ? 12 : 13,
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
      backgroundColor: _bpSurface,
      appBar: AppBar(
        title: const Text('Historiques des patients'),
        backgroundColor: _bpPrimary,
        foregroundColor: Colors.white,
      ),
      body: AnimatedBuilder(
        animation: widget.provider,
        builder: (context, _) {
          final patients = widget.provider.patients.where((p) {
            final nom = p.lastName.toLowerCase();
            final prenom = p.firstName.toLowerCase();
            final nomQuery = _nomCtrl.text.trim().toLowerCase();
            final prenomQuery = _prenomCtrl.text.trim().toLowerCase();
            final nomOk = nomQuery.isEmpty || nom.contains(nomQuery);
            final prenomOk = prenomQuery.isEmpty || prenom.contains(prenomQuery);
            final date = _dateFilter;
            final dateOk = date == null || widget.provider.measurements.any((m) {
              if (m.patientId != p.id) return false;
              return m.measuredAt.year == date.year &&
                  m.measuredAt.month == date.month &&
                  m.measuredAt.day == date.day;
            });
            return nomOk && prenomOk && dateOk;
          }).toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const _SectionHeader(
                icon: Icons.history_rounded,
                title: 'Historiques',
                subtitle: 'Consultez les patients et leurs mesures tensionnelles.',
              ),
              const SizedBox(height: 10),
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
                  if (picked != null && mounted) setState(() => _dateFilter = picked);
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
                  (p) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0.8,
                    child: ListTile(
                      leading: const Icon(Icons.person_rounded, color: Color(0xFF4FA8D5)),
                      title: Text(p.name),
                      subtitle: Text('Prénom: ${p.firstName} • Nom: ${p.lastName}'),
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
                ),
            ],
          );
        },
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
      backgroundColor: _bpSurface,
      appBar: AppBar(
        title: const Text('Alertes des patients'),
        backgroundColor: _bpPrimary,
        foregroundColor: Colors.white,
      ),
      body: AnimatedBuilder(
        animation: widget.provider,
        builder: (context, _) {
          final filtered = widget.provider.alerts.where((a) {
            final parts = a.patientName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
            final firstName = parts.isEmpty ? '' : parts.first.toLowerCase();
            final lastName = parts.length <= 1 ? '' : parts.sublist(1).join(' ').toLowerCase();
            final nomQuery = _nomCtrl.text.trim().toLowerCase();
            final prenomQuery = _prenomCtrl.text.trim().toLowerCase();
            final nomOk = nomQuery.isEmpty || lastName.contains(nomQuery);
            final prenomOk = prenomQuery.isEmpty || firstName.contains(prenomQuery);
            final date = _dateFilter;
            final dateOk = date == null ||
                (a.createdAt.year == date.year &&
                    a.createdAt.month == date.month &&
                    a.createdAt.day == date.day);
            return nomOk && prenomOk && dateOk;
          }).toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const _SectionHeader(
                icon: Icons.warning_amber_rounded,
                title: 'Alertes',
                subtitle: 'Surveillez les alertes critiques par patient.',
              ),
              const SizedBox(height: 10),
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
                  if (picked != null && mounted) setState(() => _dateFilter = picked);
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
                ...filtered.map((a) => _AlertTile(alert: a, dateTimeFmt: dateTimeFmt)),
            ],
          );
        },
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
  State<_PatientMeasurementsPage> createState() => _PatientMeasurementsPageState();
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
      backgroundColor: _bpSurface,
      appBar: AppBar(
        title: Text('Mesures • ${widget.patient.name}'),
        backgroundColor: _bpPrimary,
        foregroundColor: Colors.white,
        actions: [
          TextButton.icon(
            onPressed: () => setState(() => _showGraph = !_showGraph),
            icon: const Icon(Icons.show_chart_rounded, color: Colors.white),
            label: Text(
              _showGraph ? 'Liste' : 'Graphe',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _SectionHeader(
            icon: Icons.monitor_heart_rounded,
            title: 'Mesures individuelles',
            subtitle: 'Basculer entre liste et graphe via le bouton en haut.',
          ),
          const SizedBox(height: 10),
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
    const borderColor = Color(0xFFD2E4F0);
    const inputBorderColor = Color(0xFFB8CEDD);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFCFEFF), Color(0xFFF2F8FC)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _bpPrimary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.tune_rounded, size: 14, color: _bpPrimary),
                SizedBox(width: 6),
                Text(
                  'Filtres',
                  style: TextStyle(
                    color: _bpPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          isCompact
              ? Column(
                  children: [
                    TextField(
                      controller: nomCtrl,
                      onChanged: (_) => onChanged(),
                      decoration: InputDecoration(
                        labelText: 'Filtre Nom',
                        prefixIcon: const Icon(Icons.badge_outlined, size: 20),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: inputBorderColor),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: _bpPrimary, width: 1.4),
                        ),
                        isDense: true,
                        filled: true,
                        fillColor: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: prenomCtrl,
                      onChanged: (_) => onChanged(),
                      decoration: InputDecoration(
                        labelText: 'Filtre Prénom',
                        prefixIcon: const Icon(Icons.person_outline_rounded, size: 20),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: inputBorderColor),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: _bpPrimary, width: 1.4),
                        ),
                        isDense: true,
                        filled: true,
                        fillColor: Colors.white,
                      ),
                    ),
                  ],
                )
              : Row(
            children: [
              Expanded(
                child: TextField(
                  controller: nomCtrl,
                  onChanged: (_) => onChanged(),
                  decoration: InputDecoration(
                    labelText: 'Filtre Nom',
                    prefixIcon: const Icon(Icons.badge_outlined, size: 20),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: inputBorderColor),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: _bpPrimary, width: 1.4),
                    ),
                    isDense: true,
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: prenomCtrl,
                  onChanged: (_) => onChanged(),
                  decoration: InputDecoration(
                    labelText: 'Filtre Prénom',
                    prefixIcon: const Icon(Icons.person_outline_rounded, size: 20),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: inputBorderColor),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: _bpPrimary, width: 1.4),
                    ),
                    isDense: true,
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: onPickDate,
                icon: const Icon(Icons.date_range_rounded),
                label: Text(
                  dateFilter == null ? 'Filtrer par date' : dateFmt.format(dateFilter!),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF0B6990),
                  side: const BorderSide(color: Color(0xFFA7C9DC)),
                  backgroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
              ),
              TextButton.icon(
                onPressed: onReset,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Réinitialiser'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF0B6990),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
              ),
            ],
          ),
        ],
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
    final isCompact = MediaQuery.of(context).size.width < 380;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 0.8,
      child: ListTile(
        contentPadding: EdgeInsets.symmetric(
          horizontal: isCompact ? 12 : 16,
          vertical: isCompact ? 4 : 6,
        ),
        leading: Icon(
          Icons.monitor_heart_rounded,
          color: const Color(0xFF4FA8D5),
          size: isCompact ? 21 : 24,
        ),
        title: Text(
          measurement.patientName,
          style: TextStyle(fontSize: isCompact ? 14 : 15, fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          '${dateTimeFmt.format(measurement.measuredAt)}\nPAS ${measurement.systolic} / PAD ${measurement.diastolic}'
          '${measurement.heartRate != null ? ' • FC ${measurement.heartRate}' : ''}',
          style: TextStyle(fontSize: isCompact ? 12 : 13),
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
    final isCompact = MediaQuery.of(context).size.width < 380;
    final color = alert.isHypertension ? const Color(0xFFDC2626) : const Color(0xFFF59E0B);
    final label = alert.isHypertension ? 'Hypertension' : 'Hypotension';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 0.8,
      child: ListTile(
        contentPadding: EdgeInsets.symmetric(
          horizontal: isCompact ? 12 : 16,
          vertical: isCompact ? 4 : 6,
        ),
        leading: Icon(Icons.warning_amber_rounded, color: color, size: isCompact ? 21 : 24),
        title: Row(
          children: [
            Expanded(
              child: Text(
                '${alert.patientName} • ${alert.type}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: isCompact ? 14 : 15, fontWeight: FontWeight.w700),
              ),
            ),
            Container(
              padding: EdgeInsets.symmetric(horizontal: isCompact ? 7 : 8, vertical: 4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: isCompact ? 10 : 11,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
          ],
        ),
        subtitle: Text(
          'PAS ${alert.systolic} / PAD ${alert.diastolic}\n${dateTimeFmt.format(alert.createdAt)}',
          style: TextStyle(fontSize: isCompact ? 12 : 13),
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
      return const _EmptyLine(text: 'Pas assez de données pour afficher la courbe.');
    }

    final points = measurements.reversed.toList();
    final systolicSpots = <FlSpot>[];
    final diastolicSpots = <FlSpot>[];
    for (var i = 0; i < points.length; i++) {
      systolicSpots.add(FlSpot(i.toDouble(), points[i].systolic.toDouble()));
      diastolicSpots.add(FlSpot(i.toDouble(), points[i].diastolic.toDouble()));
    }

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 0.8,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          height: isCompact ? 210 : 240,
          child: LineChart(
            LineChartData(
              minY: 40,
              gridData: FlGridData(show: true, drawVerticalLine: false),
              titlesData: FlTitlesData(
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: points.length > 8 ? 2 : 1,
                    getTitlesWidget: (value, meta) {
                      final i = value.toInt();
                      if (i < 0 || i >= points.length) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          DateFormat('dd/MM').format(points[i].measuredAt),
                          style: TextStyle(fontSize: isCompact ? 9 : 10),
                        ),
                      );
                    },
                  ),
                ),
              ),
              borderData: FlBorderData(
                show: true,
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: systolicSpots,
                  color: const Color(0xFFDC2626),
                  barWidth: 2.5,
                  dotData: const FlDotData(show: false),
                ),
                LineChartBarData(
                  spots: diastolicSpots,
                  color: const Color(0xFF2563EB),
                  barWidth: 2.5,
                  dotData: const FlDotData(show: false),
                ),
              ],
            ),
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
    final isCompact = MediaQuery.of(context).size.width < 380;
    return Container(
      padding: EdgeInsets.all(isCompact ? 12 : 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE0F2FE), Color(0xFFF8FCFF)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Row(
        children: [
          Container(
            width: isCompact ? 36 : 40,
            height: isCompact ? 36 : 40,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: _bpPrimary, size: isCompact ? 19 : 22),
          ),
          SizedBox(width: isCompact ? 8 : 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: isCompact ? 15 : 16,
                    color: _bpText,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: isCompact ? 11 : 12,
                    color: const Color(0xFF475569),
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Text(text),
    );
  }
}
