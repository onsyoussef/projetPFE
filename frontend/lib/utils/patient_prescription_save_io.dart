import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

Future<String> savePatientPrescriptionPdf(Uint8List bytes, String filename) async {
  if (bytes.isEmpty) {
    throw Exception('PDF vide, impossible à sauvegarder.');
  }

  final stamp = _timestamp();
  final safeName = _safeFilename('ordonnance_$stamp.pdf');

  if (Platform.isAndroid) {
    await _requestAndroidStoragePermissions();
  }

  final triedPaths = <String>[];
  final candidates = <Directory>[];

  if (Platform.isAndroid) {
    candidates.add(Directory('/storage/emulated/0/Download'));
  }

  final downloadsDir = await getDownloadsDirectory();
  if (downloadsDir != null) {
    candidates.add(downloadsDir);
  }

  final appDocs = await getApplicationDocumentsDirectory();
  candidates.add(appDocs);

  for (final dir in candidates) {
    final filePath = '${dir.path}${Platform.pathSeparator}$safeName';
    triedPaths.add(filePath);
    try {
      await dir.create(recursive: true);
      final file = File(filePath);
      await file.writeAsBytes(bytes, flush: true);
      print('[PatientPrescriptionSave] PDF enregistré: ${file.path}');
      return file.path;
    } catch (e) {
      print('[PatientPrescriptionSave] Échec écriture sur $filePath: $e');
    }
  }

  throw Exception(
    'Impossible de sauvegarder le PDF. Emplacements testés: ${triedPaths.join(' | ')}',
  );
}

String _safeFilename(String filename) =>
    filename.replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_');

String _timestamp() {
  final now = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}';
}

Future<void> _requestAndroidStoragePermissions() async {
  final storage = await Permission.storage.request();
  final manage = await Permission.manageExternalStorage.request();
  print(
    '[PatientPrescriptionSave] Permissions Android storage=${storage.name} manageExternalStorage=${manage.name}',
  );
}
