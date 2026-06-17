import 'dart:html' as html;

import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../services/api_service.dart';

String _stripFlInlineFromCloudinaryUrl(String url) {
  return url
      .replaceAll('/raw/upload/fl_inline/', '/raw/upload/')
      .replaceAll('/video/upload/fl_inline/', '/video/upload/');
}

String _forceCloudinaryAttachmentDownload(String url) {
  if (url.contains('/upload/') && !url.contains('/upload/fl_attachment/')) {
    return url.replaceFirst('/upload/', '/upload/fl_attachment/');
  }
  return url;
}

Future<void> openChatAttachment({
  required String url,
  required String filename,
  bool preferDownload = true,
}) async {
  final cleaned =
      _forceCloudinaryAttachmentDownload(_stripFlInlineFromCloudinaryUrl(url));
  final uri = Uri.parse(cleaned);
  final token = ApiService.jwtToken;
  final headers = <String, String>{
    if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
  };

  try {
    final resp = await http.get(uri, headers: headers);
    if (resp.statusCode == 200) {
      final blob = html.Blob([resp.bodyBytes]);
      final objectUrl = html.Url.createObjectUrlFromBlob(blob);
      if (preferDownload) {
        final a = html.AnchorElement(href: objectUrl)
          ..target = '_blank'
          ..download = filename;
        html.document.body?.append(a);
        a.click();
        a.remove();
      } else {
        html.window.open(objectUrl, '_blank');
      }
      html.Url.revokeObjectUrl(objectUrl);
      return;
    }
  } catch (_) {
    // Fallback via ouverture directe du lien.
  }

  final ok = await launchUrl(
    uri,
    mode: LaunchMode.platformDefault,
    webOnlyWindowName: '_blank',
  );
  if (!ok) {
    throw Exception('Impossible d’ouvrir le fichier.');
  }
}
