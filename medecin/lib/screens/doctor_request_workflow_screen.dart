import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../headsapp_theme.dart';
import '../services/api_service.dart';
import '../teleconsult_first_request_letter.dart';
import '../utils/doctor_ui_utils.dart';

const Color _screenBg = Color(0xFFF5F9FC);
const Color _headerBlue = Color(0xFF2459A8);
const Color _ctaBlue = Color(0xFF0066FF);

String _requestStatusLabel(String api) {
  switch (api) {
    case 'accepted':
      return 'Acceptée';
    case 'rejected':
      return 'Refusée';
    default:
      return 'En attente';
  }
}

String _requestSubtitle(String status) {
  switch (status) {
    case 'accepted':
      return 'Demande acceptée';
    case 'rejected':
      return 'Demande refusée';
    default:
      return 'Nouveau Patient';
  }
}

/// Liste des demandes de téléconsultation.
class DoctorTeleconsultRequestsScreen extends StatefulWidget {
  const DoctorTeleconsultRequestsScreen({
    super.key,
    required this.doctorId,
    this.onRefreshHome,
    this.onListConsulted,
  });

  final String doctorId;
  final Future<void> Function()? onRefreshHome;
  final VoidCallback? onListConsulted;

  @override
  State<DoctorTeleconsultRequestsScreen> createState() =>
      _DoctorTeleconsultRequestsScreenState();
}

class _DoctorTeleconsultRequestsScreenState
    extends State<DoctorTeleconsultRequestsScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.doctorId.isEmpty) {
      setState(() {
        _loading = false;
        _items = [];
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list =
          await ApiService.getDoctorTeleconsultRequests(widget.doctorId);
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
      });
      if (mounted) widget.onListConsulted?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _openDetail(Map<String, dynamic> item) async {
    final id = item['id']?.toString() ?? '';
    if (id.isEmpty) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => DoctorTeleconsultRequestDetailScreen(
          doctorId: widget.doctorId,
          requestId: id,
        ),
      ),
    );
    if (changed == true && mounted) {
      await _load();
      await widget.onRefreshHome?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = _items
        .where((it) => (it['status']?.toString() ?? 'pending') == 'pending')
        .toList();
    final others = _items
        .where((it) => (it['status']?.toString() ?? 'pending') != 'pending')
        .toList();

    return Scaffold(
      backgroundColor: _screenBg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _HeadsAppBackHeader(title: 'Demande'),
            Divider(
              height: 1,
              thickness: 1,
              color: HeadsAppColors.border.withValues(alpha: 0.8),
            ),
            Expanded(
              child: RefreshIndicator(
                color: HeadsAppColors.brandPrimary,
                onRefresh: () async {
                  await _load();
                  await widget.onRefreshHome?.call();
                },
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: HeadsAppColors.brandPrimary,
                        ),
                      )
                    : _error != null
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.all(24),
                            children: [
                              Text(_error!, textAlign: TextAlign.center),
                            ],
                          )
                        : _items.isEmpty
                            ? ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.all(24),
                                children: const [
                                  SizedBox(height: 48),
                                  Text(
                                    'Aucune demande reçue pour le moment.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: HeadsAppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              )
                            : ListView(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 16, 16, 24),
                                children: [
                                  const Text(
                                    'Demandes Entrantes',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      color: HeadsAppColors.textPrimary,
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  if (pending.isEmpty)
                                    const _EmptyNotice(
                                      text:
                                          'Aucune demande entrante pour le moment.',
                                    )
                                  else
                                    ...pending.map(
                                      (it) => Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 12),
                                        child: _IncomingRequestCard(
                                          patientName: readablePatientName(
                                            it['patientName']?.toString(),
                                          ),
                                          patientPhotoPath:
                                              it['patientPhotoPath']?.toString(),
                                          subtitle: _requestSubtitle(
                                            it['status']?.toString() ??
                                                'pending',
                                          ),
                                          onDetails: () => _openDetail(it),
                                        ),
                                      ),
                                    ),
                                  if (others.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    const Text(
                                      'Historique',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                        color: HeadsAppColors.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    ...others.map(
                                      (it) => Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 12),
                                        child: _IncomingRequestCard(
                                          patientName: readablePatientName(
                                            it['patientName']?.toString(),
                                          ),
                                          patientPhotoPath:
                                              it['patientPhotoPath']?.toString(),
                                          subtitle: _requestSubtitle(
                                            it['status']?.toString() ??
                                                'pending',
                                          ),
                                          onDetails: () => _openDetail(it),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeadsAppBackHeader extends StatelessWidget {
  const _HeadsAppBackHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            color: _headerBlue,
          ),
          Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: _headerBlue,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _IncomingRequestCard extends StatelessWidget {
  const _IncomingRequestCard({
    required this.patientName,
    required this.patientPhotoPath,
    required this.subtitle,
    required this.onDetails,
  });

  final String patientName;
  final String? patientPhotoPath;
  final String subtitle;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          patientAvatarForDoctor(
            name: patientName,
            patientPhotoPath: patientPhotoPath,
            radius: 26,
            backgroundColor: HeadsAppColors.brandHighlight,
            accentColor: HeadsAppColors.brandPrimary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  patientName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: HeadsAppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    color: HeadsAppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(
            onPressed: onDetails,
            style: FilledButton.styleFrom(
              backgroundColor: _ctaBlue,
              foregroundColor: Colors.white,
              elevation: 0,
              minimumSize: const Size(88, 40),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              textStyle: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            child: const Text('Détails'),
          ),
        ],
      ),
    );
  }
}

class _EmptyNotice extends StatelessWidget {
  const _EmptyNotice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: HeadsAppColors.border),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: HeadsAppColors.textSecondary),
      ),
    );
  }
}

