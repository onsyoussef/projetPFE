import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:pdfx/pdfx.dart';
import 'package:url_launcher/url_launcher.dart';

import '../headsapp_theme.dart';
import '../services/api_service.dart';
import 'medical_dossier_pdf_embed_stub.dart'
    if (dart.library.html) 'medical_dossier_pdf_embed_web.dart';

enum _ViewerKind { image, pdf, text, unsupported }

_ViewerKind _classifyViewerKind(String filename, {required bool apiSaysImage}) {
  if (apiSaysImage) return _ViewerKind.image;
  final lower = filename.toLowerCase().trim();
  if (lower.endsWith('.pdf')) return _ViewerKind.pdf;
  if (lower.endsWith('.txt')) return _ViewerKind.text;
  if (lower.endsWith('.png') ||
      lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.gif') ||
      lower.endsWith('.webp') ||
      lower.endsWith('.bmp')) {
    return _ViewerKind.image;
  }
  return _ViewerKind.unsupported;
}

bool _isOfficeDocumentName(String name) {
  final l = name.toLowerCase().trim();
  return l.endsWith('.doc') ||
      l.endsWith('.docx') ||
      l.endsWith('.xls') ||
      l.endsWith('.xlsx');
}

/// Visionneuse plein écran : images, PDF et texte en mémoire (pas de lien avec attribut [download]).
Future<void> showMedicalDossierFileViewer(
  BuildContext context, {
  required String resolvedUrl,
  required String filename,
  bool isImageType = false,
  /// URL consultable sans JWT (ex. Cloudinary ou `/uploads/`), pour « Ouvrir dans le navigateur ».
  String? urlForExternalBrowser,
}) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    useSafeArea: false,
    builder: (ctx) => Dialog(
      clipBehavior: Clip.antiAlias,
      insetPadding: EdgeInsets.zero,
      child: _MedicalDossierFileViewerBody(
        resolvedUrl: resolvedUrl,
        filename: filename,
        isImageType: isImageType,
        urlForExternalBrowser: urlForExternalBrowser,
      ),
    ),
  );
}

class _MedicalDossierFileViewerBody extends StatefulWidget {
  const _MedicalDossierFileViewerBody({
    required this.resolvedUrl,
    required this.filename,
    required this.isImageType,
    this.urlForExternalBrowser,
  });

  final String resolvedUrl;
  final String filename;
  final bool isImageType;
  final String? urlForExternalBrowser;

  @override
  State<_MedicalDossierFileViewerBody> createState() => _MedicalDossierFileViewerBodyState();
}

class _MedicalDossierFileViewerBodyState extends State<_MedicalDossierFileViewerBody> {
  Uint8List? _bytes;
  String? _error;
  bool _loading = true;
  PdfControllerPinch? _pdfController;
  late final _ViewerKind _kind;

  @override
  void initState() {
    super.initState();
    _kind = _classifyViewerKind(widget.filename, apiSaysImage: widget.isImageType);
    _load();
  }

  @override
  void dispose() {
    _pdfController?.dispose();
    super.dispose();
  }

  Future<void> _openInExternalBrowser() async {
    final prefer = widget.urlForExternalBrowser?.trim();
    final target = (prefer != null && prefer.isNotEmpty) ? prefer : widget.resolvedUrl.trim();
    if (!mounted || target.isEmpty) return;
    final uri = Uri.parse(target);
    try {
      if (kIsWeb) {
        final ok = await launchUrl(uri, webOnlyWindowName: '_blank');
        if (!ok && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ouverture dans le navigateur impossible.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Aucune application pour ouvrir ce lien.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _load() async {
    if (_kind == _ViewerKind.unsupported) {
      setState(() {
        _loading = false;
        _error = null;
      });
      return;
    }

    try {
      final uri = Uri.parse(widget.resolvedUrl);
      final token = ApiService.jwtToken;
      final response = await http.get(
        uri,
        headers: {
          if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
        },
      );
      if (response.statusCode != 200) {
        setState(() {
          _loading = false;
          _error = 'Chargement impossible (${response.statusCode}).';
        });
        return;
      }
      final bytes = response.bodyBytes;
      if (_kind == _ViewerKind.pdf && !kIsWeb) {
        _pdfController = PdfControllerPinch(
          document: PdfDocument.openData(bytes),
        );
      }
      setState(() {
        _bytes = bytes;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.filename.trim().isEmpty ? 'Document' : widget.filename;

    return Material(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppBar(
            backgroundColor: HeadsAppColors.brandPrimary,
            foregroundColor: Colors.white,
            title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
            leading: IconButton(
              icon: const Icon(Icons.close_rounded),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(child: Text(_error!, textAlign: TextAlign.center)),
      );
    }

    if (_kind == _ViewerKind.unsupported) {
      final showBrowser = _isOfficeDocumentName(widget.filename);
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.description_outlined, size: 56, color: Colors.grey.shade500),
              const SizedBox(height: 16),
              const Text(
                'La prévisualisation de ce type de fichier (Word, Excel, etc.) '
                "n'est pas disponible dans l'application.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, height: 1.4),
              ),
              if (showBrowser) ...[
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _openInExternalBrowser,
                  icon: const Icon(Icons.open_in_browser_rounded),
                  label: const Text('Ouvrir dans le navigateur'),
                  style: FilledButton.styleFrom(backgroundColor: HeadsAppColors.brandPrimary),
                ),
              ],
            ],
          ),
        ),
      );
    }

    final bytes = _bytes;
    if (bytes == null) {
      return const Center(child: Text('Aucune donnée.'));
    }

    switch (_kind) {
      case _ViewerKind.image:
        return InteractiveViewer(
          minScale: 0.5,
          maxScale: 4,
          child: Center(
            child: Image.memory(
              bytes,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Impossible d’afficher cette image.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        );
      case _ViewerKind.pdf:
        if (kIsWeb) {
          return MedicalPdfEmbedWeb(bytes: bytes);
        }
        final c = _pdfController;
        if (c == null) {
          return const Center(child: Text('PDF indisponible.'));
        }
        return PdfViewPinch(controller: c);
      case _ViewerKind.text:
        late final String text;
        try {
          text = utf8.decode(bytes, allowMalformed: true);
        } catch (_) {
          text = String.fromCharCodes(bytes);
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: SelectableText(text, style: const TextStyle(fontSize: 14, height: 1.45)),
        );
      case _ViewerKind.unsupported:
        return const SizedBox.shrink();
    }
  }
}
