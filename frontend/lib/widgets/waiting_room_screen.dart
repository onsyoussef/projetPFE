import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/call_chat_context.dart';
import '../services/permission_service.dart';
import '../services/webrtc_service.dart';
import '../headsapp_theme.dart';
import '../utils/patient_ui_utils.dart';
import '../utils/waiting_room_unload.dart';

const Color _pageBg = Color(0xFFF5F7FA);
const Color _navy = Color(0xFF1A458B);
const Color _primaryBlue = Color(0xFF155EEF);
const Color _textDark = Color(0xFF111827);
const Color _textGrey = Color(0xFF6B7280);
const Color _cardGrey = Color(0xFFF3F4F6);
const Color _onlineGreen = Color(0xFF22C55E);
const Color _danger = Color(0xFFEF4444);

/// Écran plein : attente du médecin, compte à rebours, option quitter.
class WaitingRoomScreen extends StatefulWidget {
  const WaitingRoomScreen({
    super.key,
    required this.consultationTime,
    required this.doctorName,
    this.doctorSpecialty,
    this.doctorAvatarUrl,
    required this.onLeaveRoom,
    this.onSyncUnload,
    this.onConsultationStillValid,
    this.onConsultationInvalidated,
  });

  final DateTime consultationTime;
  final String doctorName;
  final String? doctorSpecialty;
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
  static const _windowBeforeConsult = Duration(minutes: 10);
  static const _windowAfterConsult = Duration(minutes: 10);

  late final DateTime _roomEnteredAt;

  Timer? _tick;
  Timer? _validateTimer;
  StreamSubscription<bool>? _netSub;
  int _connectionDotPhase = 0;

