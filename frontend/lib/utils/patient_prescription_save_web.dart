import 'dart:html' as html;
import 'dart:typed_data';

Future<String> savePatientPrescriptionPdf(Uint8List bytes, String filename) async {
  final blob = html.Blob([bytes]);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final safe = filename.replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_');
  html.AnchorElement(href: url)
    ..setAttribute('download', safe)
    ..click();
  html.Url.revokeObjectUrl(url);
  return safe;
}
