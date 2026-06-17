import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../headsapp_theme.dart';
import '../services/api_service.dart';
import '../teleconsult_first_request_letter.dart';
import '../utils/doctor_ui_utils.dart';

const Color _sky = HeadsAppColors.brandPrimary;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Demandes'),
        backgroundColor: _sky,
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _load();
          await widget.onRefreshHome?.call();
        },
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: _sky))
            : _error != null
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      const SizedBox(height: 48),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(_error!, textAlign: TextAlign.center),
                      ),
                    ],
                  )
                : _items.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          SizedBox(height: 80),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 24),
                            child: Text(
                              'Aucune demande reçue pour le moment.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: _items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final it = _items[i];
                          final name =
                              it['patientName']?.toString() ?? 'Patient';
                          final motif = it['motif']?.toString() ?? '';
                          final letter =
                              it['letterBody']?.toString().trim() ?? '';
                          final preview = doctorFormBodyPreview(
                            letter.isNotEmpty ? letter : motif,
                          );
                          final status =
                              it['status']?.toString() ?? 'pending';
                          final at = it['createdAt'];
                          DateTime? dt;
                          if (at != null) {
                            dt = DateTime.tryParse(at.toString());
                          }

                          return Card(
                            elevation: 1,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () async {
                                final id = it['id']?.toString() ?? '';
                                if (id.isEmpty) return;
                                final changed = await Navigator.of(context)
                                    .push<bool>(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        DoctorTeleconsultRequestDetailScreen(
                                      doctorId: widget.doctorId,
                                      requestId: id,
                                    ),
                                  ),
                                );
                                if (changed == true && mounted) await _load();
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        patientAvatarForDoctor(
                                          name: name,
                                          patientPhotoPath: it['patientPhotoPath']
                                              ?.toString(),
                                          backgroundColor:
                                              _sky.withValues(alpha: 0.15),
                                          accentColor: _sky,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            '👤 $name',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 16,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (preview.isNotEmpty) ...[
                                      const SizedBox(height: 8),
                                      Text(
                                        '📄 $preview',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Colors.grey.shade800,
                                          fontSize: 13,
                                          height: 1.25,
                                        ),
                                      ),
                                    ],
                                    if (dt != null) ...[
                                      const SizedBox(height: 6),
                                      Text(
                                        '🕐 ${DateFormat('dd/MM/yyyy HH:mm').format(dt.toLocal())}',
                                        style: TextStyle(
                                          color: Colors.grey.shade700,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 8),
                                    Text(
                                      'Statut : ${_requestStatusLabel(status)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
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
        builder: (ctx) => AlertDialog(
          title: const Text('Confirmer le refus'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Voulez-vous vraiment refuser cette demande ?',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: motifCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Motif du refus (optionnel)',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                foregroundColor: Colors.white,
              ),
              child: const Text('Confirmer le refus'),
            ),
          ],
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Demande — détail'),
        backgroundColor: _sky,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context, true),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _sky))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          patientAvatarForDoctor(
                            name: _data?['patientName']?.toString() ??
                                'Patient',
                            patientPhotoPath:
                                _data?['patientPhotoPath']?.toString(),
                            radius: 28,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              _data?['patientName']?.toString() ?? 'Patient',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_data?['createdAt'] != null)
                        Text(
                          'Date de la demande : ${DateFormat('dd/MM/yyyy à HH:mm').format(DateTime.parse(_data!['createdAt'].toString()).toLocal())}',
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontSize: 14,
                          ),
                        ),
                      const SizedBox(height: 20),
                      const Text(
                        'Texte de la demande',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Builder(
                        builder: (context) {
                          final raw =
                              (_data?['letterBody']?.toString() ?? '').trim();
                          final letter = raw.isNotEmpty
                              ? raw
                              : kTeleconsultFirstRequestLetterBody;
                          return Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Text(
                              letter,
                              style: const TextStyle(
                                fontSize: 15,
                                height: 1.4,
                              ),
                            ),
                          );
                        },
                      ),
                      if ((_data?['motif']?.toString() ?? '').trim().isNotEmpty) ...[
                        const SizedBox(height: 20),
                        const Text(
                          'Précisions du patient (facultatif)',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _data!['motif'].toString(),
                          style: const TextStyle(fontSize: 15, height: 1.35),
                        ),
                      ],
                      const SizedBox(height: 24),
                      if (pending) ...[
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF16A34A),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                ),
                                onPressed: _busy ? null : () => _decide(true),
                                icon: const Icon(Icons.check_rounded),
                                label: const Text('Accepter'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFFDC2626),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                ),
                                onPressed: _busy ? null : _promptRejectAndDecide,
                                icon: const Icon(Icons.close_rounded),
                                label: const Text('Refuser'),
                              ),
                            ),
                          ],
                        ),
                      ] else
                        Text(
                          'Statut final : ${_requestStatusLabel(status)}',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: status == 'accepted'
                                ? const Color(0xFF16A34A)
                                : const Color(0xFFDC2626),
                          ),
                        ),
                      const SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.pop(context, true),
                          icon: const Icon(Icons.arrow_back_rounded),
                          label: const Text('Retour à la liste'),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}