  @override
  void initState() {
    super.initState();
    _roomEnteredAt = DateTime.now();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _connectionDotPhase = (_connectionDotPhase + 1) % 4);
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
            title: const Text('Consultation annulée'),
            content: const Text(
              'La consultation a été annulée.',
              style: TextStyle(height: 1.5),
            ),
            actions: [
              FilledButton(
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

  @override
  void dispose() {
    CallChatContext.waitingRoomRouteActive = false;
    if (kIsWeb) {
      unregisterPatientWaitingUnloadSync();
    }
    _validateTimer?.cancel();
    _netSub?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  String _doctorDisplayName() {
    final name = readableDoctorName(widget.doctorName);
    final lower = name.toLowerCase();
    if (lower.startsWith('dr.') || lower.startsWith('dr ')) return name;
    return 'Dr. $name';
  }

  String _formatAppointmentClock() {
    final l = widget.consultationTime.toLocal();
    final hh = l.hour.toString().padLeft(2, '0');
    final mm = l.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  String _estimatedWaitLabel(int secUntilConsult) {
    if (secUntilConsult <= 0) return 'Bientôt';
    final min = (secUntilConsult / 60).ceil().clamp(1, 99);
    return '~ $min min';
  }

  String _connectionStatusText(bool netOk) {
    if (!netOk) return 'Reconnexion en cours';
    return 'Connexion en cours${'.' * _connectionDotPhase}';
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

  Future<void> _confirmLeave() async {
    final ok = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => AlertDialog(
        title: const Text('Quitter la salle d\'attente ?'),
        content: const Text(
          'Vous pourrez y revenir depuis le bandeau du chat tant que la consultation est prévue.',
          style: TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Rester'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _danger),
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

  Future<void> _testMicAndCamera() async {
    final ok = await PermissionService.instance
        .ensureCameraAndMicrophonePermissions(context);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Microphone et caméra sont prêts pour la consultation.'
              : 'Autorisez le micro et la caméra dans les paramètres.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _reportProblem() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Pour signaler un problème, contactez le support HeadsApp depuis Paramètres.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sec = _secondsUntilConsult();
    final netOk = WebRtcService.instance.isSocketConnected;
    final specialty = readableDecryptedField(widget.doctorSpecialty?.toString());

    return Scaffold(
      backgroundColor: _pageBg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              children: [
                Row(
                  children: [
                    Text(
                      'HeadsApp',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: _navy,
                            fontWeight: FontWeight.w800,
                            fontSize: 22,
                            letterSpacing: -0.3,
                          ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: _confirmLeave,
                      icon: const Icon(Icons.close_rounded, color: _textGrey),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Salle d\'attente',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: _textDark,
                        fontSize: 26,
                        letterSpacing: -0.4,
                      ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: _primaryBlue,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'SESSION ACTIVE',
                      style: TextStyle(
                        color: _primaryBlue,
                        fontWeight: FontWeight.w800,
                        fontSize: 11.5,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _PractitionerCard(
                  doctorName: _doctorDisplayName(),
                  specialty: specialty,
                  avatarUrl: widget.doctorAvatarUrl,
                  initials: _doctorInitials(),
                  isOnline: netOk,
                ),
                const SizedBox(height: 18),
                _MainWaitingCard(
                  connectionText: _connectionStatusText(netOk),
                  secUntilConsult: sec,
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _InfoChipCard(
                        icon: Icons.schedule_rounded,
                        label: 'RENDEZ-VOUS',
                        value: _formatAppointmentClock(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _InfoChipCard(
                        icon: Icons.hourglass_top_rounded,
                        label: 'ATTENTE',
                        value: _estimatedWaitLabel(sec),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    gradient: HeadsAppColors.primaryButtonGradient,
                    boxShadow: [
                      BoxShadow(
                        color: HeadsAppColors.authGradientEnd.withValues(alpha: 0.25),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _confirmLeave,
                      borderRadius: BorderRadius.circular(999),
                      child: const SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Quitter la salle d\'attente',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                            SizedBox(width: 8),
                            Icon(
                              Icons.logout_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: OutlinedButton.icon(
                    onPressed: _testMicAndCamera,
                    icon: const Icon(Icons.tune_rounded, color: _navy, size: 20),
                    label: const Text(
                      'Tester micro et caméra',
                      style: TextStyle(
                        color: _navy,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: _cardGrey,
                      side: BorderSide.none,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                TextButton.icon(
                  onPressed: _reportProblem,
                  icon: Icon(Icons.info_outline_rounded, size: 18, color: Colors.grey.shade500),
                  label: Text(
                    'Signaler un problème',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '© ${DateTime.now().year} HeadsApp. Tous droits réservés.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey.shade400,
                    fontSize: 11,
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

class _PractitionerCard extends StatelessWidget {
  const _PractitionerCard({
    required this.doctorName,
    required this.specialty,
    required this.avatarUrl,
    required this.initials,
    required this.isOnline,
  });

  final String doctorName;
  final String specialty;
  final String? avatarUrl;
  final String initials;
  final bool isOnline;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                radius: 34,
                backgroundColor: const Color(0xFFE8F0FE),
                backgroundImage: avatarUrl != null && avatarUrl!.isNotEmpty
                    ? NetworkImage(avatarUrl!)
                    : null,
                child: avatarUrl == null || avatarUrl!.isEmpty
                    ? Text(
                        initials,
                        style: const TextStyle(
                          color: _navy,
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
                      )
                    : null,
              ),
              if (isOnline)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: _onlineGreen,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2.5),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'VOTRE PRATICIEN',
                  style: TextStyle(
                    color: _primaryBlue,
                    fontWeight: FontWeight.w800,
                    fontSize: 10.5,
                    letterSpacing: 0.7,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  doctorName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _textDark,
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                  ),
                ),
                const SizedBox(height: 4),
                RichText(
                  text: TextSpan(
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
                    children: [
                      TextSpan(
                        text: specialty.isNotEmpty ? specialty : 'Médecin',
                        style: const TextStyle(color: _textGrey),
                      ),
                      TextSpan(
                        text: ' • ${isOnline ? 'En ligne' : 'Connexion…'}',
                        style: TextStyle(
                          color: isOnline ? _onlineGreen : _textGrey,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MainWaitingCard extends StatelessWidget {
  const _MainWaitingCard({
    required this.connectionText,
    required this.secUntilConsult,
  });

  final String connectionText;
  final int secUntilConsult;

  @override
  Widget build(BuildContext context) {
    final mainMessage = secUntilConsult <= 0
        ? 'Votre médecin peut vous rejoindre.'
        : 'Votre médecin vous rejoindra bientôt.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 28, 22, 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF2563EB),
            Color(0xFF155EEF),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: _primaryBlue.withValues(alpha: 0.35),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const Positioned.fill(
            child: CustomPaint(
              painter: _WaitingWavePainter(),
            ),
          ),
          Column(
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.18),
                ),
                child: const Icon(
                  Icons.videocam_rounded,
                  color: Colors.white,
                  size: 36,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                mainMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Veuillez patienter, la consultation va commencer automatiquement.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 13.5,
                  height: 1.45,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 22),
              Text(
                connectionText,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.88),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WaitingWavePainter extends CustomPainter {
  const _WaitingWavePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    for (var i = 0; i < 2; i++) {
      final path = Path();
      final baseY = size.height * (0.35 + i * 0.18);
      path.moveTo(0, baseY);
      for (double x = 0; x <= size.width; x += 8) {
        final y = baseY + math.sin((x / size.width) * math.pi * 3 + i) * 10;
        path.lineTo(x, y);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _InfoChipCard extends StatelessWidget {
  const _InfoChipCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: _cardGrey,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: _primaryBlue, size: 20),
          const SizedBox(height: 10),
          Text(
            label,
            style: const TextStyle(
              color: _textGrey,
              fontWeight: FontWeight.w700,
              fontSize: 10,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: _textDark,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
        ],
      ),
    );
  }
}
