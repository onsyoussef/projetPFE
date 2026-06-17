import 'dart:typed_data';

import 'package:flutter/widgets.dart';

/// Sur IO / mobile, la visionneuse utilise [pdfx] ; ce widget n’est pas utilisé.
class MedicalPdfEmbedWeb extends StatelessWidget {
  const MedicalPdfEmbedWeb({super.key, required this.bytes});

  final Uint8List bytes;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
