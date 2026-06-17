import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../headsapp_theme.dart';
import '../providers/call_provider.dart' show CallProvider, CallState;
import '../services/api_service.dart';
import '../services/call_chat_context.dart';
import '../widgets/prescription_form_sheet.dart';
import 'doctor_prescription_pdf_viewer_screen.dart';
import '../services/webrtc_service.dart';

/// Style du panneau « Signes vitaux » (cohérent avec le thème médecin).
abstract final class _VitalsPanelStyle {
  static const Color primary = HeadsAppColors.brandPrimary;
  static const Color bg = HeadsAppColors.surfaceAlt;
  static const Color surface = HeadsAppColors.surface;
  static const Color border = HeadsAppColors.border;
  static const Color textSecondary = HeadsAppColors.textSecondary;
  static const Color textPrimary = HeadsAppColors.textPrimary;
  static const Color error = HeadsAppColors.danger;
  static List<BoxShadow> get cardShadow => const [
        BoxShadow(
          color: Color(0x0D000000),
          blurRadius: 12,
          offset: Offset(0, 4),
        ),
      ];
}

class ActiveCallScreen extends StatefulWidget {
  const ActiveCallScreen({
    super.key,
    required this.callProvider,
    required this.displayName,
    this.isVideoCall = false,
    this.avatarUrl,
  });

  final CallProvider callProvider;
  final String displayName;
  final bool isVideoCall;
  final String? avatarUrl;

  @override
  State<ActiveCallScreen> createState() => _ActiveCallScreenState();
}

