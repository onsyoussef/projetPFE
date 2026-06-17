import 'dart:typed_data';

import 'pdf_web_opener_stub.dart'
    if (dart.library.html) 'pdf_web_opener_web.dart' as impl;

Future<void> openPdfBytesInNewTab(
  Uint8List bytes, {
  String filename = 'document.pdf',
}) {
  return impl.openPdfBytesInNewTab(bytes, filename: filename);
}
