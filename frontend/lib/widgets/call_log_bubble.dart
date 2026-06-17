import 'package:flutter/material.dart';

import '../headsapp_theme.dart';

/// Bulle centrée pour les journaux d'appel (`payload.kind == call_log`).
class CallLogBubble extends StatelessWidget {
  const CallLogBubble({
    super.key,
    required this.payload,
    this.titleOverride,
  });

  final Map<String, dynamic> payload;
  /// Texte principal (ex. champ `content` du message en base).
  final String? titleOverride;

  static int _durSec(Map<String, dynamic> p) {
    final d = p['durationSeconds'];
    if (d is int) return d;
    if (d is num) return d.toInt();
    return int.tryParse('$d') ?? 0;
  }

  static String _formatDuration(int sec) {
    if (sec <= 0) return '';
    final m = sec ~/ 60;
    final s = sec % 60;
    if (m > 0) {
      return '$m min ${s.toString().padLeft(2, '0')} s';
    }
    return '$s s';
  }

  @override
  Widget build(BuildContext context) {
    final mediaType = payload['mediaType']?.toString() ?? 'audio';
    final outcome = payload['outcome']?.toString() ?? 'ended';
    final isVideo = mediaType == 'video';
    final isRefused = outcome == 'refused';
    final isMissed = outcome == 'missed';
    final dur = _durSec(payload);
    final durLabel = _formatDuration(dur);

    late Color accent;
    late Color bg;
    late IconData icon;

    if (isMissed) {
      accent = HeadsAppColors.warning;
      bg = HeadsAppColors.warning.withValues(alpha: 0.10);
      icon = isVideo ? Icons.videocam_off_rounded : Icons.phone_missed_rounded;
    } else if (isRefused) {
      accent = HeadsAppColors.danger;
      bg = HeadsAppColors.danger.withValues(alpha: 0.10);
      icon = isVideo ? Icons.videocam_off_rounded : Icons.phone_disabled_rounded;
    } else if (isVideo) {
      accent = HeadsAppColors.brandPrimary;
      bg = HeadsAppColors.surfaceSoft;
      icon = Icons.videocam_rounded;
    } else {
      accent = HeadsAppColors.success;
      bg = HeadsAppColors.success.withValues(alpha: 0.10);
      icon = Icons.phone_rounded;
    }

    final fromPayload = payload['title']?.toString().trim();
    final title = (titleOverride != null && titleOverride!.trim().isNotEmpty)
        ? titleOverride!.trim()
        : (fromPayload != null && fromPayload.isNotEmpty)
            ? fromPayload
            : _defaultTitle(isVideo, isRefused, isMissed);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(HeadsAppMetrics.compactRadius),
              border: Border.all(color: accent.withValues(alpha: 0.45), width: 1.2),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 20, color: accent),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        title,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: accent.withValues(alpha: 0.95),
                          height: 1.25,
                        ),
                      ),
                    ),
                  ],
                ),
                if (durLabel.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Durée : $durLabel',
                    style: TextStyle(
                      fontSize: 12,
                      color: HeadsAppColors.textSecondary,
                      height: 1.2,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _defaultTitle(bool isVideo, bool isRefused, bool isMissed) {
    if (isMissed) {
      return isVideo ? 'Appel vidéo manqué' : 'Appel manqué';
    }
    if (isRefused) {
      return isVideo ? 'Appel vidéo refusé' : 'Appel audio refusé';
    }
    return isVideo ? 'Appel vidéo terminé' : 'Appel audio terminé';
  }
}