class _ActiveCallScreenState extends State<ActiveCallScreen> {
  bool _done = false;
  bool _vitalsPanelOpen = false;
  bool _graphOpen = false;
  bool _loadingVitals = false;
  String? _vitalsError;
  _VitalHistoryFilter _historyFilter = _VitalHistoryFilter.all;
  _VitalMetric _graphMetric = _VitalMetric.bloodPressure;
  _GraphRange _graphRange = _GraphRange.last24h;
  Timer? _vitalsRefreshTimer;
  List<_VitalPoint> _vitalPoints = <_VitalPoint>[];
  final GlobalKey _graphBoundaryKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    widget.callProvider.addListener(_onProviderUpdateSync);
    unawaited(_loadVitals());
    _vitalsRefreshTimer = Timer.periodic(
      const Duration(seconds: 12),
      (_) => _loadVitals(silent: true),
    );
  }

  @override
  void dispose() {
    widget.callProvider.removeListener(_onProviderUpdateSync);
    _vitalsRefreshTimer?.cancel();
    super.dispose();
  }

  void _onProviderUpdateSync() {
    unawaited(_onProviderUpdateAsync());
  }

  Future<void> _onProviderUpdateAsync() async {
    if (!mounted || _done) return;
    final s = widget.callProvider.currentState;
    if (s == CallState.termine ||
        s == CallState.refuse ||
        s == CallState.echec) {
      _done = true;
      final p = widget.callProvider;
      final navigator = Navigator.of(context);
      if (!navigator.mounted) return;
      CallChatContext.popCallStackWithNavigator(navigator);
      p.resetAfterCallUi();
    } else {
      setState(() {});
    }
  }

  String _qualityLabel(RTCPeerConnectionState s) {
    switch (s) {
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        return 'Connecté';
      case RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
        return 'Connexion...';
      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
        return 'Signal faible';
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        return 'Échec';
      default:
        return 'Connexion...';
    }
  }

  Color _qualityColor(RTCPeerConnectionState s) {
    switch (s) {
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        return Colors.green;
      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
        return Colors.orange;
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        return Colors.red;
      default:
        return Colors.blueGrey;
    }
  }

  bool get _showVitalsButton => !CallChatContext.isPatientSide;

  Future<void> _openLatestPrescription(BuildContext context) async {
    final cid = CallChatContext.conversationId?.trim();
    if (cid == null || cid.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Discussion non disponible.')),
      );
      return;
    }
    try {
      final data = await ApiService.getLatestPrescription(conversationId: cid);
      final pdfUrl = '${data['pdfUrl'] ?? ''}'.trim();
      if (pdfUrl.isEmpty) throw Exception('empty');
      final prescriptionId = '${data['prescriptionId'] ?? ''}'.trim();
      if (!context.mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => DoctorPrescriptionPdfViewerScreen(
            pdfUrl: pdfUrl,
            conversationId: cid,
            prescriptionId: prescriptionId.isEmpty ? null : prescriptionId,
          ),
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Aucune ordonnance disponible pour le moment.'),
        ),
      );
    }
  }

  void _openPrescriptionDuringCall(BuildContext context) {
    final cid = CallChatContext.conversationId?.trim();
    final did = CallChatContext.doctorId?.trim();
    final pnameFromCtx = CallChatContext.patientDisplayName?.trim() ?? '';
    final pname =
        pnameFromCtx.isNotEmpty ? pnameFromCtx : widget.displayName.trim();
    if (cid == null || cid.isEmpty || did == null || did.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Impossible d\'accéder à la discussion pour cette ordonnance.',
          ),
        ),
      );
      return;
    }
    unawaited(
      showDoctorPrescriptionFormBottomSheet(
        context,
        conversationId: cid,
        doctorId: did,
        patientName: pname,
        source: PrescriptionSendSource.teleconsult,
        consultationCallRoomId: widget.callProvider.roomId,
        onSent: CallChatContext.onReloadMessages,
      ),
    );
  }

  String? get _doctorId {
    final id = CallChatContext.doctorId?.trim() ?? '';
    return id.isEmpty ? null : id;
  }

  String? get _patientId {
    final id = CallChatContext.patientId?.trim() ?? '';
    return id.isEmpty ? null : id;
  }

  int? _toInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.round();
    if (v is String) return int.tryParse(v.trim());
    return null;
  }

  DateTime? _parseAt(Map<String, dynamic> row) {
    final keys = ['measuredAt', 'takenAt', 'createdAt', 'updatedAt', 'date'];
    for (final k in keys) {
      final raw = row[k];
      if (raw == null) continue;
      final dt = DateTime.tryParse(raw.toString());
      if (dt != null) return dt.toLocal();
    }
    return null;
  }

  _VitalPoint _mapRow(Map<String, dynamic> row) {
    final at = _parseAt(row) ?? DateTime.now();
    return _VitalPoint(
      at: at,
      systolic: _toInt(row['systolic']) ?? _toInt(row['tensionSystolique']),
      diastolic: _toInt(row['diastolic']) ?? _toInt(row['tensionDiastolique']),
      bpm: _toInt(row['heartRate']) ?? _toInt(row['bpm']) ?? _toInt(row['pulse']),
      spo2: _toInt(row['spo2']) ??
          _toInt(row['oxygenSaturation']) ??
          _toInt(row['saturationOxygene']),
    );
  }

  Future<void> _loadVitals({bool silent = false}) async {
    final doctorId = _doctorId;
    if (doctorId == null || doctorId.isEmpty) return;
    if (!silent) {
      setState(() {
        _loadingVitals = true;
        _vitalsError = null;
      });
    }
    try {
      final rows = await ApiService.getDoctorBloodPressureMeasurements(
        doctorId: doctorId,
      );
      final pid = _patientId;
      final filtered = rows.where((raw) {
        if (pid == null) return true;
        final r = Map<String, dynamic>.from(raw);
        final rowPid = (r['patientId'] ??
                r['patient']?['id'] ??
                r['patient']?['_id'] ??
                '')
            .toString();
        return rowPid == pid;
      }).map((e) => _mapRow(Map<String, dynamic>.from(e))).toList();
      filtered.sort((a, b) => b.at.compareTo(a.at));
      if (!mounted) return;
      setState(() {
        _vitalPoints = filtered;
        _loadingVitals = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _vitalsError = e.toString().replaceFirst('Exception: ', '');
        _loadingVitals = false;
      });
    }
  }

  _VitalPoint? get _latest => _vitalPoints.isEmpty ? null : _vitalPoints.first;

  _VitalStatus _bpStatus(int? sys, int? dia) {
    if (sys == null || dia == null) return _VitalStatus.normal;
    if (sys >= 140 || dia >= 90) return _VitalStatus.hypertension;
    if (sys < 90 || dia < 60) return _VitalStatus.hypotension;
    return _VitalStatus.normal;
  }

  _VitalStatus _hrStatus(int? bpm) {
    if (bpm == null) return _VitalStatus.normal;
    if (bpm > 100) return _VitalStatus.hypertension;
    if (bpm < 60) return _VitalStatus.hypotension;
    return _VitalStatus.normal;
  }

  _VitalStatus _spo2Status(int? spo2) {
    if (spo2 == null) return _VitalStatus.normal;
    if (spo2 < 92) return _VitalStatus.hypotension;
    if (spo2 > 100) return _VitalStatus.hypertension;
    return _VitalStatus.normal;
  }

  String _statusLabel(_VitalStatus s) {
    switch (s) {
      case _VitalStatus.hypotension:
        return 'Hypotension';
      case _VitalStatus.hypertension:
        return 'Hypertension';
      case _VitalStatus.normal:
        return 'Normal';
    }
  }

  Color _statusColor(_VitalStatus s) {
    switch (s) {
      case _VitalStatus.hypotension:
        return const Color(0xFF0EA5E9);
      case _VitalStatus.hypertension:
        return const Color(0xFFDC2626);
      case _VitalStatus.normal:
        return const Color(0xFF16A34A);
    }
  }

  List<_VitalHistoryRow> get _historyRows {
    final rows = <_VitalHistoryRow>[];
    for (final p in _vitalPoints) {
      if (p.systolic != null && p.diastolic != null) {
        rows.add(
          _VitalHistoryRow(
            at: p.at,
            metric: _VitalMetric.bloodPressure,
            value: '${p.systolic}/${p.diastolic} mmHg',
          ),
        );
      }
      if (p.bpm != null) {
        rows.add(
          _VitalHistoryRow(
            at: p.at,
            metric: _VitalMetric.heartRate,
            value: '${p.bpm} BPM',
          ),
        );
      }
      if (p.spo2 != null) {
        rows.add(
          _VitalHistoryRow(
            at: p.at,
            metric: _VitalMetric.spo2,
            value: '${p.spo2} %',
          ),
        );
      }
    }
    rows.sort((a, b) => b.at.compareTo(a.at));
    switch (_historyFilter) {
      case _VitalHistoryFilter.bp:
        return rows.where((r) => r.metric == _VitalMetric.bloodPressure).toList();
      case _VitalHistoryFilter.hr:
        return rows.where((r) => r.metric == _VitalMetric.heartRate).toList();
      case _VitalHistoryFilter.spo2:
        return rows.where((r) => r.metric == _VitalMetric.spo2).toList();
      case _VitalHistoryFilter.all:
        return rows;
    }
  }

  Duration get _graphDuration {
    switch (_graphRange) {
      case _GraphRange.lastHour:
        return const Duration(hours: 1);
      case _GraphRange.last24h:
        return const Duration(hours: 24);
      case _GraphRange.last7d:
        return const Duration(days: 7);
      case _GraphRange.last30d:
        return const Duration(days: 30);
    }
  }

  String _fmtAt(DateTime dt) {
    final d = dt.toLocal();
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  List<_GraphPoint> get _graphPoints {
    final cutoff = DateTime.now().subtract(_graphDuration);
    final points = <_GraphPoint>[];
    for (final p in _vitalPoints.reversed) {
      if (p.at.isBefore(cutoff)) continue;
      final y = switch (_graphMetric) {
        _VitalMetric.bloodPressure => (p.systolic ?? p.diastolic)?.toDouble(),
        _VitalMetric.heartRate => p.bpm?.toDouble(),
        _VitalMetric.spo2 => p.spo2?.toDouble(),
      };
      if (y == null) continue;
      points.add(_GraphPoint(x: p.at.millisecondsSinceEpoch.toDouble(), y: y));
    }
    return points;
  }

  String get _graphMetricLabel => switch (_graphMetric) {
        _VitalMetric.bloodPressure => 'Pression artérielle',
        _VitalMetric.heartRate => 'Fréquence cardiaque',
        _VitalMetric.spo2 => 'SpO2',
      };

  Future<void> _exportGraphPng() async {
    final ctx = _graphBoundaryKey.currentContext;
    if (ctx == null) return;
    final boundary = ctx.findRenderObject();
    if (boundary is! RenderRepaintBoundary) return;
    final img = await boundary.toImage(pixelRatio: 2.0);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    if (!mounted) return;
    if (data == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Export impossible pour le moment.')),
      );
      return;
    }
    final bytes = data.buffer.asUint8List();
    final uri = Uri.parse('data:image/png;base64,${base64Encode(bytes)}');
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'Image PNG ouverte (enregistrez-la depuis le navigateur).'
            : 'Impossible d’ouvrir le PNG exporté.'),
      ),
    );
  }

  Widget _vitalSectionHeader(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: _VitalsPanelStyle.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.25,
              color: _VitalsPanelStyle.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _vitalsInputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: _VitalsPanelStyle.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _VitalsPanelStyle.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _VitalsPanelStyle.primary, width: 1.5),
      ),
      isDense: true,
      labelStyle: const TextStyle(
        color: _VitalsPanelStyle.textSecondary,
        fontWeight: FontWeight.w600,
        fontSize: 12,
      ),
    );
  }

  Widget _buildMediaArea(
    bool hasRemoteStream,
    bool hasLocalStream,
    CallProvider provider,
    RTCPeerConnectionState quality,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          if (widget.isVideoCall)
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: hasRemoteStream
                            ? RTCVideoView(
                                WebRtcService.instance.remoteRenderer,
                                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                                mirror: false,
                              )
                            : const Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.videocam_off_rounded,
                                        color: Colors.white70, size: 34),
                                    SizedBox(height: 8),
                                    Text(
                                      'En attente de la vidéo distante...',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                      ),
                    ),
                  ),
                  if (hasLocalStream)
                    Positioned(
                      top: 12,
                      right: 12,
                      child: SizedBox(
                        width: 110,
                        height: 150,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: RTCVideoView(
                            WebRtcService.instance.localRenderer,
                            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                            mirror: true,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          if (!widget.isVideoCall) ...[
            const SizedBox(height: 24),
            CircleAvatar(
              radius: 46,
              backgroundImage: widget.avatarUrl != null && widget.avatarUrl!.isNotEmpty
                  ? NetworkImage(widget.avatarUrl!)
                  : null,
              child: widget.avatarUrl == null || widget.avatarUrl!.isEmpty
                  ? const Icon(Icons.person_rounded, size: 42)
                  : null,
            ),
            const SizedBox(height: 12),
          ],
          if (widget.isVideoCall) const SizedBox(height: 12),
          Text(
            widget.displayName,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            provider.formattedDuration(),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.circle, size: 10, color: _qualityColor(quality)),
              const SizedBox(width: 6),
              Text(_qualityLabel(quality)),
            ],
          ),
          const SizedBox(height: 20),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              _CallControlPill(
                icon: provider.isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                label: provider.isMuted ? 'Micro off' : 'Micro',
                onPressed: provider.toggleMute,
              ),
              _CallControlPill(
                icon: provider.speakerOn ? Icons.volume_up_rounded : Icons.hearing_rounded,
                label: 'Audio',
                onPressed: provider.toggleSpeaker,
              ),
              if (widget.isVideoCall)
                _CallControlPill(
                  icon: provider.cameraOn
                      ? Icons.videocam_rounded
                      : Icons.videocam_off_rounded,
                  label: provider.cameraOn ? 'Caméra' : 'Caméra off',
                  onPressed: provider.toggleCamera,
                ),
              if (_showVitalsButton)
                _CallControlPill(
                  icon: Icons.monitor_heart_rounded,
                  label: 'Signes vitaux',
                  active: _vitalsPanelOpen,
                  onPressed: () {
                    setState(() {
                      _vitalsPanelOpen = !_vitalsPanelOpen;
                    });
                  },
                ),
              _CallControlPill(
                icon: Icons.call_end_rounded,
                label: 'Raccrocher',
                danger: true,
                onPressed: () {
                  unawaited(provider.endCall());
                },
              ),
            ],
          ),
          if (!widget.isVideoCall && WebRtcService.instance.isRemoteRendererReady)
            SizedBox(
              width: 1,
              height: 1,
              child: RTCVideoView(
                WebRtcService.instance.remoteRenderer,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                mirror: false,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildVitalsPanel() {
    final latest = _latest;
    final bpStatus = _bpStatus(latest?.systolic, latest?.diastolic);
    final hrStatus = _hrStatus(latest?.bpm);
    final spo2Status = _spo2Status(latest?.spo2);
    final history = _historyRows.take(40).toList();
    final graphPoints = _graphPoints;
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFF8FBFD),
            _VitalsPanelStyle.bg,
          ],
        ),
      ),
      child: SafeArea(
        left: false,
        right: false,
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: LayoutBuilder(
            builder: (context, panelConstraints) {
              final compact = panelConstraints.maxHeight < 520;
              final historyHeight = compact ? 120.0 : 180.0;
              return ListView(
                padding: EdgeInsets.zero,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: _VitalsPanelStyle.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _VitalsPanelStyle.border),
                      boxShadow: _VitalsPanelStyle.cardShadow,
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _VitalsPanelStyle.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.monitor_heart_rounded,
                            color: _VitalsPanelStyle.primary,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Signes vitaux',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.3,
                                  color: _VitalsPanelStyle.textPrimary,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Données du patient pendant l’appel',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: _VitalsPanelStyle.textSecondary,
                                  height: 1.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Fermer',
                          style: IconButton.styleFrom(
                            foregroundColor: _VitalsPanelStyle.textSecondary,
                          ),
                          onPressed: () => setState(() => _vitalsPanelOpen = false),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_loadingVitals)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: const LinearProgressIndicator(
                        minHeight: 3,
                        color: _VitalsPanelStyle.primary,
                        backgroundColor: Color(0xFFE2E8F0),
                      ),
                    )
                  else
                    const SizedBox(height: 3),
                  if (_vitalsError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _VitalsPanelStyle.error.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _VitalsPanelStyle.error.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Text(
                          _vitalsError!,
                          style: const TextStyle(
                            color: _VitalsPanelStyle.error,
                            fontSize: 12,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 14),
                  _vitalSectionHeader(
                    'Temps réel',
                    'Dernières valeurs connues pour ce patient',
                  ),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _VitalsPanelStyle.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _VitalsPanelStyle.border),
                      boxShadow: _VitalsPanelStyle.cardShadow,
                    ),
                    child: Column(
                      children: [
                        _VitalCard(
                          title: 'Pression artérielle',
                          value: latest == null ||
                                  latest.systolic == null ||
                                  latest.diastolic == null
                              ? '— / — mmHg'
                              : '${latest.systolic} / ${latest.diastolic} mmHg',
                          statusLabel: _statusLabel(bpStatus),
                          statusColor: _statusColor(bpStatus),
                          icon: Icons.favorite_border_rounded,
                        ),
                        const Divider(height: 20, color: _VitalsPanelStyle.border),
                        _VitalCard(
                          title: 'Fréquence cardiaque',
                          value: latest?.bpm == null ? '— BPM' : '${latest!.bpm} BPM',
                          statusLabel: _statusLabel(hrStatus),
                          statusColor: _statusColor(hrStatus),
                          icon: Icons.favorite_rounded,
                          pulse: true,
                        ),
                        const Divider(height: 20, color: _VitalsPanelStyle.border),
                        _VitalCard(
                          title: 'Saturation SpO₂',
                          value: latest?.spo2 == null ? '— %' : '${latest!.spo2} %',
                          statusLabel: _statusLabel(spo2Status),
                          statusColor: _statusColor(spo2Status),
                          icon: Icons.air_rounded,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  _vitalSectionHeader(
                    'Historique',
                    'Mesures récentes, filtrables par indicateur',
                  ),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        _FilterChip(
                          label: 'Tout',
                          selected: _historyFilter == _VitalHistoryFilter.all,
                          onTap: () =>
                              setState(() => _historyFilter = _VitalHistoryFilter.all),
                        ),
                        _FilterChip(
                          label: 'Pression artérielle',
                          selected: _historyFilter == _VitalHistoryFilter.bp,
                          onTap: () =>
                              setState(() => _historyFilter = _VitalHistoryFilter.bp),
                        ),
                        _FilterChip(
                          label: 'Fréquence cardiaque',
                          selected: _historyFilter == _VitalHistoryFilter.hr,
                          onTap: () =>
                              setState(() => _historyFilter = _VitalHistoryFilter.hr),
                        ),
                        _FilterChip(
                          label: 'SpO₂',
                          selected: _historyFilter == _VitalHistoryFilter.spo2,
                          onTap: () =>
                              setState(() => _historyFilter = _VitalHistoryFilter.spo2),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: historyHeight,
                    child: Container(
                      decoration: BoxDecoration(
                        color: _VitalsPanelStyle.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: _VitalsPanelStyle.border),
                        boxShadow: _VitalsPanelStyle.cardShadow,
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: history.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text(
                                  'Aucune mesure enregistrée pour le moment.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: _VitalsPanelStyle.textSecondary.withValues(
                                      alpha: 0.9,
                                    ),
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              itemCount: history.length,
                              separatorBuilder: (context, index) => const Divider(
                                height: 1,
                                indent: 56,
                                color: _VitalsPanelStyle.border,
                              ),
                              itemBuilder: (context, i) {
                                final h = history[i];
                                final color = switch (h.metric) {
                                  _VitalMetric.bloodPressure =>
                                    _VitalsPanelStyle.primary,
                                  _VitalMetric.heartRate =>
                                    const Color(0xFFDC2626),
                                  _VitalMetric.spo2 => const Color(0xFF0891B2),
                                };
                                final label = switch (h.metric) {
                                  _VitalMetric.bloodPressure => 'PA',
                                  _VitalMetric.heartRate => 'FC',
                                  _VitalMetric.spo2 => 'O₂',
                                };
                                return ListTile(
                                  dense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 2,
                                  ),
                                  title: Text(
                                    h.value,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      color: _VitalsPanelStyle.textPrimary,
                                    ),
                                  ),
                                  subtitle: Text(
                                    _fmtAt(h.at),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: _VitalsPanelStyle.textSecondary,
                                    ),
                                  ),
                                  leading: CircleAvatar(
                                    radius: 16,
                                    backgroundColor: color.withValues(alpha: 0.12),
                                    child: Text(
                                      label,
                                      style: TextStyle(
                                        color: color,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  _vitalSectionHeader(
                    'Courbe',
                    'Visualiser l’évolution dans le temps',
                  ),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: _VitalsPanelStyle.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    onPressed: () => setState(() => _graphOpen = !_graphOpen),
                    icon: Icon(
                      _graphOpen
                          ? Icons.expand_less_rounded
                          : Icons.show_chart_rounded,
                    ),
                    label: Text(
                      _graphOpen ? 'Masquer le graphe' : 'Générer un graphe',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
              AnimatedSize(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: !_graphOpen
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: _VitalsPanelStyle.surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: _VitalsPanelStyle.border),
                            boxShadow: _VitalsPanelStyle.cardShadow,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: DropdownButtonFormField<_VitalMetric>(
                                      initialValue: _graphMetric,
                                      decoration: _vitalsInputDecoration('Indicateur'),
                                      items: const [
                                        DropdownMenuItem(
                                          value: _VitalMetric.bloodPressure,
                                          child: Text('Pression artérielle'),
                                        ),
                                        DropdownMenuItem(
                                          value: _VitalMetric.heartRate,
                                          child: Text('Fréquence cardiaque'),
                                        ),
                                        DropdownMenuItem(
                                          value: _VitalMetric.spo2,
                                          child: Text('SpO₂'),
                                        ),
                                      ],
                                      onChanged: (v) {
                                        if (v != null) setState(() => _graphMetric = v);
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: DropdownButtonFormField<_GraphRange>(
                                      initialValue: _graphRange,
                                      decoration: _vitalsInputDecoration('Période'),
                                      items: const [
                                        DropdownMenuItem(
                                          value: _GraphRange.lastHour,
                                          child: Text('Dernière heure'),
                                        ),
                                        DropdownMenuItem(
                                          value: _GraphRange.last24h,
                                          child: Text('24 heures'),
                                        ),
                                        DropdownMenuItem(
                                          value: _GraphRange.last7d,
                                          child: Text('7 jours'),
                                        ),
                                        DropdownMenuItem(
                                          value: _GraphRange.last30d,
                                          child: Text('30 jours'),
                                        ),
                                      ],
                                      onChanged: (v) {
                                        if (v != null) setState(() => _graphRange = v);
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              RepaintBoundary(
                                key: _graphBoundaryKey,
                                child: Container(
                                  height: 176,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFAFBFC),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: _VitalsPanelStyle.border),
                                  ),
                                  child: graphPoints.length < 2
                                      ? Center(
                                          child: Text(
                                            'Pas assez de points pour afficher une courbe sur cette période.',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize: 13,
                                              height: 1.35,
                                              color: _VitalsPanelStyle.textSecondary
                                                  .withValues(alpha: 0.95),
                                            ),
                                          ),
                                        )
                                      : CustomPaint(
                                          painter: _GraphPainter(
                                            points: graphPoints,
                                            color: switch (_graphMetric) {
                                              _VitalMetric.bloodPressure =>
                                                _VitalsPanelStyle.primary,
                                              _VitalMetric.heartRate =>
                                                const Color(0xFFDC2626),
                                              _VitalMetric.spo2 =>
                                                const Color(0xFF0891B2),
                                            },
                                          ),
                                          child: Align(
                                            alignment: Alignment.topLeft,
                                            child: Text(
                                              _graphMetricLabel,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w800,
                                                color: _VitalsPanelStyle.textPrimary,
                                                letterSpacing: -0.2,
                                              ),
                                            ),
                                          ),
                                        ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: _VitalsPanelStyle.textPrimary,
                                  side: const BorderSide(color: _VitalsPanelStyle.border),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                onPressed:
                                    graphPoints.length < 2 ? null : _exportGraphPng,
                                icon: const Icon(Icons.download_rounded, size: 20),
                                label: const Text(
                                  'Exporter le graphe (PNG)',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
              ),
              const SizedBox(height: 8),
              ],
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = widget.callProvider;
    final quality = provider.connectionState;
    final appBarTitle =
        widget.isVideoCall ? 'Appel vidéo' : 'Appel audio';
    final hasRemoteRenderer =
        widget.isVideoCall && WebRtcService.instance.isRemoteRendererReady;
    final hasLocalRenderer =
        widget.isVideoCall && WebRtcService.instance.isLocalRendererReady;
    final hasRemoteStream =
        hasRemoteRenderer &&
        WebRtcService.instance.remoteRenderer.srcObject != null;
    final hasLocalStream =
        hasLocalRenderer &&
        WebRtcService.instance.localRenderer.srcObject != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(appBarTitle),
        actions: _showVitalsButton
            ? [
                IconButton(
                  tooltip: 'Voir la dernière ordonnance',
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  onPressed: () => unawaited(_openLatestPrescription(context)),
                ),
              ]
            : const [],
      ),
      floatingActionButton: _showVitalsButton &&
              provider.currentState == CallState.enAppel
          ? FloatingActionButton.extended(
              heroTag: 'doctor_prescription_fab',
              backgroundColor: HeadsAppColors.brandPrimary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.medical_information_rounded),
              label: const Text('Ordonnance'),
              onPressed: () => _openPrescriptionDuringCall(context),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isSmall = constraints.maxWidth < 980;
          final media = _buildMediaArea(
            hasRemoteStream,
            hasLocalStream,
            provider,
            quality,
          );
          if (isSmall) {
            return Stack(
              children: [
                Positioned.fill(child: media),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: AnimatedSlide(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    offset: _vitalsPanelOpen
                        ? Offset.zero
                        : const Offset(0, 1.04),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      height: constraints.maxHeight * 0.6,
                      decoration: BoxDecoration(
                        color: _VitalsPanelStyle.bg,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(20),
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x22000000),
                            blurRadius: 20,
                            offset: Offset(0, -4),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: _buildVitalsPanel(),
                    ),
                  ),
                ),
              ],
            );
          }
          final panelWidth = _vitalsPanelOpen ? constraints.maxWidth * 0.35 : 0.0;
          return Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                width: math.max(0, constraints.maxWidth - panelWidth),
                child: media,
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                width: panelWidth,
                child: panelWidth < 2
                    ? const SizedBox.shrink()
                    : _buildVitalsPanel(),
              ),
            ],
          );
        },
      ),
    );
  }
}

