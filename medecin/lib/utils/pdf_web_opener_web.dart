import 'dart:html' as html;
import 'dart:typed_data';

Future<void> openPdfBytesInNewTab(
  Uint8List bytes, {
  String filename = 'document.pdf',
}) async {
  final blob = html.Blob(<dynamic>[bytes], 'application/pdf');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.window.open(url, '_blank');
}
