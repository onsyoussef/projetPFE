import 'dart:async';
import 'dart:developer' as dev;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:url_launcher/url_launcher.dart';

import '../headsapp_theme.dart';
import '../services/api_service.dart';
import '../utils/pdf_web_opener.dart';

/// Lecteur PDF plein écran pour le médecin (aperçu uniquement).
///
/// Privilégie les URLs **`GET .../prescriptions/:id/pdf`** ou **`.../by-message/:messageId/pdf`**
/// (JWT) pour éviter les 400 « Cloudinary attendu » côté serveur et les soucis CORS sur le web.
class DoctorPrescriptionPdfViewerScreen extends StatefulWidget {
  const DoctorPrescriptionPdfViewerScreen({
    super.key,
    required this.pdfUrl,
    this.conversationId,
    this.prescriptionId,
    /// Message chat `prescription` — permet le proxy même sans `prescriptionId` en payload.
    this.prescriptionMessageId,
    this.title = 'Ordonnance',
  });

  /// URL historique / secours (Cloudinary ou `/uploads/...`).
  final String pdfUrl;

  /// Si renseignés, chargement via proxy API authentifié (recommandé).
  final String? conversationId;
  final String? prescriptionId;
  final String? prescriptionMessageId;

  final String title;

  @override
  State<DoctorPrescriptionPdfViewerScreen> createState() =>
      _DoctorPrescriptionPdfViewerScreenState();
}