enum _VitalStatus { normal, hypotension, hypertension }

enum _VitalHistoryFilter { all, bp, hr, spo2 }

enum _VitalMetric { bloodPressure, heartRate, spo2 }

enum _GraphRange { lastHour, last24h, last7d, last30d }

class _VitalPoint {
  _VitalPoint({
    required this.at,
    this.systolic,
    this.diastolic,
    this.bpm,
    this.spo2,
  });

  final DateTime at;
  final int? systolic;
  final int? diastolic;
  final int? bpm;
  final int? spo2;
}

class _VitalHistoryRow {
  _VitalHistoryRow({
    required this.at,
    required this.metric,
    required this.value,
  });

  final DateTime at;
  final _VitalMetric metric;
  final String value;
}

class _GraphPoint {
  _GraphPoint({required this.x, required this.y});
  final double x;
  final double y;
}

class _CallControlPill extends StatelessWidget {
  const _CallControlPill({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.active = false,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool active;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color bg = danger
        ? const Color(0xFFDC2626)
        : active
            ? const Color(0xFF0EA5E9)
            : const Color(0xFFEFF6FF);
    final Color fg = danger || active ? Colors.white : const Color(0xFF1E293B);
    final borderColor = danger
        ? const Color(0xFFB91C1C)
        : active
            ? const Color(0xFF0284C7)
            : const Color(0xFFBFDBFE);
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: fg,
        minimumSize: const Size(132, 44),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: borderColor),
        ),
        textStyle: theme.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
        ),
        elevation: danger || active ? 1 : 0,
      ),
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}

