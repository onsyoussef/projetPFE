import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';

import '../services/api_service.dart';

String _safeFileName(String name) {
  final base = name.trim().isEmpty ? 'fichier' : name;
  return base.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
}

String _stripFlInlineFromCloudinaryUrl(String url) {
  return url
      .replaceAll('/raw/upload/fl_inline/', '/raw/upload/')
      .replaceAll('/video/upload/fl_inline/', '/video/upload/');
}

/// Télécharge l’URL puis ouvre le fichier avec l’app système.
Future<void> openChatAttachment({
  required String url,
  required String filename,
  bool preferDownload = true,
}) async {
  final cleaned = _stripFlInlineFromCloudinaryUrl(url);
  final uri = Uri.parse(cleaned);
  final token = ApiService.jwtToken;
  final response = await http.get(
    uri,
    headers: {
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    },
  );
  if (response.statusCode != 200) {
    throw Exception('Téléchargement impossible (${response.statusCode}).');
  }
  final dir = await getTemporaryDirectory();
  final path = '${dir.path}/${_safeFileName(filename)}';
  final file = File(path);
  await file.writeAsBytes(response.bodyBytes);
  final result = await OpenFile.open(path);
  if (result.type == ResultType.error) {
    final m = result.message;
    throw Exception(m.isEmpty ? 'Ouverture impossible' : m);
  }
}
