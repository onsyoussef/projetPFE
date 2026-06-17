import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';

import '../headsapp_theme.dart';
import '../screens/doctor_prescription_pdf_viewer_screen.dart';
import '../widgets/prescription_form_sheet.dart';
import 'prescription_history_controller.dart';
import 'prescription_history_model.dart';
import 'prescription_history_strings.dart';
import 'prescription_history_theme.dart';

/// Panneau historique pour le médecin (actions Détail / Réutiliser).
Future<void> openDoctorPrescriptionHistory(
  BuildContext parentContext, {
  required String conversationId,
  required String doctorId,
  required String patientName,
  required bool sessionClosed,
  Future<void> Function()? onPrescriptionChanged,
}) {
  return showModalBottomSheet<void>(
    context: parentContext,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: PrescriptionHistoryTheme.background,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(PrescriptionHistoryTheme.sheetCornerRadius),
      ),
    ),
    builder: (sheetContext) {
      final h = MediaQuery.sizeOf(sheetContext).height;
      return SizedBox(
        height: h * 0.92,
        child: ChangeNotifierProvider(
          create: (_) => PrescriptionHistoryController(conversationId)..load(),
          child: _DoctorSheetBody(
            parentContext: parentContext,
            sheetContext: sheetContext,
            conversationId: conversationId,
            doctorId: doctorId,
            patientName: patientName,
            sessionClosed: sessionClosed,
            onPrescriptionChanged: onPrescriptionChanged,
          ),
        ),
      );
    },
  );
}

class _DoctorSheetBody extends StatelessWidget {
  const _DoctorSheetBody({
    required this.parentContext,
    required this.sheetContext,
    required this.conversationId,
    required this.doctorId,
    required this.patientName,
    required this.sessionClosed,
    this.onPrescriptionChanged,
  });

  final BuildContext parentContext;
  final BuildContext sheetContext;
  final String conversationId;
  final String doctorId;
  final String patientName;
  final bool sessionClosed;
  final Future<void> Function()? onPrescriptionChanged;

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: HeadsAppColors.textPrimary,
        );

    return Consumer<PrescriptionHistoryController>(
      builder: (context, ctrl, _) {
        return Container(
          decoration: BoxDecoration(
            color: PrescriptionHistoryTheme.background,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(PrescriptionHistoryTheme.sheetCornerRadius),
            ),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxW = constraints.maxWidth > 720 ? 640.0 : constraints.maxWidth;
              return Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxW),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 4, 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                PrescriptionHistoryStrings.sheetTitle,
                                style: titleStyle,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Actualiser',
                              onPressed: ctrl.loading ? null : () => ctrl.refresh(),
                              icon: const Icon(Icons.refresh_rounded),
                              color: HeadsAppColors.textSecondary,
                            ),
                            IconButton(
                              tooltip: PrescriptionHistoryStrings.close,
                              onPressed: () => Navigator.of(sheetContext).pop(),
                              icon: const Icon(Icons.close_rounded),
                              color: HeadsAppColors.textSecondary,
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: _Body(
                          ctrl: ctrl,
                          parentContext: parentContext,
                          sheetContext: sheetContext,
                          conversationId: conversationId,
                          doctorId: doctorId,
                          patientName: patientName,
                          sessionClosed: sessionClosed,
                          onPrescriptionChanged: onPrescriptionChanged,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.ctrl,
    required this.parentContext,
    required this.sheetContext,
    required this.conversationId,
    required this.doctorId,
    required this.patientName,
    required this.sessionClosed,
    this.onPrescriptionChanged,
  });

  final PrescriptionHistoryController ctrl;
  final BuildContext parentContext;
  final BuildContext sheetContext;
  final String conversationId;
  final String doctorId;
  final String patientName;
  final bool sessionClosed;
  final Future<void> Function()? onPrescriptionChanged;

  @override
  Widget build(BuildContext context) {
    if (ctrl.loading && ctrl.items.isEmpty) {
      return const _ShimmerList();
    }
    if (ctrl.errorMessage != null && ctrl.items.isEmpty) {
      return _ErrorState(
        message: ctrl.errorMessage!,
        onRetry: () => ctrl.refresh(),
      );
    }
    final items = ctrl.items;
    if (items.isEmpty) {
      return _EmptyState(
        onRefresh: () => ctrl.refresh(),
      );
    }
    return Column(
      children: [
        if (ctrl.loading)
          const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: RefreshIndicator(
            onRefresh: ctrl.refresh,
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              itemCount: items.length,
              itemBuilder: (context, i) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: HeadsAppMetrics.sectionSpacing),
                  child: _DoctorCard(
                    entry: items[i],
                    parentContext: parentContext,
                    sheetContext: sheetContext,
                    conversationId: conversationId,
                    doctorId: doctorId,
                    patientName: patientName,
                    sessionClosed: sessionClosed,
                    onPrescriptionChanged: onPrescriptionChanged,
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _ShimmerList extends StatelessWidget {
  const _ShimmerList();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: HeadsAppMetrics.pagePadding),
      child: Shimmer.fromColors(
        baseColor: HeadsAppColors.border.withValues(alpha: 0.65),
        highlightColor: HeadsAppColors.surface,
        child: ListView.builder(
          padding: const EdgeInsets.only(bottom: 16),
          itemCount: 5,
          itemBuilder: (context, i) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              height: 100,
              decoration: BoxDecoration(
                color: HeadsAppColors.surface,
                borderRadius: BorderRadius.circular(
                  PrescriptionHistoryTheme.cardCornerRadius,
                ),
                border: Border.all(color: HeadsAppColors.border),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onRefresh});

  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.55,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(HeadsAppMetrics.pagePadding),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.receipt_long_outlined,
                      size: 72,
                      color: HeadsAppColors.textSecondary.withValues(alpha: 0.45),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      PrescriptionHistoryStrings.emptyTitle,
                      textAlign: TextAlign.center,
                      style: theme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: HeadsAppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      PrescriptionHistoryStrings.emptySubtitle,
                      textAlign: TextAlign.center,
                      style: theme.bodyMedium?.copyWith(
                        color: HeadsAppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () => onRefresh(),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Actualiser'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 48,
              color: HeadsAppColors.textSecondary,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: HeadsAppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onRetry,
              child: Text(PrescriptionHistoryStrings.retry),
            ),
          ],
        ),
      ),
    );
  }
}