class _DoctorPrescriptionPdfViewerScreenState
    extends State<DoctorPrescriptionPdfViewerScreen> {
  Uint8List? _bytes;
  String? _error;
  bool _loading = true;
  bool _webOpenInProgress = false;

  static final RegExp _mongoObjectId = RegExp(r'^[0-9a-fA-F]{24}$');

  /// Évite d’appeler `GET .../prescriptions/:id/pdf` avec une valeur qui n’est pas un ObjectId
  /// (sinon le backend répond **400** et le fallback `by-message` n’était jamais tenté).
  bool _isLikelyMongoObjectId(String? s) =>
      s != null &&
      s.trim().isNotEmpty &&
      _mongoObjectId.hasMatch(s.trim());

  /// Compare deux URLs PDF en ignorant query et casse (Cloudinary, chemins relatifs résolus).
  String _canonicalPdfUrlForCompare(String raw) {
    var resolved = ApiService.resolveMediaUrl(raw).trim();
    // Même logique que le backend (`stripFlInlineFromCloudinaryUrl`) pour comparer message vs `/latest`.
    resolved = resolved
        .replaceAll('/raw/upload/fl_inline/', '/raw/upload/')
        .replaceAll('/video/upload/fl_inline/', '/video/upload/');
    final uri = Uri.tryParse(resolved);
    if (uri == null || uri.host.isEmpty) return resolved.toLowerCase();
    return '${uri.scheme}://${uri.host}${uri.path}'.toLowerCase();
  }

  /// Aligné sur le backend (`normalizeCloudinaryDeliveryUrl`) pour les GET directs.
  String _normalizeDirectFetchUrl(String resolved) {
    var t = resolved.trim();
    if (t.startsWith('http://res.cloudinary.com')) {
      t = 'https://${t.substring('http://'.length)}';
    }
    return t
        .replaceAll('/raw/upload/fl_inline/', '/raw/upload/')
        .replaceAll('/video/upload/fl_inline/', '/video/upload/');
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadPdf());
  }

  String _apiBaseTrimmed() {
    final b = ApiService.baseUrl.trim();
    return b.endsWith('/') ? b.substring(0, b.length - 1) : b;
  }

  Future<void> _loadPdf() async {
    const logName = 'DoctorPrescriptionPdfViewer';
    final traceId = DateTime.now().millisecondsSinceEpoch;
    void step(String message) {
      debugPrint('[DoctorPrescriptionPdfViewer#$traceId] $message');
      dev.log(message, name: logName);
    }

    step('start load pdf');
    setState(() {
      _loading = true;
      _error = null;
      _bytes = null;
    });

    final cid = widget.conversationId?.trim();
    final pid = widget.prescriptionId?.trim();
    final mid = widget.prescriptionMessageId?.trim();
    final jwt = ApiService.jwtToken?.trim() ?? '';
    var stopProxyAttempts = false;
    if (ApiService.jwtToken == null || ApiService.jwtToken!.isEmpty) {
      debugPrint(
        '[DoctorPrescriptionPdfViewer] JWT absent — skip proxy, fallback direct',
      );
      // Pas de return : on laisse le fallback direct Cloudinary s'exécuter.
    }
    step(
      'params cid=${cid ?? ''}, pid=${pid ?? ''}, mid=${mid ?? ''}, jwt=${jwt.isEmpty ? 'missing' : 'present'}',
    );

    Future<bool> tryProxyUri(Uri uri, {required String reason}) async {
      step('proxy try ($reason) -> $uri');
      try {
        final response = await http.get(
          uri,
          headers: {
            if (jwt.isNotEmpty) 'Authorization': 'Bearer $jwt',
          },
        );
        step('proxy response ($reason): ${response.statusCode}, bytes=${response.bodyBytes.length}');
        if (!mounted) return false;
        if (response.statusCode == 401) {
          debugPrint('[DoctorPrescriptionPdfViewer] 401 JWT absent ou expiré');
          stopProxyAttempts = true;
          setState(() {
            _loading = false;
            _error = 'Impossible de charger le PDF (code 401). '
                'Votre session a peut-être expiré. Reconnectez-vous.';
          });
          return false;
        }
        if (response.statusCode == 200 &&
            response.bodyBytes.isNotEmpty &&
            _looksLikePdf(response.bodyBytes)) {
          setState(() {
            _bytes = Uint8List.fromList(response.bodyBytes);
            _loading = false;
          });
          step('proxy success ($reason)');
          return true;
        }
      } catch (e, st) {
        step('proxy exception ($reason): $e');
        dev.log(
          'Proxy fetch failure',
          name: logName,
          error: e,
          stackTrace: st,
        );
      }
      return false;
    }

    if (cid != null && cid.isNotEmpty && jwt.isNotEmpty) {
      // 1) by-message en priorité absolue.
      if (mid != null && mid.isNotEmpty && _isLikelyMongoObjectId(mid)) {
        final byMessageUri = Uri.parse(
          '${_apiBaseTrimmed()}/api/conversations/'
          '${Uri.encodeComponent(cid)}/prescriptions/by-message/'
          '${Uri.encodeComponent(mid)}/pdf',
        );
        if (await tryProxyUri(byMessageUri, reason: 'by-message')) return;
        if (stopProxyAttempts) return;
      } else {
        step('skip by-message: messageId absent/invalide');
      }

      // 2) by-prescriptionId si ObjectId plausible.
      if (pid != null && pid.isNotEmpty && _isLikelyMongoObjectId(pid)) {
        final byPrescriptionUri = Uri.parse(
          '${_apiBaseTrimmed()}/api/conversations/'
          '${Uri.encodeComponent(cid)}/prescriptions/'
          '${Uri.encodeComponent(pid)}/pdf',
        );
        if (await tryProxyUri(byPrescriptionUri, reason: 'by-prescription-id')) {
          return;
        }
        if (stopProxyAttempts) return;
      } else {
        step('skip by-prescription-id: prescriptionId absent/invalide');
      }

      // 3) Fallback latest -> by-prescriptionId si URL cohérente.
      try {
        step('fetch latest prescription for fallback');
        final latest = await ApiService.getLatestPrescription(
          conversationId: cid,
        );
        final want = _canonicalPdfUrlForCompare(widget.pdfUrl);
        final latestPdf = '${latest['pdfUrl'] ?? ''}'.trim();
        final got = _canonicalPdfUrlForCompare(latestPdf);
        final retryPid = '${latest['prescriptionId'] ?? ''}'.trim();
        step(
          'latest fetched retryPid=$retryPid latestPdf=${latestPdf.isEmpty ? 'empty' : 'present'} urlMatch=${want == got}',
        );
        if (retryPid.isNotEmpty &&
            latestPdf.isNotEmpty &&
            want == got &&
            _isLikelyMongoObjectId(retryPid)) {
          final uri = Uri.parse(
            '${_apiBaseTrimmed()}/api/conversations/'
            '${Uri.encodeComponent(cid)}/prescriptions/'
            '${Uri.encodeComponent(retryPid)}/pdf',
          );
          if (await tryProxyUri(uri, reason: 'latest-prescription-id-match')) {
            return;
          }
          if (stopProxyAttempts) return;
        }
      } catch (e, st) {
        step('latest fallback failed: $e');
        dev.log('Latest fallback failure', name: logName, error: e, stackTrace: st);
      }
    } else {
      step('skip proxy block: conversationId or jwt absent');
    }

    step('fallback direct/cloudinary');
    await _loadPdfDirect();
  }

  bool _looksLikePdf(Uint8List bytes) {
    if (bytes.length < 4) return false;
    return bytes[0] == 0x25 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x44 &&
        bytes[3] == 0x46; // %PDF
  }

  List<String> _buildDirectCandidates() {
    final initial = _normalizeDirectFetchUrl(ApiService.resolveMediaUrl(widget.pdfUrl));
    if (initial.isEmpty) return const [];
    final candidates = <String>{initial};
    if (initial.contains('/raw/upload/')) {
      candidates.add(initial.replaceFirst('/raw/upload/', '/raw/upload/fl_inline/'));
    } else if (initial.contains('/raw/upload/fl_inline/')) {
      candidates.add(initial.replaceFirst('/raw/upload/fl_inline/', '/raw/upload/'));
    }
    if (initial.contains('/video/upload/')) {
      candidates.add(initial.replaceFirst('/video/upload/', '/video/upload/fl_inline/'));
    } else if (initial.contains('/video/upload/fl_inline/')) {
      candidates.add(initial.replaceFirst('/video/upload/fl_inline/', '/video/upload/'));
    }
    return candidates.toList();
  }

  Future<void> _loadPdfDirect() async {
    const logName = 'DoctorPrescriptionPdfViewer';
    final candidates = _buildDirectCandidates();
    if (candidates.isEmpty) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Lien du document indisponible.';
      });
      return;
    }

    Object? lastError;
    for (final url in candidates) {
      debugPrint('[DoctorPrescriptionPdfViewer] direct try -> $url');
      try {
        final uri = Uri.parse(url);
        final response = await http.get(uri);
        debugPrint(
          '[DoctorPrescriptionPdfViewer] direct response ${response.statusCode} bytes=${response.bodyBytes.length} url=$url',
        );
        if (!mounted) return;
        if (response.statusCode == 200 &&
            response.bodyBytes.isNotEmpty &&
            _looksLikePdf(response.bodyBytes)) {
          setState(() {
            _bytes = Uint8List.fromList(response.bodyBytes);
            _loading = false;
          });
          return;
        }
        lastError = 'HTTP ${response.statusCode} (${response.bodyBytes.length} octets)';
      } catch (e, st) {
        lastError = e;
        dev.log(
          'Direct fetch failed',
          name: logName,
          error: e,
          stackTrace: st,
        );
      }
    }

    if (!mounted) return;
    setState(() {
      _loading = false;
      _error =
          'Impossible de charger le PDF. Vérifiez la signature du lien Cloudinary ou ouvrez dans le navigateur.';
    });
    debugPrint('[DoctorPrescriptionPdfViewer] direct fallback failed: $lastError');
  }

  Future<void> _openInBrowser() async {
    final candidates = _buildDirectCandidates();
    for (final candidate in candidates) {
      final uri = Uri.tryParse(candidate);
      if (uri == null) continue;
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (ok) return;
    }
  }

  Future<void> _openInExternalPdfApp() async {
    if (kIsWeb) return;
    final candidates = _buildDirectCandidates();
    for (final candidate in candidates) {
      final uri = Uri.tryParse(candidate);
      if (uri == null) continue;
      final ok = await launchUrl(uri, mode: LaunchMode.externalNonBrowserApplication);
      if (ok) return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: HeadsAppColors.brandPrimary,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: Text(widget.title),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline_rounded, size: 48, color: Colors.grey.shade600),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade800, height: 1.35),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => unawaited(_loadPdf()),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Réessayer'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _openInBrowser,
                icon: const Icon(Icons.open_in_browser_rounded),
                label: const Text('Ouvrir dans le navigateur'),
              ),
              if (!kIsWeb) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _openInExternalPdfApp,
                  icon: const Icon(Icons.picture_as_pdf_rounded),
                  label: const Text('Ouvrir avec une app PDF'),
                ),
              ],
            ],
          ),
        ),
      );
    }
    final bytes = _bytes;
    if (bytes == null || bytes.isEmpty) {
      return const Center(child: Text('Aucune donnée PDF.'));
    }
    if (kIsWeb) {
      return Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: HeadsAppColors.brandHighlight,
              borderRadius: BorderRadius.circular(HeadsAppMetrics.compactRadius),
            ),
            child: const Text(
              'Si l’aperçu reste vide sur le navigateur, ouvrez le document dans un nouvel onglet.',
              style: TextStyle(fontSize: 13.5),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _webOpenInProgress
                    ? null
                    : () async {
                        setState(() => _webOpenInProgress = true);
                        try {
                          await openPdfBytesInNewTab(bytes, filename: 'ordonnance.pdf');
                        } finally {
                          if (mounted) setState(() => _webOpenInProgress = false);
                        }
                      },
                icon: const Icon(Icons.open_in_new_rounded),
                label: Text(_webOpenInProgress ? 'Ouverture…' : 'Ouvrir dans un nouvel onglet'),
              ),
            ),
          ),
          Expanded(
            child: SfPdfViewer.memory(
              bytes,
              canShowPaginationDialog: false,
              canShowScrollHead: false,
            ),
          ),
        ],
      );
    }
    return Stack(
      children: [
        SfPdfViewer.memory(
          bytes,
          canShowPaginationDialog: false,
          canShowScrollHead: false,
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FloatingActionButton.extended(
                heroTag: 'open_browser',
                onPressed: _openInBrowser,
                icon: const Icon(Icons.open_in_browser_rounded),
                label: const Text('Navigateur'),
              ),
              if (!kIsWeb) ...[
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'open_external_pdf_app',
                  onPressed: _openInExternalPdfApp,
                  child: const Icon(Icons.picture_as_pdf_rounded),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
