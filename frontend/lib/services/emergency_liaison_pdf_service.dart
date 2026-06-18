import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../utils/patient_prescription_save.dart';

/// Génère et enregistre la fiche de liaison d'urgence sur l'appareil.
class EmergencyLiaisonPdfService {
  EmergencyLiaisonPdfService._();

  static final _dateFormat = DateFormat('dd/MM/yyyy HH:mm', 'fr');

  static Future<String> generateAndSave({
    required Map<String, dynamic> patientProfile,
    required List<Map<String, String>> symptomsWithTimes,
    required DateTime emergencyStartedAt,
  }) async {
    final bytes = await _buildPdfBytes(
      patientProfile: patientProfile,
      symptomsWithTimes: symptomsWithTimes,
      emergencyStartedAt: emergencyStartedAt,
    );

    final fileName =
        'fiche_liaison_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final savedPath = await savePatientPrescriptionPdf(bytes, fileName);

    if (!kIsWeb) {
      await OpenFile.open(savedPath);
    }
    return savedPath;
  }

  static Future<Uint8List> _buildPdfBytes({
    required Map<String, dynamic> patientProfile,
    required List<Map<String, String>> symptomsWithTimes,
    required DateTime emergencyStartedAt,
  }) async {
    final pdf = pw.Document();
    final fullName = (patientProfile['fullName'] as String?)?.trim() ?? 'Patient';
    final birthDate = patientProfile['birthDate'];
    final sex = patientProfile['sex'] as String?;
    final bloodGroup = (patientProfile['bloodGroup'] as String?)?.trim() ?? '';
    final phone = (patientProfile['phone'] as String?)?.trim() ?? '';
    final address = (patientProfile['addressExact'] as String?)?.trim() ?? '';
    final weightKg = patientProfile['weightKg'];
    final heightCm = patientProfile['heightCm'];
    final allergies = (patientProfile['knownAllergies'] as String?)?.trim() ?? '';

    String birthLabel = '-';
    if (birthDate is String && birthDate.isNotEmpty) {
      final parsed = DateTime.tryParse(birthDate);
      if (parsed != null) {
        birthLabel = DateFormat('dd/MM/yyyy', 'fr').format(parsed);
      }
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Text(
              'FICHE DE LIAISON D\'URGENCE - HeadsApp',
              style: pw.TextStyle(
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.blue900,
              ),
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            'Generee le ${_dateFormat.format(DateTime.now())}',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 20),
          pw.Text(
            'Informations patient',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          _infoRow('Nom complet', fullName),
          _infoRow('Date de naissance', birthLabel),
          _infoRow('Sexe', sex ?? '-'),
          _infoRow('Groupe sanguin', bloodGroup.isEmpty ? '-' : bloodGroup),
          _infoRow('Telephone', phone.isEmpty ? '-' : phone),
          _infoRow('Adresse', address.isEmpty ? '-' : address),
          if (weightKg != null) _infoRow('Poids', '$weightKg kg'),
          if (heightCm != null) _infoRow('Taille', '$heightCm cm'),
          if (allergies.isNotEmpty) _infoRow('Allergies connues', allergies),
          pw.SizedBox(height: 20),
          pw.Text(
            'Alerte urgence acceptee le ${_dateFormat.format(emergencyStartedAt)}',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 12),
          pw.Text(
            'Symptomes signales',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          if (symptomsWithTimes.isEmpty)
            pw.Text('Aucun symptome enregistre.')
          else
            pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
              cellAlignment: pw.Alignment.centerLeft,
              headers: ['Symptome', 'Heure de selection'],
              data: symptomsWithTimes
                  .map((s) {
                    final at = DateTime.tryParse(s['at'] ?? '');
                    final timeLabel =
                        at != null ? _dateFormat.format(at) : '-';
                    return [s['label'] ?? '', timeLabel];
                  })
                  .toList(),
            ),
          pw.SizedBox(height: 24),
          pw.Text(
            'Consignes : appelez le 190 (SAMU), restez au repos, ne conduisez pas, gardez votre telephone libre.',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey800),
          ),
        ],
      ),
    );

    return pdf.save();
  }

  static pw.Widget _infoRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 130,
            child: pw.Text(
              '$label :',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.Expanded(child: pw.Text(value)),
        ],
      ),
    );
  }
}