class _DoctorCard extends StatelessWidget {
  const _DoctorCard({
    required this.entry,
    required this.parentContext,
    required this.sheetContext,
    required this.conversationId,
    required this.doctorId,
    required this.patientName,
    required this.sessionClosed,
    this.onPrescriptionChanged,
  });

  final PrescriptionHistoryEntry entry;
  final BuildContext parentContext;
  final BuildContext sheetContext;
  final String conversationId;
  final String doctorId;
  final String patientName;
  final bool sessionClosed;
  final Future<void> Function()? onPrescriptionChanged;

  String _dateLabel() {
    final d = entry.createdAt;
    if (d == null) return '—';
    return DateFormat('d MMM yyyy - HH:mm', 'en_US').format(d.toLocal());
  }

  void _openDetail() {
    final url = entry.pdfUrl.trim();
    if (url.isEmpty) return;
    Navigator.of(sheetContext).pop();
    Navigator.of(parentContext).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => DoctorPrescriptionPdfViewerScreen(
          pdfUrl: url,
          conversationId: conversationId,
          prescriptionId: entry.id,
          prescriptionMessageId: entry.prescriptionMessageId,
        ),
      ),
    );
  }

  Future<void> _reorder() async {
    if (sessionClosed) return;
    Navigator.of(sheetContext).pop();
    final initial = <Map<String, String>>[];
    for (final m in entry.medications) {
      initial.add({
        'name': m.name,
        'posologie': m.dosage,
        'duree': m.duration,
        'instructions': m.instructions,
      });
    }
    await showDoctorPrescriptionFormBottomSheet(
      parentContext,
      conversationId: conversationId,
      doctorId: doctorId,
      patientName: patientName,
      source: PrescriptionSendSource.chat,
      initialMedicationRows: initial.isEmpty ? null : initial,
      initialNotes: entry.note.isEmpty ? null : entry.note,
      initialCity: entry.city.isEmpty ? null : entry.city,
      onSent: onPrescriptionChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final badgeActive = entry.statusLabelKey == 'delivered';
    final radius = PrescriptionHistoryTheme.cardCornerRadius;

    return Material(
      color: PrescriptionHistoryTheme.cardSurface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: const BorderSide(color: HeadsAppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _dateLabel(),
                        style: theme.bodySmall?.copyWith(
                          color: HeadsAppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        entry.doctorName.isNotEmpty
                            ? 'Dr ${entry.doctorName}'
                            : '—',
                        style: theme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: HeadsAppColors.textPrimary,
                        ),
                      ),
                      if (entry.doctorSpecialty.isNotEmpty)
                        Text(
                          entry.doctorSpecialty,
                          style: theme.bodySmall?.copyWith(
                            color: HeadsAppColors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
                _StatusChip(
                  active: badgeActive,
                  label: PrescriptionHistoryStrings.statusDelivered,
                ),
              ],
            ),
            if (entry.medications.isNotEmpty) ...[
              const SizedBox(height: 12),
              ...entry.medications.map(
                (m) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.medication_liquid_outlined,
                        size: 18,
                        color: HeadsAppColors.brandPrimary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          [
                            m.name,
                            if (m.dosage.isNotEmpty) ' — ${m.dosage}',
                            if (m.duration.isNotEmpty) ' · ${m.duration}',
                          ].join(),
                          style: theme.bodyLarge?.copyWith(
                            color: HeadsAppColors.textPrimary,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                OutlinedButton(
                  onPressed: _openDetail,
                  child: Text(PrescriptionHistoryStrings.actionDetail),
                ),
                FilledButton.tonal(
                  onPressed: sessionClosed ? null : _reorder,
                  child: Text(
                    sessionClosed
                        ? PrescriptionHistoryStrings.sessionClosedHint
                        : PrescriptionHistoryStrings.actionReorder,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.active,
    required this.label,
  });

  final bool active;
  final String label;

  @override
  Widget build(BuildContext context) {
    final bg = active
        ? PrescriptionHistoryTheme.badgeActiveBg
        : PrescriptionHistoryTheme.badgeInactiveBg;
    final fg = active
        ? PrescriptionHistoryTheme.badgeActiveFg
        : PrescriptionHistoryTheme.badgeInactiveFg;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(
          PrescriptionHistoryTheme.chipCornerRadius,
        ),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: fg,
            ),
      ),
    );
  }
}
