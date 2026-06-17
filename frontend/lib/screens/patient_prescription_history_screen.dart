import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../headsapp_theme.dart';
import '../services/api_service.dart';
import '../utils/patient_ui_utils.dart';
import '../widgets/medical_dossier_file_viewer.dart';

/// Liste des ordonnances envoyées dans cette conversation (accès patient).
class PatientPrescriptionHistoryScreen extends StatefulWidget {
  const PatientPrescriptionHistoryScreen({
    super.key,
    required this.conversationId,
    this.title = 'Mes ordonnances',
  });

  final String conversationId;
  final String title;

  @override
  State<PatientPrescriptionHistoryScreen> createState() =>
      _PatientPrescriptionHistoryScreenState();
}

class _PatientPrescriptionHistoryScreenState
    extends State<PatientPrescriptionHistoryScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  DateTime? _from;
  DateTime? _to;

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
      final list = await ApiService.getConversationPrescriptions(
        conversationId: widget.conversationId,
        from: _from,
        to: _to,
        limit: 150,
      );
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _pickFrom() async {
    final now = DateTime.now();
    final init = _from ?? now.subtract(const Duration(days: 30));
    final date = await showDatePicker(
      context: context,
      initialDate: init,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 2),
      locale: const Locale('fr', 'FR'),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(init),
    );
    if (!mounted) return;
    final dt = DateTime(
      date.year,
      date.month,
      date.day,
      time?.hour ?? 0,
      time?.minute ?? 0,
    );
    setState(() => _from = dt);
    await _load();
  }

  Future<void> _pickTo() async {
    final now = DateTime.now();
    final init = _to ?? now;
    final date = await showDatePicker(
      context: context,
      initialDate: init,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 2),
      locale: const Locale('fr', 'FR'),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(init),
    );
    if (!mounted) return;
    final dt = DateTime(
      date.year,
      date.month,
      date.day,
      time?.hour ?? 23,
      time?.minute ?? 59,
    );
    setState(() => _to = dt);
    await _load();
  }

  String _fmtDate(DateTime? d) =>
      d == null ? '—' : DateFormat('dd/MM/yyyy HH:mm').format(d);

  Future<void> _openPdf({
    required String prescriptionId,
  }) async {
    final pid = prescriptionId.trim();
    if (pid.isEmpty) return;
    final url = ApiService.prescriptionPdfProxyUrlByPrescriptionId(
      conversationId: widget.conversationId,
      prescriptionId: pid,
    );
    await showMedicalDossierFileViewer(
      context,
      resolvedUrl: url,
      filename: 'ordonnance.pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: HeadsAppColors.brandPrimary,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _pickFrom,
                  icon: const Icon(Icons.schedule_rounded),
                  label: Text('Du ${_fmtDate(_from)}'),
                ),
                OutlinedButton.icon(
                  onPressed: _pickTo,
                  icon: const Icon(Icons.event_rounded),
                  label: Text('Au ${_fmtDate(_to)}'),
                ),
                TextButton(
                  onPressed: () async {
                    setState(() {
                      _from = null;
                      _to = null;
                    });
                    await _load();
                  },
                  child: const Text('Réinitialiser'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: HeadsAppColors.brandPrimary),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _load,
                style: FilledButton.styleFrom(
                  backgroundColor: HeadsAppColors.brandPrimary,
                ),
                child: const Text('Réessayer'),
              ),
            ],
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return const Center(
        child: Text('Aucune ordonnance pour ce filtre.'),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _items.length,
      separatorBuilder: (_, i) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final e = _items[i];
        final prescriptionId = '${e['prescriptionId'] ?? ''}'.trim();
        final sent = DateTime.tryParse('${e['sentAt'] ?? ''}')?.toLocal();
        final sentLabel =
            sent != null ? DateFormat('dd/MM/yyyy à HH:mm').format(sent) : '—';
        final doctorName = readableDoctorName(e['doctorName']?.toString(), fallback: '');
        final city = readableDecryptedField(e['city']?.toString());
        return Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: HeadsAppColors.brandHighlight,
              child: Icon(
                Icons.picture_as_pdf_rounded,
                color: HeadsAppColors.brandPrimary,
              ),
            ),
            title: Text('Ordonnance · $sentLabel'),
            subtitle: Text(
              [
                if (doctorName.isNotEmpty) 'Dr : $doctorName',
                if (city.isNotEmpty) 'Ville : $city',
              ].join(' · '),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: prescriptionId.isEmpty
                ? null
                : () => _openPdf(prescriptionId: prescriptionId),
          ),
        );
      },
    );
  }
}