class _VitalCard extends StatefulWidget {
  const _VitalCard({
    required this.title,
    required this.value,
    required this.statusLabel,
    required this.statusColor,
    required this.icon,
    this.pulse = false,
  });

  final String title;
  final String value;
  final String statusLabel;
  final Color statusColor;
  final IconData icon;
  final bool pulse;

  @override
  State<_VitalCard> createState() => _VitalCardState();
}

class _VitalCardState extends State<_VitalCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _VitalsPanelStyle.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(widget.icon, color: _VitalsPanelStyle.primary, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _VitalsPanelStyle.textSecondary,
                    letterSpacing: 0.1,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    if (widget.pulse)
                      FadeTransition(
                        opacity: Tween<double>(begin: 0.45, end: 1).animate(_c),
                        child: const Padding(
                          padding: EdgeInsets.only(right: 6),
                          child: Icon(
                            Icons.favorite_rounded,
                            color: Color(0xFFDC2626),
                            size: 16,
                          ),
                        ),
                      ),
                    Flexible(
                      child: Text(
                        widget.value,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 19,
                          letterSpacing: -0.4,
                          color: _VitalsPanelStyle.textPrimary,
                          height: 1.15,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            constraints: const BoxConstraints(minWidth: 88),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: widget.statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: widget.statusColor.withValues(alpha: 0.22),
              ),
            ),
            child: Text(
              widget.statusLabel,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: widget.statusColor,
                fontWeight: FontWeight.w800,
                fontSize: 11,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: selected
                  ? _VitalsPanelStyle.primary.withValues(alpha: 0.14)
                  : _VitalsPanelStyle.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected
                    ? _VitalsPanelStyle.primary.withValues(alpha: 0.45)
                    : _VitalsPanelStyle.border,
                width: selected ? 1.5 : 1,
              ),
              boxShadow: selected ? _VitalsPanelStyle.cardShadow : null,
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: selected
                    ? _VitalsPanelStyle.primary
                    : _VitalsPanelStyle.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GraphPainter extends CustomPainter {
  _GraphPainter({required this.points, required this.color});
  final List<_GraphPoint> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final minX = points.first.x;
    final maxX = points.last.x;
    final minY = points.map((e) => e.y).reduce(math.min);
    final maxY = points.map((e) => e.y).reduce(math.max);
    final spanX = (maxX - minX).abs() < 1 ? 1 : (maxX - minX);
    final spanY = (maxY - minY).abs() < 1 ? 1 : (maxY - minY);
    final chartRect = Rect.fromLTWH(0, 18, size.width, size.height - 24);

    final grid = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..strokeWidth = 1;
    for (int i = 0; i < 4; i++) {
      final y = chartRect.top + (chartRect.height * i / 3);
      canvas.drawLine(Offset(chartRect.left, y), Offset(chartRect.right, y), grid);
    }

    final line = Paint()
      ..color = color
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke;
    final fill = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withValues(alpha: 0.25), color.withValues(alpha: 0.02)],
      ).createShader(chartRect);

    final path = Path();
    for (int i = 0; i < points.length; i++) {
      final p = points[i];
      final dx = chartRect.left + ((p.x - minX) / spanX) * chartRect.width;
      final dy = chartRect.bottom - ((p.y - minY) / spanY) * chartRect.height;
      if (i == 0) {
        path.moveTo(dx, dy);
      } else {
        path.lineTo(dx, dy);
      }
    }
    final area = Path.from(path)
      ..lineTo(chartRect.right, chartRect.bottom)
      ..lineTo(chartRect.left, chartRect.bottom)
      ..close();

    canvas.drawPath(area, fill);
    canvas.drawPath(path, line);
  }

  @override
  bool shouldRepaint(covariant _GraphPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.color != color;
}
