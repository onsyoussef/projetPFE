import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/call_chat_context.dart';
import '../services/webrtc_service.dart';
import '../utils/waiting_room_unload.dart';

// Palette
const Color _cBg = Color(0xFF0F172A);
const Color _cCard = Color(0xFF1E293B);
const Color _cAccent = Color(0xFF38BDF8);
const Color _cTextMain = Color(0xFFF8FAFC);
const Color _cTextSec = Color(0xFF94A3B8);
const Color _cSuccess = Color(0xFF22C55E);
const Color _cBorder = Color(0xFF334155);
const Color _cDanger = Color(0xFFEF4444);
const Color _cAvatarFallback = Color(0xFF1E40AF);

/// Écran plein : attente du médecin, compte à rebours, option quitter.
class WaitingRoomScreen extends StatefulWidget {
  const WaitingRoomScreen({
    super.key,
    required this.consultationTime,
    required this.doctorName,
    this.doctorAvatarUrl,
    required this.onLeaveRoom,
    this.onSyncUnload,
    this.onConsultationStillValid,
    this.onConsultationInvalidated,
  });

  final DateTime consultationTime;
  final String doctorName;
  final String? doctorAvatarUrl;
  final Future<void> Function() onLeaveRoom;
  final void Function()? onSyncUnload;
  final Future<bool> Function()? onConsultationStillValid;
  final Future<void> Function()? onConsultationInvalidated;

  @override
  State<WaitingRoomScreen> createState() => _WaitingRoomScreenState();
}

