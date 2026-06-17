import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';

import '../headsapp_theme.dart';
import '../services/api_service.dart';
import '../widgets/medical_dossier_file_viewer.dart';
import 'prescription_history_controller.dart';
import 'prescription_history_model.dart';
import 'prescription_history_strings.dart';
import 'prescription_history_theme.dart';

/// Ouvre le panneau d’historique (patient) depuis la barre du chat.
Future<void> openPrescriptionHistory(
  BuildContext context, {
  required String conversationId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: PrescriptionHistoryTheme.background,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(PrescriptionHistoryTheme.sheetCornerRadius),
      ),
    ),
    builder: (ctx) {
      final h = MediaQuery.sizeOf(ctx).height;
      return SizedBox(
        height: h * 0.92,
        child: ChangeNotifierProvider(
          create: (_) => PrescriptionHistoryController(conversationId)..load(),
          child: _PrescriptionHistorySheet(
            conversationId: conversationId,
            isDoctor: false,
          ),
        ),
      );
    },
  );
}

class _PrescriptionHistorySheet extends StatelessWidget {
  const _PrescriptionHistorySheet({
    required this.conversationId,
    required this.isDoctor,
  });

  final String conversationId;
  final bool isDoctor;

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
                              tooltip: PrescriptionHistoryStrings.close,
                              onPressed: () => Navigator.of(context).pop(),
                              icon: const Icon(Icons.close_rounded),
                              color: HeadsAppColors.textSecondary,
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: _SheetBody(
                          ctrl: ctrl,
                          conversationId: conversationId,
                          isDoctor: isDoctor,
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

class _SheetBody extends StatelessWidget {
  const _SheetBody({
    required this.ctrl,
    required this.conversationId,
    required this.isDoctor,
  });

  final PrescriptionHistoryController ctrl;
  final String conversationId;
  final bool isDoctor;

  @override
  Widget build(BuildContext context) {
    if (ctrl.loading && (ctrl.items == null || ctrl.items!.isEmpty)) {
      return const _ShimmerList();
    }
    if (ctrl.errorMessage != null &&
        (ctrl.items == null || ctrl.items!.isEmpty)) {
      return _ErrorState(
        message: ctrl.errorMessage!,
        onRetry: () => ctrl.load(),
      );
    }
    final items = ctrl.items ?? [];
    if (items.isEmpty) {
      return const _EmptyState();
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: items.length,
      itemBuilder: (context, i) {
        return Padding(
          padding: const EdgeInsets.only(bottom: HeadsAppMetrics.sectionSpacing),
          child: _PrescriptionCard(
            entry: items[i],
            conversationId: conversationId,
            isDoctor: isDoctor,
          ),
        );
      },
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
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Center(
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
          ],
        ),
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

class _PrescriptionCard extends StatelessWidget {
  const _PrescriptionCard({
    required this.entry,
    required this.conversationId,
    required this.isDoctor,
  });

  final PrescriptionHistoryEntry entry;
  final String conversationId;
  final bool isDoctor;

  String _dateLabel() {
    final d = entry.createdAt;
    if (d == null) return '—';
    return DateFormat('d MMM yyyy - HH:mm', 'en_US').format(d.toLocal());
  }

  Future<void> _openPdf(BuildContext context) async {
    final pid = entry.id.trim();
    if (pid.isEmpty) return;
    final url = ApiService.prescriptionPdfProxyUrlByPrescriptionId(
      conversationId: conversationId,
      prescriptionId: pid,
    );
    await showMedicalDossierFileViewer(
      context,
      resolvedUrl: url,
      filename: 'ordonnance.pdf',
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
      child: InkWell(
        onTap: isDoctor ? null : () => _openPdf(context),
        borderRadius: BorderRadius.circular(radius),
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
            ],
          ),
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
