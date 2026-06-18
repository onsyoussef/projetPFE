import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../headsapp_theme.dart';
import '../models/blood_pressure_alert.dart';
import '../models/blood_pressure_measurement.dart';
import '../providers/blood_pressure_provider.dart';
import '../utils/patient_ui_utils.dart';

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

  Future<void> _toggleBleConnection() async {
    if (_provider.bleConnecting) return;
    try {
      if (_provider.bleConnected) {
        await _provider.disconnectBle();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tensiomètre déconnecté.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        await _provider.connectBle();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tensiomètre connecté. Les mesures seront synchronisées.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _provider,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: HeadsAppColors.surfaceAlt,
          appBar: AppBar(
            title: const Text('Tensiomètre connecté'),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: TextButton.icon(
                  onPressed: _provider.bleConnecting ? null : _toggleBleConnection,
                  icon: _provider.bleConnecting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          _provider.bleConnected
                              ? Icons.bluetooth_connected_rounded
                              : Icons.bluetooth_rounded,
                          size: 20,
                        ),
                  label: Text(
                    _provider.bleConnecting
                        ? 'Connexion…'
                        : (_provider.bleConnected ? 'Connecté' : 'Se connecter'),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: _provider.bleConnected
                        ? HeadsAppColors.success
                        : HeadsAppColors.brandPrimary,
                    textStyle: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
          body: _provider.loading
              ? const Center(
                  child: CircularProgressIndicator(
                    color: HeadsAppColors.brandPrimary,
                  ),
                )
              : RefreshIndicator(
                  color: HeadsAppColors.brandPrimary,
                  onRefresh: _provider.refresh,
                  child: ListView(
                    padding: const EdgeInsets.all(HeadsAppMetrics.pagePadding),
                    children: [
                      _HubHeader(
                        patientName: widget.patientName,
                        bleConnected: _provider.bleConnected,
                        bleStatusMessage: _provider.bleStatusMessage,
                      ),
                      const SizedBox(height: 14),
                      if (!_provider.bleConnected)
                        _BleHintCard(connecting: _provider.bleConnecting)
                      else ...[
                        _InteractiveHubCard(
                          title: 'Mesure en temps réel',
                          subtitle:
                              'Consulter PAS/PAD/FC et l\'interprétation instantanée',
                          icon: Icons.monitor_heart_rounded,
                          accent: HeadsAppColors.brandPrimary,
                          badgeText: 'Connecté',
                          badgeColor: HeadsAppColors.success,
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    _BloodPressureLivePage(provider: _provider),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                      ],
                      _InteractiveHubCard(
                        title: 'Historique',
                        subtitle: 'Voir et filtrer les mesures précédentes',
                        icon: Icons.history_rounded,
                        accent: HeadsAppColors.brandPrimary,
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
                        accent: HeadsAppColors.warning,
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
                            color: HeadsAppColors.warning,
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
  const _HubHeader({
    required this.patientName,
    required this.bleConnected,
    this.bleStatusMessage,
  });

  final String patientName;
  final bool bleConnected;
  final String? bleStatusMessage;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: HeadsAppColors.surface,
        borderRadius: BorderRadius.circular(HeadsAppMetrics.cardRadius),
        border: Border.all(color: HeadsAppColors.border),
        boxShadow: [
          BoxShadow(
            color: HeadsAppColors.brandPrimary.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Suivi tensionnel',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: HeadsAppColors.textPrimary,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            readablePatientName(patientName).isEmpty
                ? 'Patient'
                : readablePatientName(patientName),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                bleConnected
                    ? Icons.bluetooth_connected_rounded
                    : Icons.bluetooth_disabled_rounded,
                size: 18,
                color: bleConnected
                    ? HeadsAppColors.success
                    : HeadsAppColors.textTertiary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  bleStatusMessage ??
                      (bleConnected
                          ? 'Tensiomètre connecté via Bluetooth'
                          : 'Appuyez sur « Se connecter » pour lier le tensiomètre'),
                  style: TextStyle(
                    color: bleConnected
                        ? HeadsAppColors.success
                        : HeadsAppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BleHintCard extends StatelessWidget {
  const _BleHintCard({required this.connecting});

  final bool connecting;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: HeadsAppColors.brandHighlight,
        borderRadius: BorderRadius.circular(HeadsAppMetrics.compactRadius),
        border: Border.all(
          color: HeadsAppColors.brandPrimary.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            connecting ? Icons.hourglass_top_rounded : Icons.info_outline_rounded,
            color: HeadsAppColors.brandPrimary,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              connecting
                  ? 'Connexion Bluetooth en cours avec le tensiomètre ESP32…'
                  : 'La carte « Mesure en temps réel » apparaîtra après connexion Bluetooth via le bouton « Se connecter » en haut à droite.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: HeadsAppColors.textSecondary,
                    height: 1.45,
                  ),
            ),
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
    this.badgeText,
    this.badgeColor,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;
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
    final scale = _pressed ? 0.98 : (_hovered ? 1.02 : 1.0);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          transform: Matrix4.diagonal3Values(scale, scale, 1),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: HeadsAppColors.surface,
            borderRadius: BorderRadius.circular(HeadsAppMetrics.cardRadius),
            border: Border.all(color: HeadsAppColors.border),
            boxShadow: [
              BoxShadow(
                color: HeadsAppColors.brandPrimary.withValues(alpha: _hovered ? 0.12 : 0.06),
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
                  color: widget.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(HeadsAppMetrics.compactRadius),
                ),
                child: Icon(widget.icon, color: widget.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: HeadsAppColors.textPrimary,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: HeadsAppColors.textSecondary,
                          ),
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
          backgroundColor: HeadsAppColors.surfaceAlt,
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
          backgroundColor: HeadsAppColors.surfaceAlt,
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
          backgroundColor: HeadsAppColors.surfaceAlt,
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
    const borderColor = HeadsAppColors.border;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            HeadsAppColors.surface,
            HeadsAppColors.surfaceSoft,
          ],
        ),
        borderRadius: BorderRadius.circular(HeadsAppMetrics.compactRadius),
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
              color: HeadsAppColors.brandPrimary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.tune_rounded, size: 14, color: HeadsAppColors.brandPrimary),
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
          OutlinedButton.icon(
            onPressed: onPickDate,
            icon: const Icon(Icons.date_range_rounded),
            label: Text(
              selectedDate == null ? 'Filtrer par date' : dateFmt.format(selectedDate!),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: HeadsAppColors.brandPrimary,
              side: const BorderSide(color: HeadsAppColors.border),
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
              foregroundColor: HeadsAppColors.brandPrimary,
              side: const BorderSide(color: HeadsAppColors.border),
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
              foregroundColor: HeadsAppColors.brandPrimary,
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
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            HeadsAppColors.surface,
            HeadsAppColors.surfaceSoft,
          ],
        ),
        borderRadius: BorderRadius.circular(HeadsAppMetrics.compactRadius),
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
              color: HeadsAppColors.brandPrimary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.filter_alt_rounded, size: 14, color: HeadsAppColors.brandPrimary),
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
          OutlinedButton.icon(
            onPressed: onPickDate,
            icon: const Icon(Icons.date_range_rounded),
            label: Text(
              selectedDate == null ? 'Filtrer par date' : dateFmt.format(selectedDate!),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: HeadsAppColors.brandPrimary,
              side: const BorderSide(color: HeadsAppColors.border),
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
                border: Border.all(color: HeadsAppColors.border),
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
              foregroundColor: HeadsAppColors.brandPrimary,
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
        leading: const Icon(Icons.monitor_heart_rounded, color: HeadsAppColors.brandPrimary),
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