class _WaitingRoomScreenState extends State<WaitingRoomScreen>
    with TickerProviderStateMixin {
  /// Fenêtre affichée : J-10 → RDV → J+10 (20 min au total), alignée sur le chat patient.
  static const _windowBeforeConsult = Duration(minutes: 10);
  static const _windowAfterConsult = Duration(minutes: 10);

  /// Heure d’entrée effective dans la salle (compteur d’attente MM:SS).
  late final DateTime _roomEnteredAt;

  Timer? _tick;
  Timer? _validateTimer;
  StreamSubscription<bool>? _netSub;
  late AnimationController _dotPulse;
  late AnimationController _hourglassTurn;
  late AnimationController _urgentScale;
  /// Cercle principal qui pulse (agrandit / rétrécit).
  late AnimationController _roomPulse;

  static const _weekdays = [
    'lundi',
    'mardi',
    'mercredi',
    'jeudi',
    'vendredi',
    'samedi',
    'dimanche',
  ];
  static const _months = [
    'janvier',
    'février',
    'mars',
    'avril',
    'mai',
    'juin',
    'juillet',
    'août',
    'septembre',
    'octobre',
    'novembre',
    'décembre',
  ];

  @override
  void initState() {
    super.initState();
    _roomEnteredAt = DateTime.now();
    _roomPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _dotPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _hourglassTurn = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    _urgentScale = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _syncUrgentAnimation();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _syncUrgentAnimation();
      setState(() {});
    });
    _netSub = WebRtcService.instance.socketConnected.listen((_) {
      if (mounted) setState(() {});
    });
    final stillValid = widget.onConsultationStillValid;
    if (stillValid != null) {
      _validateTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
        if (!mounted) return;
        final ok = await stillValid();
        if (!mounted) return;
        if (ok) return;

        final inv = widget.onConsultationInvalidated;
        if (inv != null) await inv();
        if (!mounted) return;

        await showDialog<void>(
          context: context,
          barrierColor: Colors.black54,
          builder: (dialogCtx) => AlertDialog(
            backgroundColor: _cCard,
            title: const Text(
              'Consultation annulée',
              style: TextStyle(
                color: _cTextMain,
                fontWeight: FontWeight.w600,
              ),
            ),
            content: const Text(
              'La consultation a été annulée.',
              style: TextStyle(color: _cTextSec, height: 1.5),
            ),
            actions: [
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: _cAccent,
                  foregroundColor: _cBg,
                ),
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        if (!mounted) return;
        Navigator.of(context).pop();
      });
    }
    if (kIsWeb && widget.onSyncUnload != null) {
      registerPatientWaitingUnloadSync(widget.onSyncUnload!);
    }
    CallChatContext.waitingRoomRouteActive = true;
  }

  void _syncUrgentAnimation() {
    final s = _secondsUntilConsult();
    final urgent = s > 0 && s < 300;
    if (urgent) {
      if (!_urgentScale.isAnimating) {
        _urgentScale.repeat(reverse: true);
      }
    } else {
      _urgentScale.stop();
      _urgentScale.value = 0;
    }
  }

  @override
  void dispose() {
    CallChatContext.waitingRoomRouteActive = false;
    if (kIsWeb) {
      unregisterPatientWaitingUnloadSync();
    }
    _validateTimer?.cancel();
    _netSub?.cancel();
    _tick?.cancel();
    _dotPulse.dispose();
    _hourglassTurn.dispose();
    _urgentScale.dispose();
    _roomPulse.dispose();
    super.dispose();
  }

  String _formatElapsedWait() {
    final sec = DateTime.now().difference(_roomEnteredAt).inSeconds.clamp(0, 86400);
    final m = sec ~/ 60;
    final s = sec % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  int _secondsUntilConsult() {
    return widget.consultationTime.difference(DateTime.now()).inSeconds;
  }

  String _doctorInitials() {
    final parts =
        widget.doctorName.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      final s = parts[0];
      return s.length >= 2
          ? s.substring(0, 2).toUpperCase()
          : s.toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  String _formatConsultDateTime() {
    final l = widget.consultationTime.toLocal();
    final d = _weekdays[l.weekday - 1];
    final cap = '${d[0].toUpperCase()}${d.substring(1)}';
    final mon = _months[l.month - 1];
    final hh = l.hour.toString().padLeft(2, '0');
    final mm = l.minute.toString().padLeft(2, '0');
    return '$cap ${l.day} $mon ${l.year} à $hh:$mm';
  }

  double _progressSinceWindowOpen() {
    final open = widget.consultationTime.subtract(_windowBeforeConsult);
    final end = widget.consultationTime.add(_windowAfterConsult);
    final totalSec = end.difference(open).inSeconds;
    if (totalSec <= 0) return 1;
    final elapsed = DateTime.now().difference(open).inSeconds;
    return (elapsed / totalSec).clamp(0.0, 1.0);
  }

  String _countdownHms(int sec) {
    if (sec <= 0) return '00:00:00';
    final h = sec ~/ 3600;
    final m = (sec % 3600) ~/ 60;
    final s = sec % 60;
    return '${h.toString().padLeft(2, '0')}:'
        '${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')}';
  }

  Future<void> _confirmLeave() async {
    final ok = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cCard,
        title: const Text(
          'Quitter la salle d\'attente ?',
          style: TextStyle(
            color: _cTextMain,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: const Text(
          'Vous pourrez y revenir depuis le bandeau du chat tant que la consultation est prévue.',
          style: TextStyle(color: _cTextSec, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Rester', style: TextStyle(color: _cAccent)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _cDanger,
              foregroundColor: _cTextMain,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Quitter'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await widget.onLeaveRoom();
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final sec = _secondsUntilConsult();
    final netOk = WebRtcService.instance.isSocketConnected;
    final urgent = sec > 0 && sec < 300;
    final timerColor = urgent ? _cDanger : _cAccent;
    final progress = _progressSinceWindowOpen();

    return Scaffold(
      backgroundColor: _cBg,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: _cTextMain,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _cTextMain),
          onPressed: _confirmLeave,
        ),
        title: const Text(
          'Salle d\'attente',
          style: TextStyle(
            color: _cTextMain,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                const SizedBox(height: 8),
                Center(
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.92, end: 1.08).animate(
                      CurvedAnimation(
                        parent: _roomPulse,
                        curve: Curves.easeInOut,
                      ),
                    ),
                    child: Container(
                      width: 120,
                      height: 120,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _cAccent.withValues(alpha: 0.12),
                        border: Border.all(
                          color: _cAccent.withValues(alpha: 0.45),
                          width: 3,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _cAccent.withValues(alpha: 0.25),
                            blurRadius: 28,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.sensors_rounded,
                        size: 48,
                        color: _cAccent,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Vous êtes dans la salle d\'attente…',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _cTextMain,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Le médecin va vous rejoindre dans un instant',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _cTextSec,
                    fontSize: 15,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Temps d\'attente',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _cTextSec,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _formatElapsedWait(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _cAccent,
                    fontSize: 36,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'monospace',
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 28),
                if (!netOk)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _cCard,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _cBorder),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.wifi_off_rounded, color: Colors.orange.shade400),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Connexion interrompue — reconnexion en cours…',
                              style: TextStyle(color: _cTextSec, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // A. Carte médecin
                Column(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: _cAccent, width: 3),
                      ),
                      padding: const EdgeInsets.all(3),
                      child: CircleAvatar(
                        radius: 36,
                        backgroundColor: _cAvatarFallback,
                        backgroundImage: widget.doctorAvatarUrl != null &&
                                widget.doctorAvatarUrl!.isNotEmpty
                            ? NetworkImage(widget.doctorAvatarUrl!)
                            : null,
                        child: widget.doctorAvatarUrl == null ||
                                widget.doctorAvatarUrl!.isEmpty
                            ? Text(
                                _doctorInitials(),
                                style: const TextStyle(
                                  color: _cTextMain,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                ),
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      widget.doctorName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: _cTextMain,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        FadeTransition(
                          opacity: Tween<double>(begin: 0.4, end: 1).animate(
                            CurvedAnimation(parent: _dotPulse, curve: Curves.easeInOut),
                          ),
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: _cSuccess,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          netOk ? 'En ligne' : 'Connexion…',
                          style: TextStyle(
                            color: netOk ? _cSuccess : _cTextSec,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 28),

                // B. Compte à rebours
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                  decoration: BoxDecoration(
                    color: _cCard,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _cBorder),
                    boxShadow: [
                      BoxShadow(
                        color: _cAccent.withValues(alpha: 0.15),
                        blurRadius: 24,
                        spreadRadius: 0,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'Votre consultation commence dans',
                        style: TextStyle(
                          color: _cTextSec,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (sec <= 0)
                        const Text(
                          'L\'appel peut démarrer',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _cSuccess,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        )
                      else
                        ScaleTransition(
                          scale: urgent
                              ? Tween<double>(begin: 1.0, end: 1.02).animate(
                                  CurvedAnimation(
                                    parent: _urgentScale,
                                    curve: Curves.easeInOut,
                                  ),
                                )
                              : const AlwaysStoppedAnimation<double>(1),
                          child: Text(
                            _countdownHms(sec),
                            style: TextStyle(
                              fontSize: 52,
                              fontWeight: FontWeight.w700,
                              color: timerColor,
                              fontFamily: 'monospace',
                              letterSpacing: 2,
                            ),
                          ),
                        ),
                      const SizedBox(height: 20),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 6,
                          backgroundColor: _cBorder,
                          color: _cAccent,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _formatConsultDateTime(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: _cTextSec,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // C. Statut
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: _cCard,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _cBorder),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RotationTransition(
                        turns: _hourglassTurn,
                        child: const Icon(
                          Icons.hourglass_top_rounded,
                          color: _cAccent,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Vous êtes dans la salle d\'attente virtuelle',
                              style: TextStyle(
                                color: _cTextMain,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                height: 1.35,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Le médecin sera notifié de votre présence. '
                              'L\'appel démarrera automatiquement à l\'heure prévue.',
                              style: TextStyle(
                                color: _cTextSec,
                                fontSize: 13,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Quitter (bouton rouge plein en bas)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _confirmLeave(),
                    icon: const Icon(Icons.exit_to_app_rounded),
                    label: const Text(
                      'Quitter la salle d\'attente',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: _cDanger,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
