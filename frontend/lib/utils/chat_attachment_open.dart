import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/api_service.dart';
import '../widgets/medical_dossier_file_viewer.dart';

/// Ouvre la pièce jointe dans la visionneuse intégrée (pas de fichier temporaire, pas d’[OpenFile]).
Future<void> openChatAttachment({
  required BuildContext context,
  required String url,
  required String filename,
  bool isImageType = false,
  bool preferDownload = false,
}) async {
  if (!context.mounted) return;
  if (preferDownload) {
    final ok = await launchUrl(
      Uri.parse(ApiService.resolveMediaUrl(url)),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Téléchargement impossible.')),
      );
    }
    return;
  }
  await showMedicalDossierFileViewer(
    context,
    resolvedUrl: ApiService.resolveMediaUrl(url),
    filename: filename,
    isImageType: isImageType,
  );
}
