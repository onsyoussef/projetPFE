import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/blood_pressure_alert.dart';
import '../models/blood_pressure_measurement.dart';
import '../providers/blood_pressure_provider.dart';
import '../utils/patient_ui_utils.dart';

const Color _bpPrimary = Color(0xFF4FA8D5);

class BloodPressureScreen extends StatefulWidget {
  const BloodPressureScreen({
    super.key,
    required this.patientId,
    required this.patientName,
  });

  final String patientId;
  final String patientName;

  @override
  State<BloodPressureScreen> createState() => _BloodPressureScreenState();
}

class _BloodPressureScreenState extends State<BloodPressureScreen> {
  late final BloodPressureProvider _provider;

  @override
  void initState() {
    super.initState();
    _provider = BloodPressureProvider(patientId: widget.patientId);
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
          appBar: AppBar(
            title: const Text('Tensiomètre connecté'),
            backgroundColor: const Color(0xFF4FA8D5),
            foregroundColor: Colors.white,
          ),
          body: _provider.loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _provider.refresh,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _HubHeader(
                        patientName: widget.patientName,
                        deviceConnected: _provider.deviceConnected,
                      ),
                      const SizedBox(height: 14),
                      _InteractiveHubCard(
                        title: 'Mesure en temps réel',
                        subtitle: 'Consulter PAS/PAD/FC et l\'interprétation instantanée',
                        icon: Icons.monitor_heart_rounded,
                        accent: const Color(0xFF0EA5E9),
                        badgeText: _provider.deviceConnected ? 'Connecté' : 'Non connecté',
                        badgeColor: _provider.deviceConnected
                            ? const Color(0xFF16A34A)
                            : const Color(0xFFDC2626),
                        enabled: _provider.deviceConnected,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => _BloodPressureLivePage(provider: _provider),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      _InteractiveHubCard(
                        title: 'Historique',
                        subtitle: 'Voir et filtrer les mesures précédentes',
                        icon: Icons.history_rounded,
                        accent: const Color(0xFF4F46E5),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => _BloodPressureHistoryPage(provider: _provider),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      _InteractiveHubCard(
                        title: 'Alertes',
                        subtitle: 'Suivre les alertes tensionnelles récentes',
                        icon: Icons.warning_amber_rounded,
                        accent: const Color(0xFFF97316),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => _BloodPressureAlertsPage(provider: _provider),
                            ),
                          );
                        },
                      ),
                      if (_provider.error != null) ...[
                        const SizedBox(height: 14),
                        Text(
                          _provider.error!,
                          style: const TextStyle(
                            color: Color(0xFFB45309),
                            fontSize: 12,
                          ),
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

class _HubHeader extends StatelessWidget {
  const _HubHeader({required this.patientName, required this.deviceConnected});

  final String patientName;
  final bool deviceConnected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          colors: [Color(0xFFE0F2FE), Color(0xFFF8FAFC)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: const Color(0xFFBAE6FD)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Suivi tensionnel',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
          ),
          const SizedBox(height: 6),
          Text(
            readablePatientName(patientName).isEmpty
                ? 'Patient'
                : readablePatientName(patientName),
            style: const TextStyle(color: Color(0xFF334155), fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                deviceConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                size: 18,
                color: deviceConnected ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
              ),
              const SizedBox(width: 6),
              Text(
                deviceConnected ? 'Tensiomètre connecté' : 'Tensiomètre non connecté',
                style: TextStyle(
                  color: deviceConnected ? const Color(0xFF15803D) : const Color(0xFFB91C1C),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InteractiveHubCard extends StatefulWidget {
  const _InteractiveHubCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.onTap,
    this.enabled = true,
    this.badgeText,
    this.badgeColor,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;
  final bool enabled;
  final String? badgeText;
  final Color? badgeColor;

  @override
  State<_InteractiveHubCard> createState() => _InteractiveHubCardState();
}

class _InteractiveHubCardState extends State<_InteractiveHubCard> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.enabled;
    final scale = _pressed ? 0.98 : (_hovered ? 1.02 : 1.0);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: active ? widget.onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          transform: Matrix4.diagonal3Values(scale, scale, 1),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              colors: active
                  ? [widget.accent.withValues(alpha: 0.12), Colors.white]
                  : [const Color(0xFFF1F5F9), const Color(0xFFF8FAFC)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(
              color: active ? widget.accent.withValues(alpha: 0.45) : const Color(0xFFE2E8F0),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: _hovered ? 0.12 : 0.08),
                blurRadius: _hovered ? 16 : 10,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: active ? widget.accent.withValues(alpha: 0.18) : const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(widget.icon, color: active ? widget.accent : const Color(0xFF94A3B8)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: active ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.subtitle,
                      style: const TextStyle(fontSize: 13, color: Color(0xFF475569)),
                    ),
                  ],
                ),
              ),
              if (widget.badgeText != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: (widget.badgeColor ?? const Color(0xFF94A3B8)).withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    widget.badgeText!,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: widget.badgeColor ?? const Color(0xFF475569),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BloodPressureLivePage extends StatelessWidget {
  const _BloodPressureLivePage({required this.provider});

  final BloodPressureProvider provider;

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('dd/MM/yyyy');
    final timeFmt = DateFormat('HH:mm');
    return AnimatedBuilder(
      animation: provider,
      builder: (context, _) {
        final latest = provider.latest;
        return Scaffold(
          appBar: AppBar(title: const Text('Mesure en temps réel')),
          body: RefreshIndicator(
            onRefresh: provider.refresh,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (latest == null)
                  const _EmptyLine(text: 'Aucune donnée temps réel disponible.')
                else ...[
                  _LiveReadingCard(latest: latest, dateFmt: dateFmt, timeFmt: timeFmt),
                  const SizedBox(height: 12),
                  _StatusCard(status: provider.status),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BloodPressureHistoryPage extends StatefulWidget {
  const _BloodPressureHistoryPage({required this.provider});
  final BloodPressureProvider provider;

  @override
  State<_BloodPressureHistoryPage> createState() => _BloodPressureHistoryPageState();
}

class _BloodPressureHistoryPageState extends State<_BloodPressureHistoryPage> {
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('dd/MM/yyyy');
    final timeFmt = DateFormat('HH:mm');
    return AnimatedBuilder(
      animation: widget.provider,
      builder: (context, _) {
        final filtered = widget.provider.history.where((m) {
          final d = _selectedDate;
          final t = _selectedTime;
          final dateMatches =
              d == null || (m.measuredAt.year == d.year && m.measuredAt.month == d.month && m.measuredAt.day == d.day);
          final timeMatches = t == null || (m.measuredAt.hour == t.hour && m.measuredAt.minute == t.minute);
          return dateMatches && timeMatches;
        }).toList();

        return Scaffold(
          appBar: AppBar(title: const Text('Historique des mesures')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _HistoryFilters(
                selectedDate: _selectedDate,
                selectedTime: _selectedTime,
                onPickDate: () async {
                  final now = DateTime.now();
                  final picked = await showDatePicker(
                    context: context,
                    firstDate: DateTime(now.year - 3),
                    lastDate: now,
                    initialDate: _selectedDate ?? now,
                  );
                  if (picked != null && mounted) {
                    setState(() => _selectedDate = picked);
                  }
                },
                onPickTime: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: _selectedTime ?? const TimeOfDay(hour: 8, minute: 0),
                  );
                  if (picked != null && mounted) {
                    setState(() => _selectedTime = picked);
                  }
                },
                onReset: () => setState(() {
                  _selectedDate = null;
                  _selectedTime = null;
                }),
                dateFmt: dateFmt,
              ),
              const SizedBox(height: 12),
              if (filtered.isEmpty)
                const _EmptyLine(text: 'Aucune mesure pour ce filtre.')
              else
                ...filtered.map(
                  (m) => _HistoryItem(
                    measurement: m,
                    dateFmt: dateFmt,
                    timeFmt: timeFmt,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _BloodPressureAlertsPage extends StatefulWidget {
  const _BloodPressureAlertsPage({required this.provider});
  final BloodPressureProvider provider;

  @override
  State<_BloodPressureAlertsPage> createState() => _BloodPressureAlertsPageState();
}

class _BloodPressureAlertsPageState extends State<_BloodPressureAlertsPage> {
  DateTime? _selectedDate;
  String _severity = 'all';

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('dd/MM/yyyy');
    final timeFmt = DateFormat('HH:mm');
    return AnimatedBuilder(
      animation: widget.provider,
      builder: (context, _) {
        final filtered = widget.provider.alerts.where((a) {
          final date = _selectedDate;
          final dateOk = date == null ||
              (a.createdAt.year == date.year &&
                  a.createdAt.month == date.month &&
                  a.createdAt.day == date.day);
          final isHigh = a.severity == 'high' || a.type.contains('high');
          final sevOk = _severity == 'all' ||
              (_severity == 'high' && isHigh) ||
              (_severity == 'normal' && !isHigh);
          return dateOk && sevOk;
        }).toList();
        return Scaffold(
          appBar: AppBar(title: const Text('Alertes')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _AlertFilters(
                selectedDate: _selectedDate,
                severity: _severity,
                dateFmt: dateFmt,
                onSeverityChanged: (v) => setState(() => _severity = v),
                onPickDate: () async {
                  final now = DateTime.now();
                  final picked = await showDatePicker(
                    context: context,
                    firstDate: DateTime(now.year - 3),
                    lastDate: now,
                    initialDate: _selectedDate ?? now,
                  );
                  if (picked != null && mounted) {
                    setState(() => _selectedDate = picked);
                  }
                },
                onReset: () => setState(() {
                  _selectedDate = null;
                  _severity = 'all';
                }),
              ),
              const SizedBox(height: 12),
              if (filtered.isEmpty)
                const _EmptyLine(text: 'Aucune alerte générée.')
              else
                ...filtered.map(
                  (a) => _AlertItem(
                    alert: a,
                    dateFmt: dateFmt,
                    timeFmt: timeFmt,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _HistoryFilters extends StatelessWidget {
  const _HistoryFilters({
    required this.selectedDate,
    required this.selectedTime,
    required this.onPickDate,
    required this.onPickTime,
    required this.onReset,
    required this.dateFmt,
  });

  final DateTime? selectedDate;
  final TimeOfDay? selectedTime;
  final VoidCallback onPickDate;
  final VoidCallback onPickTime;
  final VoidCallback onReset;
  final DateFormat dateFmt;

  @override
  Widget build(BuildContext context) {
    const borderColor = Color(0xFFD2E4F0);
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
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
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
          OutlinedButton.icon(
            onPressed: onPickDate,
            icon: const Icon(Icons.date_range_rounded),
            label: Text(
              selectedDate == null ? 'Filtrer par date' : dateFmt.format(selectedDate!),
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
          OutlinedButton.icon(
            onPressed: onPickTime,
            icon: const Icon(Icons.access_time_rounded),
            label: Text(
              selectedTime == null
                  ? 'Filtrer par heure'
                  : '${selectedTime!.hour.toString().padLeft(2, '0')}:${selectedTime!.minute.toString().padLeft(2, '0')}',
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
    );
  }
}

class _AlertFilters extends StatelessWidget {
  const _AlertFilters({
    required this.selectedDate,
    required this.severity,
    required this.dateFmt,
    required this.onSeverityChanged,
    required this.onPickDate,
    required this.onReset,
  });

  final DateTime? selectedDate;
  final String severity;
  final DateFormat dateFmt;
  final ValueChanged<String> onSeverityChanged;
  final VoidCallback onPickDate;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFCFEFF), Color(0xFFF2F8FC)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD2E4F0)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
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
                Icon(Icons.filter_alt_rounded, size: 14, color: _bpPrimary),
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
          OutlinedButton.icon(
            onPressed: onPickDate,
            icon: const Icon(Icons.date_range_rounded),
            label: Text(
              selectedDate == null ? 'Filtrer par date' : dateFmt.format(selectedDate!),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF0B6990),
              side: const BorderSide(color: Color(0xFFA7C9DC)),
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
            ),
          ),
          DropdownButtonHideUnderline(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: const Color(0xFFA7C9DC)),
              ),
              child: DropdownButton<String>(
                value: severity,
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('Toutes alertes')),
                  DropdownMenuItem(value: 'high', child: Text('Hypertension')),
                  DropdownMenuItem(value: 'normal', child: Text('Hypotension/Autres')),
                ],
                onChanged: (v) => onSeverityChanged(v ?? 'all'),
              ),
            ),
          ),
          TextButton.icon(
            onPressed: onReset,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Réinitialiser'),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF0B6990),
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

class _LiveReadingCard extends StatelessWidget {
  const _LiveReadingCard({
    required this.latest,
    required this.dateFmt,
    required this.timeFmt,
  });

  final BloodPressureMeasurement latest;
  final DateFormat dateFmt;
  final DateFormat timeFmt;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Mesure en temps réel',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _MetricPill(label: 'PAS', value: '${latest.systolic}'),
                const SizedBox(width: 8),
                _MetricPill(label: 'PAD', value: '${latest.diastolic}'),
                const SizedBox(width: 8),
                _MetricPill(
                  label: 'FC',
                  value: latest.heartRate == null ? '--' : '${latest.heartRate}',
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Dernière mesure: ${dateFmt.format(latest.measuredAt)} à ${timeFmt.format(latest.measuredAt)}',
              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          children: [
            Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status});
  final BloodPressureStatus status;

  @override
  Widget build(BuildContext context) {
    Color c;
    String text;
    switch (status) {
      case BloodPressureStatus.hypotension:
        c = const Color(0xFFF59E0B);
        text = 'Hypotension';
        break;
      case BloodPressureStatus.hypertension:
        c = const Color(0xFFDC2626);
        text = 'Hypertension';
        break;
      case BloodPressureStatus.normal:
        c = const Color(0xFF16A34A);
        text = 'Normal';
        break;
    }
    return Card(
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        leading: Icon(Icons.health_and_safety_rounded, color: c),
        title: const Text('Interprétation automatique'),
        subtitle: Text(
          text,
          style: TextStyle(
            color: c,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _HistoryItem extends StatelessWidget {
  const _HistoryItem({
    required this.measurement,
    required this.dateFmt,
    required this.timeFmt,
  });

  final BloodPressureMeasurement measurement;
  final DateFormat dateFmt;
  final DateFormat timeFmt;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: const Icon(Icons.monitor_heart_rounded, color: Color(0xFF4FA8D5)),
        title: Text('PAS ${measurement.systolic} / PAD ${measurement.diastolic}'),
        subtitle: Text(
          '${dateFmt.format(measurement.measuredAt)} • ${timeFmt.format(measurement.measuredAt)}'
          '${measurement.heartRate != null ? ' • FC ${measurement.heartRate}' : ''}',
        ),
      ),
    );
  }
}

class _AlertItem extends StatelessWidget {
  const _AlertItem({
    required this.alert,
    required this.dateFmt,
    required this.timeFmt,
  });

  final BloodPressureAlert alert;
  final DateFormat dateFmt;
  final DateFormat timeFmt;

  @override
  Widget build(BuildContext context) {
    final isRecent = DateTime.now().difference(alert.createdAt).inHours < 24;
    final danger = alert.severity == 'high' || alert.type.contains('high');
    final color = danger ? const Color(0xFFDC2626) : const Color(0xFFF59E0B);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Icon(Icons.warning_amber_rounded, color: color),
        title: Text(alert.message),
        subtitle: Text('${dateFmt.format(alert.createdAt)} • ${timeFmt.format(alert.createdAt)}'),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: (isRecent ? const Color(0xFFDBEAFE) : const Color(0xFFE2E8F0)),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            isRecent ? 'Récente' : 'Ancienne',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}

