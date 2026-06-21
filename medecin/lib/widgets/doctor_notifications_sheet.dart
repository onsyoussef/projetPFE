import 'package:flutter/material.dart';

import '../headsapp_theme.dart';

enum DoctorNotificationVisualKind {
  urgent,
  analysis,
  message,
  newPatient,
}

class DoctorNotificationSheetItem {
  const DoctorNotificationSheetItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.subtitle,
    this.occurredAt,
    this.dismissible = false,
    this.onTap,
  });

  final String id;
  final DoctorNotificationVisualKind kind;
  final String title;
  final String subtitle;
  final DateTime? occurredAt;
  final bool dismissible;
  final VoidCallback? onTap;
}

Future<void> showDoctorNotificationsSheet(
  BuildContext context, {
  required List<DoctorNotificationSheetItem> items,
  required Future<void> Function(DoctorNotificationSheetItem item) onDismissItem,
  required Future<void> Function() onDismissAll,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFFF5F7FA),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetCtx) {
      final h = MediaQuery.sizeOf(context).height * 0.88;
      return SafeArea(
        child: SizedBox(
          height: h,
          child: _DoctorNotificationsSheetBody(
            sheetContext: sheetCtx,
            initialItems: items,
            onDismissItem: onDismissItem,
            onDismissAll: onDismissAll,
          ),
        ),
      );
    },
  );
}

class _DoctorNotificationsSheetBody extends StatefulWidget {
  const _DoctorNotificationsSheetBody({
    required this.sheetContext,
    required this.initialItems,
    required this.onDismissItem,
    required this.onDismissAll,
  });

  final BuildContext sheetContext;
  final List<DoctorNotificationSheetItem> initialItems;
  final Future<void> Function(DoctorNotificationSheetItem item) onDismissItem;
  final Future<void> Function() onDismissAll;

  @override
  State<_DoctorNotificationsSheetBody> createState() =>
      _DoctorNotificationsSheetBodyState();
}

class _DoctorNotificationsSheetBodyState
    extends State<_DoctorNotificationsSheetBody> {
  static const Color _headerBlue = Color(0xFF1A56BE);

  late List<DoctorNotificationSheetItem> _items;

  @override
  void initState() {
    super.initState();
    _items = List<DoctorNotificationSheetItem>.from(widget.initialItems);
  }

  Future<void> _removeItem(DoctorNotificationSheetItem item) async {
    await widget.onDismissItem(item);
    if (!mounted) return;
    setState(() {
      _items.removeWhere((e) => e.id == item.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 10),
        Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFDCE3EC),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 16, 12),
          child: Row(
            children: [
              IconButton(
                onPressed: () => Navigator.of(widget.sheetContext).pop(),
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                color: _headerBlue,
              ),
              const Text(
                'Notifications',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: _headerBlue,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x0D000000),
                    blurRadius: 20,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: _items.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Aucune notification pour le moment.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: HeadsAppColors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    )
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _items.length,
                        separatorBuilder: (_, _) => Divider(
                          height: 1,
                          thickness: 1,
                          indent: 72,
                          endIndent: 16,
                          color: HeadsAppColors.border.withValues(alpha: 0.65),
                        ),
                        itemBuilder: (context, index) {
                          final item = _items[index];
                          final row = _DoctorNotificationRow(item: item);
                          if (!item.dismissible) return row;
                          return Dismissible(
                            key: ValueKey<String>(item.id),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              color: HeadsAppColors.danger.withValues(alpha: 0.12),
                              child: Icon(
                                Icons.delete_outline_rounded,
                                color: HeadsAppColors.danger,
                              ),
                            ),
                            onDismissed: (_) => _removeItem(item),
                            child: row,
                          );
                        },
                      ),
                    ),
            ),
          ),
        ),
        if (_items.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: TextButton(
              onPressed: () async {
                await widget.onDismissAll();
                if (widget.sheetContext.mounted) {
                  Navigator.of(widget.sheetContext).pop();
                }
              },
              child: const Text(
                'Tout effacer',
                style: TextStyle(
                  color: _headerBlue,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _DoctorNotificationRow extends StatelessWidget {
  const _DoctorNotificationRow({required this.item});

  final DoctorNotificationSheetItem item;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: item.onTap == null
            ? null
            : () {
                Navigator.of(context).pop();
                item.onTap!();
              },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DoctorNotificationIcon(kind: item.kind),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            item.title,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: _titleColor(item.kind),
                              height: 1.25,
                            ),
                          ),
                        ),
                        if (item.occurredAt != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            _formatNotificationTime(item.occurredAt!),
                            style: TextStyle(
                              fontSize: 12,
                              color: HeadsAppColors.textSecondary
                                  .withValues(alpha: 0.9),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: HeadsAppColors.textSecondary,
                        fontWeight: FontWeight.w500,
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

  static Color _titleColor(DoctorNotificationVisualKind kind) {
    switch (kind) {
      case DoctorNotificationVisualKind.urgent:
        return const Color(0xFFC0392B);
      case DoctorNotificationVisualKind.analysis:
        return const Color(0xFF0F766E);
      case DoctorNotificationVisualKind.message:
        return const Color(0xFF1A56BE);
      case DoctorNotificationVisualKind.newPatient:
        return const Color(0xFF1A56BE);
    }
  }

  static String _formatNotificationTime(DateTime at) {
    final local = at.toLocal();
    final diff = DateTime.now().difference(local);
    if (diff.inMinutes < 1) return 'À l\'instant';
    if (diff.inMinutes < 60) return 'Il y a ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Il y a ${diff.inHours} h';
    if (diff.inDays == 1) return 'Hier';
    return 'Il y a ${diff.inDays} j';
  }
}

class _DoctorNotificationIcon extends StatelessWidget {
  const _DoctorNotificationIcon({required this.kind});

  final DoctorNotificationVisualKind kind;

  @override
  Widget build(BuildContext context) {
    late final Color bg;
    late final Color fg;
    late final IconData icon;

    switch (kind) {
      case DoctorNotificationVisualKind.urgent:
        bg = const Color(0xFFFFE8E8);
        fg = const Color(0xFFC0392B);
        icon = Icons.warning_amber_rounded;
      case DoctorNotificationVisualKind.analysis:
        bg = const Color(0xFFE8F4FF);
        fg = const Color(0xFF0F766E);
        icon = Icons.biotech_outlined;
      case DoctorNotificationVisualKind.message:
        bg = const Color(0xFFE8F2FF);
        fg = const Color(0xFF1A56BE);
        icon = Icons.chat_bubble_outline_rounded;
      case DoctorNotificationVisualKind.newPatient:
        bg = const Color(0xFFF2F4F7);
        fg = const Color(0xFF1A56BE);
        icon = Icons.person_outline_rounded;
    }

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Icon(icon, color: fg, size: 20),
    );
  }
}
