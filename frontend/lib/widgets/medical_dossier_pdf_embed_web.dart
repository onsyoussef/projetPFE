import 'dart:typed_data';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';

/// PDF dans une iframe + blob URL : évite pdfx / PDF.js (erreur `getDocument is not a function` sur Web).
class MedicalPdfEmbedWeb extends StatefulWidget {
  const MedicalPdfEmbedWeb({super.key, required this.bytes});

  final Uint8List bytes;

  @override
  State<MedicalPdfEmbedWeb> createState() => _MedicalPdfEmbedWebState();
}

class _MedicalPdfEmbedWebState extends State<MedicalPdfEmbedWeb> {
  late final String _viewType;
  late final String _blobUrl;

  @override
  void initState() {
    super.initState();
    _viewType =
        'medical_pdf_${identityHashCode(this)}_${DateTime.now().microsecondsSinceEpoch}';
    _blobUrl = html.Url.createObjectUrlFromBlob(
      html.Blob(<dynamic>[widget.bytes], 'application/pdf'),
    );
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final iframe = html.IFrameElement()
        ..src = _blobUrl
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%';
      return iframe;
    });
  }

  @override
  void dispose() {
    html.Url.revokeObjectUrl(_blobUrl);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType);
  }
}
