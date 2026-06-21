import 'package:flutter/material.dart';

import '../headsapp_theme.dart';

enum PatientNotificationType {
  accepted,
  file,
  teleconsult,
  message,
  rejected,
}

class PatientNotificationEntry {
  PatientNotificationEntry({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    required this.timestamp,
    this.isNew = true,
  });

  final String id;
  final PatientNotificationType type;
  final String title;
  final String description;
  final DateTime timestamp;
  bool isNew;
}

class PatientNotificationsScreen extends StatefulWidget {
  const PatientNotificationsScreen({
    super.key,
    required this.items,
    required this.onMarkAllAsRead,
    required this.onItemTap,
  });

  final List<PatientNotificationEntry> items;
  final VoidCallback onMarkAllAsRead;
  final ValueChanged<PatientNotificationEntry> onItemTap;

  @override
  State<PatientNotificationsScreen> createState() =>
      _PatientNotificationsScreenState();
}

class _PatientNotificationsScreenState extends State<PatientNotificationsScreen> {
  late List<PatientNotificationEntry> _items;

  @override
  void initState() {
    super.initState();
    _items = List<PatientNotificationEntry>.from(widget.items);
  }

  int get _newTodayCount => _items.where((e) => e.isNew).length;

  void _markAllAsRead() {
    setState(() {
      for (final item in _items) {
        item.isNew = false;
      }
    });
    widget.onMarkAllAsRead();
  }

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF1A2B48);
    const linkBlue = Color(0xFF4A89DC);
    const summaryGrey = Color(0xFF718096);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_rounded, color: navy),
                  ),
                  Expanded(
                    child: Text(
                      'Notifications',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: navy,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      _newTodayCount > 0
                          ? 'Vous avez $_newTodayCount nouvelle${_newTodayCount > 1 ? 's' : ''} notification${_newTodayCount > 1 ? 's' : ''} aujourd\'hui'
                          : 'Aucune nouvelle notification aujourd\'hui',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: summaryGrey,
                            height: 1.35,
                          ),
                    ),
                  ),
                  if (_newTodayCount > 0) ...[
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: _markAllAsRead,
                      child: Text(
                        'Tout marquer comme lu',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: linkBlue,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: _items.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          'Aucune notification pour le moment.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                color: summaryGrey,
                              ),
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                      itemCount: _items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 14),
                      itemBuilder: (context, index) {
                        final item = _items[index];
                        return _NotificationCard(
                          item: item,
                          onTap: () {
                            setState(() => item.isNew = false);
                            widget.onItemTap(item);
                          },
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

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.item,
    required this.onTap,
  });

  final PatientNotificationEntry item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = _styleForType(item.type);
    final timeLabel = _formatNotificationTime(item.timestamp);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      elevation: 0,
      shadowColor: Colors.black.withValues(alpha: 0.06),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1A2B48).withValues(alpha: 0.06),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 4,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          HeadsAppColors.authGradientStart,
                          HeadsAppColors.authGradientEnd,
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: style.iconBg,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  style.icon,
                                  color: style.iconColor,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            item.title,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleSmall
                                                ?.copyWith(
                                                  color: const Color(0xFF111827),
                                                  fontWeight: FontWeight.w800,
                                                  height: 1.2,
                                                ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          timeLabel,
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall
                                              ?.copyWith(
                                                color: const Color(0xFF9CA3AF),
                                                fontWeight: FontWeight.w500,
                                              ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      item.description,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: const Color(0xFF6B7280),
                                            height: 1.4,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          if (item.isNew) ...[
                            const SizedBox(height: 12),
                            _NouveauBadge(),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NouveauBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: HeadsAppColors.primaryButtonGradient,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        child: Text(
          'NOUVEAU',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
              ),
        ),
      ),
    );
  }
}

class _NotificationVisualStyle {
  const _NotificationVisualStyle({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBg;
}

_NotificationVisualStyle _styleForType(PatientNotificationType type) {
  switch (type) {
    case PatientNotificationType.accepted:
      return const _NotificationVisualStyle(
        icon: Icons.check_rounded,
        iconColor: Color(0xFF16A34A),
        iconBg: Color(0xFFE8F8EF),
      );
    case PatientNotificationType.file:
      return const _NotificationVisualStyle(
        icon: Icons.description_outlined,
        iconColor: Color(0xFF265AA6),
        iconBg: Color(0xFFE8F2FC),
      );
    case PatientNotificationType.teleconsult:
      return const _NotificationVisualStyle(
        icon: Icons.videocam_rounded,
        iconColor: Color(0xFFEA580C),
        iconBg: Color(0xFFFFF4ED),
      );
    case PatientNotificationType.rejected:
      return const _NotificationVisualStyle(
        icon: Icons.cancel_outlined,
        iconColor: Color(0xFFDC2626),
        iconBg: Color(0xFFFEE2E2),
      );
    case PatientNotificationType.message:
      return const _NotificationVisualStyle(
        icon: Icons.chat_bubble_outline_rounded,
        iconColor: HeadsAppColors.brandPrimary,
        iconBg: Color(0xFFE8F2FC),
      );
  }
}

String _formatNotificationTime(DateTime timestamp) {
  final local = timestamp.toLocal();
  final now = DateTime.now();
  final diff = now.difference(local);
  if (diff.inMinutes < 1) return 'À l\'instant';
  if (diff.inMinutes < 60) return 'Il y a ${diff.inMinutes} min';
  if (diff.inHours < 24 &&
      local.year == now.year &&
      local.month == now.month &&
      local.day == now.day) {
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }
  return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}';
}