class DoctorTeleconsultRequestDetailScreen extends StatefulWidget {
  const DoctorTeleconsultRequestDetailScreen({
    super.key,
    required this.doctorId,
    required this.requestId,
  });

  final String doctorId;
  final String requestId;

  @override
  State<DoctorTeleconsultRequestDetailScreen> createState() =>
      _DoctorTeleconsultRequestDetailScreenState();
}

class _DoctorTeleconsultRequestDetailScreenState
    extends State<DoctorTeleconsultRequestDetailScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await ApiService.getTeleconsultRequestForDoctor(
        requestId: widget.requestId,
        doctorId: widget.doctorId,
      );
      if (!mounted) return;
      setState(() {
        _data = d;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _decide(bool accept, {String? rejectionMotif}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ApiService.decideTeleconsultRequest(
        requestId: widget.requestId,
        doctorId: widget.doctorId,
        accept: accept,
        rejectionMotif: rejectionMotif,
      );
      if (!mounted) return;
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              accept
                  ? 'Demande acceptée — le patient a été notifié'
                  : 'Demande refusée — le patient a été notifié',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _promptRejectAndDecide() async {
    if (_busy) return;
    final motifCtrl = TextEditingController();
    bool? confirmed;
    try {
      confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => Dialog(
          backgroundColor: Colors.white,
          insetPadding: const EdgeInsets.symmetric(horizontal: 28),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Confirmer le refus',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: HeadsAppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Voulez-vous vraiment refuser cette demande ?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: HeadsAppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: motifCtrl,
                  decoration: InputDecoration(
                    labelText: 'Motif du refus (optionnel)',
                    filled: true,
                    fillColor: const Color(0xFFF2F4F7),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                ),
                const SizedBox(height: 18),
                SizedBox(
                  height: 46,
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    style: TextButton.styleFrom(
                      backgroundColor: const Color(0xFFF2F4F7),
                      foregroundColor: HeadsAppColors.textPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Annuler',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 46,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: FilledButton.styleFrom(
                      backgroundColor: HeadsAppColors.danger,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Confirmer le refus',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } finally {
      if (confirmed != true) {
        motifCtrl.dispose();
      }
    }
    if (confirmed != true || !mounted) return;
    final motif = motifCtrl.text.trim();
    motifCtrl.dispose();
    await _decide(false, rejectionMotif: motif.isEmpty ? null : motif);
  }

  @override
  Widget build(BuildContext context) {
    final status = _data?['status']?.toString() ?? 'pending';
    final pending = status == 'pending';
    final patientName =
        readablePatientName(_data?['patientName']?.toString());

    return Scaffold(
      backgroundColor: _screenBg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                    color: _headerBlue,
                  ),
                  const Text(
                    'Détail de la demande',
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
            Divider(
              height: 1,
              thickness: 1,
              color: HeadsAppColors.border.withValues(alpha: 0.8),
            ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: HeadsAppColors.brandPrimary,
                      ),
                    )
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              _error!,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _DetailSurfaceCard(
                                child: Row(
                                  children: [
                                    patientAvatarForDoctor(
                                      name: patientName,
                                      patientPhotoPath:
                                          _data?['patientPhotoPath']?.toString(),
                                      radius: 28,
                                      backgroundColor:
                                          HeadsAppColors.brandHighlight,
                                      accentColor: HeadsAppColors.brandPrimary,
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            patientName,
                                            style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w800,
                                              color: HeadsAppColors.textPrimary,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            _requestSubtitle(status),
                                            style: const TextStyle(
                                              fontSize: 13,
                                              color:
                                                  HeadsAppColors.textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (_data?['createdAt'] != null) ...[
                                const SizedBox(height: 12),
                                _DetailSurfaceCard(
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.schedule_rounded,
                                        size: 18,
                                        color: HeadsAppColors.textSecondary
                                            .withValues(alpha: 0.9),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Date de la demande : ${DateFormat('dd/MM/yyyy à HH:mm').format(DateTime.parse(_data!['createdAt'].toString()).toLocal())}',
                                          style: const TextStyle(
                                            fontSize: 14,
                                            color: HeadsAppColors.textSecondary,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 16),
                              const Text(
                                'Texte de la demande',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                  color: HeadsAppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 10),
                              _DetailSurfaceCard(
                                child: Builder(
                                  builder: (context) {
                                    final raw = (_data?['letterBody']
                                                ?.toString() ??
                                            '')
                                        .trim();
                                    final letter = raw.isNotEmpty
                                        ? raw
                                        : kTeleconsultFirstRequestLetterBody;
                                    return Text(
                                      letter,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        height: 1.45,
                                        color: HeadsAppColors.textPrimary,
                                      ),
                                    );
                                  },
                                ),
                              ),
                              if ((_data?['motif']?.toString() ?? '')
                                  .trim()
                                  .isNotEmpty) ...[
                                const SizedBox(height: 16),
                                const Text(
                                  'Précisions du patient',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                    color: HeadsAppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                _DetailSurfaceCard(
                                  child: Text(
                                    _data!['motif'].toString(),
                                    style: const TextStyle(
                                      fontSize: 15,
                                      height: 1.4,
                                      color: HeadsAppColors.textPrimary,
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 20),
                              if (pending) ...[
                                SizedBox(
                                  height: 50,
                                  child: FilledButton.icon(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: _ctaBlue,
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    onPressed:
                                        _busy ? null : () => _decide(true),
                                    icon: const Icon(Icons.check_rounded),
                                    label: const Text(
                                      'Accepter',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                SizedBox(
                                  height: 50,
                                  child: TextButton.icon(
                                    style: TextButton.styleFrom(
                                      backgroundColor: const Color(0xFFF2F4F7),
                                      foregroundColor: HeadsAppColors.textPrimary,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    onPressed: _busy
                                        ? null
                                        : _promptRejectAndDecide,
                                    icon: const Icon(Icons.close_rounded),
                                    label: const Text(
                                      'Refuser',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                              ] else
                                _DetailSurfaceCard(
                                  child: Row(
                                    children: [
                                      Icon(
                                        status == 'accepted'
                                            ? Icons.check_circle_outline_rounded
                                            : Icons.cancel_outlined,
                                        color: status == 'accepted'
                                            ? HeadsAppColors.success
                                            : HeadsAppColors.danger,
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        'Statut final : ${_requestStatusLabel(status)}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 15,
                                          color: status == 'accepted'
                                              ? HeadsAppColors.success
                                              : HeadsAppColors.danger,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailSurfaceCard extends StatelessWidget {
  const _DetailSurfaceCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}
