import 'package:flutter/material.dart';

const _frenchMonthsUpper = [
  'JANVIER',
  'FÉVRIER',
  'MARS',
  'AVRIL',
  'MAI',
  'JUIN',
  'JUILLET',
  'AOÛT',
  'SEPTEMBRE',
  'OCTOBRE',
  'NOVEMBRE',
  'DÉCEMBRE',
];

DateTime? chatMessageCreatedAtLocal(Map<String, dynamic> msg) {
  final raw = msg['createdAt'];
  if (raw is String) return DateTime.tryParse(raw)?.toLocal();
  return null;
}

String chatSessionStatusLabel(Map<String, dynamic> msg, {required bool closed}) {
  final dt = chatMessageCreatedAtLocal(msg);
  final prefix = closed ? 'DISCUSSION CLÔTURÉE' : 'DISCUSSION RÉOUVERTE';
  if (dt == null) return prefix;
  final month = _frenchMonthsUpper[dt.month - 1];
  return '$prefix LE ${dt.day} $month.';
}

/// Pastille centrée « DISCUSSION CLÔTURÉE / RÉOUVERTE LE … » dans le fil de chat.
class ChatSessionStatusChip extends StatelessWidget {
  const ChatSessionStatusChip({
    super.key,
    required this.msg,
    required this.closed,
  });

  final Map<String, dynamic> msg;
  final bool closed;

  @override
  Widget build(BuildContext context) {
    final label = chatSessionStatusLabel(msg, closed: closed);
    final bg = closed ? const Color(0xFFEEF2F6) : const Color(0xFFE8F5E9);
    final fg = closed ? const Color(0xFF64748B) : const Color(0xFF166534);
    final border = closed ? const Color(0xFFE2E8F0) : const Color(0xFFBBF7D0);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 340),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: border),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }
}
