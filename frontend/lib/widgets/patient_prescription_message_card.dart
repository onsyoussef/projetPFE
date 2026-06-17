import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../headsapp_theme.dart';
import '../services/api_service.dart';
import '../utils/patient_prescription_save.dart';
import 'medical_dossier_file_viewer.dart';

/// Carte « ordonnance » côté patient (distincte des messages texte).
class PatientPrescriptionMessageCard extends StatelessWidget {
  const PatientPrescriptionMessageCard({
    super.key,
    required this.msg,
    this.conversationId,
  });

  final Map<String, dynamic> msg;

  /// Conversation courante (chat) : permet le chargement PDF via proxy API au lieu de Cloudinary direct.
  final String? conversationId;

  DateTime? _sentAt() {
    final payload = msg['payload'];
    if (payload is Map) {
      final iso = payload['sentAt']?.toString();
      final parsed = DateTime.tryParse(iso ?? '');
      if (parsed != null) return parsed.toLocal();
    }
    final created = msg['createdAt'];
    if (created == null) return null;
    return DateTime.tryParse(created.toString())?.toLocal();
  }

  String _pdfUrl() {
    final payload = msg['payload'];
    if (payload is! Map) return '';
    return '${payload['pdfUrl'] ?? ''}'.trim();
  }

  String? _messageId() {
    final id = msg['_id'] ?? msg['id'];
    if (id == null) return null;
    final s = id.toString().trim();
    return s.isEmpty ? null : s;
  }

  /// GET PDF : proxy `/api/.../by-message/.../pdf` si possible, sinon URL média (sans `fl_inline` invalide).
  String _pdfFetchUrl() {
    final cid = conversationId?.trim() ?? '';
    final mid = _messageId();
    if (cid.isNotEmpty && mid != null && mid.isNotEmpty) {
      return ApiService.prescriptionPdfProxyUrl(
        conversationId: cid,
        messageId: mid,
      );
    }
    final pdfUrl = _pdfUrl();
    if (pdfUrl.isEmpty) return '';
    return ApiService.resolveMediaUrl(pdfUrl);
  }

  Future<void> _open(BuildContext context) async {
    final fetchUrl = _pdfFetchUrl();
    if (fetchUrl.isEmpty) return;
    await showMedicalDossierFileViewer(
      context,
      resolvedUrl: fetchUrl,
      filename: 'ordonnance.pdf',
    );
  }

  Future<void> _download(BuildContext context) async {
    final resolved = _pdfFetchUrl();
    if (resolved.isEmpty) return;
    final token = ApiService.jwtToken;
    try {
      final response = await http.get(
        Uri.parse(resolved),
        headers: {
          if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
        },
      );
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }
      final bytes = Uint8List.fromList(response.bodyBytes);
      final savedPath = await savePatientPrescriptionPdf(
        bytes,
        'ordonnance_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.pdf',
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Ordonnance téléchargée avec succès.\nEmplacement: $savedPath',
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Téléchargement impossible.\nDétail: ${e.toString().replaceFirst('Exception: ', '')}',
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final sent = _sentAt();
    final dateLabel =
        sent != null ? DateFormat('dd/MM/yyyy à HH:mm').format(sent) : '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.88,
          ),
          child: Material(
            color: const Color(0xFFE8F7EF),
            borderRadius: BorderRadius.circular(16),
            elevation: 0,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => _open(context),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: HeadsAppColors.brandPrimary.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.medical_information_rounded,
                            color: HeadsAppColors.brandPrimary,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Ordonnance médicale',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                  color: Color(0xFF0F5132),
                                ),
                              ),
                              if (dateLabel.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'Envoyée le : $dateLabel',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: () => _open(context),
                          icon: const Icon(Icons.visibility_rounded, size: 18),
                          label: const Text('Ouvrir'),
                          style: FilledButton.styleFrom(
                            backgroundColor: HeadsAppColors.brandPrimary,
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _download(context),
                          icon: const Icon(Icons.download_rounded, size: 18),
                          label: const Text('Télécharger'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
