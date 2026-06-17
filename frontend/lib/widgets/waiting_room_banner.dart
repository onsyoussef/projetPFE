import 'dart:async';

import 'package:flutter/material.dart';

import '../headsapp_theme.dart';

/// Bandeau salle d’attente : avant J-10 compte à rebours vers l’ouverture + bouton désactivé ;
/// à partir de J-10 : compte à rebours vers la consultation + bouton actif.
class WaitingRoomBanner extends StatefulWidget {
  const WaitingRoomBanner({
    super.key,
    required this.consultationTime,
    required this.waitingRoomOpensAt,
    required this.canEnterWaitingRoom,
    required this.doctorName,
    required this.specialty,
    required this.onEnterRoom,
  });

  final DateTime consultationTime;
  final DateTime waitingRoomOpensAt;
  final bool canEnterWaitingRoom;
  final String doctorName;
  final String specialty;
  final VoidCallback onEnterRoom;

  @override
  State<WaitingRoomBanner> createState() => _WaitingRoomBannerState();
}

class _WaitingRoomBannerState extends State<WaitingRoomBanner> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String _fmtCountdown(Duration diff) {
    if (diff.isNegative || diff.inSeconds <= 0) {
      return 'maintenant';
    }
    final m = diff.inMinutes;
    final s = diff.inSeconds % 60;
    return 'dans $m min ${s.toString().padLeft(2, '0')} sec';
  }

  @override
  Widget build(BuildContext context) {
    final spec = widget.specialty.trim().isEmpty ? 'Médecin' : widget.specialty.trim();
    final now = DateTime.now();

    final String title;
    if (widget.canEnterWaitingRoom) {
      final diff = widget.consultationTime.difference(now);
      if (diff.isNegative || diff.inSeconds <= 0) {
        title = 'Votre consultation commence maintenant.';
      } else {
        title = 'Votre consultation commence ${_fmtCountdown(diff)}';
      }
    } else if (now.isBefore(widget.waitingRoomOpensAt)) {
      title =
          'La salle d\'attente s\'ouvre ${_fmtCountdown(widget.waitingRoomOpensAt.difference(now))}';
    } else {
      title = 'Préparez-vous : la consultation va commencer.';
    }

    return Material(
      elevation: 2,
      color: HeadsAppColors.surfaceSoft,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: HeadsAppColors.textPrimary,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${widget.doctorName} · $spec',
              style: const TextStyle(fontSize: 13, color: HeadsAppColors.textSecondary),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: widget.canEnterWaitingRoom ? widget.onEnterRoom : null,
                style: FilledButton.styleFrom(
                  backgroundColor: HeadsAppColors.brandPrimary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: HeadsAppColors.textTertiary,
                  disabledForegroundColor: Colors.white70,
                ),
                child: Text(
                  widget.canEnterWaitingRoom
                      ? 'Entrer dans la salle d\'attente'
                      : 'Ouverture 10 min avant l\'heure',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
