import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import 'headsapp_theme.dart';
import 'services/api_service.dart';
import 'utils/patient_ui_utils.dart';
import 'widgets/medical_dossier_file_viewer.dart';

class DossierMedicalPage extends StatefulWidget {
  const DossierMedicalPage({
    super.key,
    required this.patientId,
  });

  final String patientId;

  @override
  State<DossierMedicalPage> createState() => _DossierMedicalPageState();
}

enum MedicalCategory {
  analyses,
  ordonnances,
  fichiers,
  images,
}

extension on MedicalCategory {
  String get apiKey => switch (this) {
        MedicalCategory.analyses => 'analyses',
        MedicalCategory.ordonnances => 'ordonnances',
        MedicalCategory.fichiers => 'fichiers',
        MedicalCategory.images => 'images',
      };

  String get label => switch (this) {
        MedicalCategory.analyses => 'Analyses',
        MedicalCategory.ordonnances => 'Ordonnances',
        MedicalCategory.fichiers => 'Fichiers',
        MedicalCategory.images => 'Images',
      };

  String get hint => switch (this) {
        MedicalCategory.analyses =>
          'PDF, JPG, PNG — résultats d\'analyses, imagerie, etc.',
        MedicalCategory.ordonnances =>
          'PDF, JPG, PNG — ordonnances de tout médecin.',
        MedicalCategory.fichiers =>
          'PDF, Word, Excel, texte — comptes rendus, certificats…',
        MedicalCategory.images => 'JPG, PNG — photos médicales.',
      };

  List<String> get pickExtensions {
    switch (this) {
      case MedicalCategory.analyses:
      case MedicalCategory.ordonnances:
        return ['pdf', 'jpg', 'jpeg', 'png'];
      case MedicalCategory.fichiers:
        return ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'txt'];
      case MedicalCategory.images:
        return ['jpg', 'jpeg', 'png'];
    }
  }

  String get acceptedFormatsShort {
    switch (this) {
      case MedicalCategory.analyses:
      case MedicalCategory.ordonnances:
        return 'PDF, JPG, PNG';
      case MedicalCategory.fichiers:
        return 'PDF, Word, Excel, texte';
      case MedicalCategory.images:
        return 'JPG, PNG';
    }
  }
}

enum _ImportSource { deviceFiles, gallery, camera }

class _DossierMedicalPageState extends State<DossierMedicalPage>
    with SingleTickerProviderStateMixin {
  static const Color _surface = HeadsAppColors.surfaceAlt;
  static const Color _primary = HeadsAppColors.brandAccent;
  static const Color _primaryDark = HeadsAppColors.brandPrimary;
  static const Color _accent = HeadsAppColors.danger;

  final TextEditingController _searchCtrl = TextEditingController();
  late TabController _tabController;

  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;
  bool _uploading = false;
  String _effectivePatientId = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _boot();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _tabController.dispose();
    super.dispose();
  }

  bool _isObjectId(String value) => RegExp(r'^[0-9a-fA-F]{24}$').hasMatch(value);

  String _patientIdFromJwt(String? jwt) {
    final token = (jwt ?? '').trim();
    if (token.isEmpty) return '';
    try {
      final parts = token.split('.');
      if (parts.length < 2) return '';
      var payload = parts[1].replaceAll('-', '+').replaceAll('_', '/');
      while (payload.length % 4 != 0) {
        payload += '=';
      }
      final decoded = utf8.decode(base64Decode(payload));
      final json = jsonDecode(decoded);
      if (json is! Map) return '';
      final sub = (json['sub'] ?? '').toString().trim();
      return _isObjectId(sub) ? sub : '';
    } catch (_) {
      return '';
    }
  }

  Future<void> _boot() async {
    final fromWidget = widget.patientId.trim();
    var resolved = fromWidget;
    final prefs = await SharedPreferences.getInstance();
    if (!_isObjectId(resolved)) {
      final fromPrefs = (prefs.getString('patientId') ?? '').trim();
      if (_isObjectId(fromPrefs)) resolved = fromPrefs;
    }
    if (!_isObjectId(resolved)) {
      final fromJwtPref = _patientIdFromJwt(prefs.getString('patient_jwt'));
      if (_isObjectId(fromJwtPref)) resolved = fromJwtPref;
    }
    if (!_isObjectId(resolved)) {
      final fromJwtMem = _patientIdFromJwt(ApiService.jwtToken);
      if (_isObjectId(fromJwtMem)) resolved = fromJwtMem;
    }
    if (!mounted) return;
    if (!_isObjectId(resolved)) {
      setState(() {
        _loading = false;
        _error = 'Session patient invalide. Reconnectez-vous.';
      });
      return;
    }
    setState(() => _effectivePatientId = resolved);
    await _load();
  }

  Future<void> _load() async {
    if (!_isObjectId(_effectivePatientId)) {
      setState(() {
        _loading = false;
        _error = 'patientId invalide.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await ApiService.getPatientMedicalDossier(
        patientId: _effectivePatientId,
      );
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  List<Map<String, dynamic>> _itemsForCategory(MedicalCategory cat) {
    final key = cat.apiKey;
    final q = _searchCtrl.text.trim().toLowerCase();
    return _items.where((it) {
      if ((it['category']?.toString() ?? '') != key) return false;
      if (q.isEmpty) return true;
      final title = (it['title']?.toString() ?? '').toLowerCase();
      final name = (it['filename']?.toString() ?? '').toLowerCase();
      return title.contains(q) || name.contains(q);
    }).toList();
  }

  String _categoryLabel(String? apiKey) {
    for (final c in MedicalCategory.values) {
      if (c.apiKey == apiKey) return c.label;
    }
    return (apiKey != null && apiKey.isNotEmpty) ? apiKey : '—';
  }

  String _displayName(Map<String, dynamic> it) {
    final t = it['title']?.toString().trim() ?? '';
    if (t.isNotEmpty) return t;
    return it['filename']?.toString() ?? 'Document';
  }

  String _fmtDate(String? raw) {
    if (raw == null || raw.isEmpty) return '—';
    final dt = DateTime.tryParse(raw)?.toLocal();
    if (dt == null) return '—';
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final y = dt.year.toString();
    return '$d/$m/$y';
  }

  String _dateLine(Map<String, dynamic> it) {
    final doc = it['documentDate']?.toString();
    if (doc != null && doc.isNotEmpty) {
      return 'Date document : ${_fmtDate(doc)}';
    }
    return 'Ajouté le ${_fmtDate(it['createdAt']?.toString())}';
  }

  String _fmtSize(num? bytes) {
    final b = (bytes ?? 0).toDouble();
    if (b <= 0) return '—';
    if (b < 1024) return '${b.toStringAsFixed(0)} o';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} Ko';
    return '${(b / (1024 * 1024)).toStringAsFixed(1)} Mo';
  }

  IconData _iconForFilename(String filename, bool isImage) {
    if (isImage) return Icons.image_rounded;
    final f = filename.toLowerCase();
    if (f.endsWith('.pdf')) return Icons.picture_as_pdf_rounded;
    if (f.endsWith('.doc') || f.endsWith('.docx')) {
      return Icons.description_rounded;
    }
    if (f.endsWith('.xls') || f.endsWith('.xlsx')) {
      return Icons.table_chart_rounded;
    }
    return Icons.insert_drive_file_rounded;
  }

  Future<void> _openInAppViewer(Map<String, dynamic> item) async {
    final url = item['url']?.toString() ?? '';
    final name = item['filename']?.toString() ?? 'fichier';
    if (url.isEmpty || !mounted) return;
    final browserRaw = item['browserUrl']?.toString().trim();
    await showMedicalDossierFileViewer(
      context,
      resolvedUrl: ApiService.resolveMediaUrl(url),
      filename: name,
      isImageType: (item['type']?.toString() ?? '') == 'image',
      urlForExternalBrowser:
          browserRaw != null && browserRaw.isNotEmpty ? ApiService.resolveMediaUrl(browserRaw) : null,
    );
  }

  Future<void> _deleteItem(Map<String, dynamic> item) async {
    final id = item['id']?.toString() ?? '';
    if (id.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer ce document ?'),
        content: const Text(
          'Le fichier sera retiré de votre dossier médical personnel.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: _accent),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await ApiService.deletePatientMedicalDocument(
      patientId: _effectivePatientId,
      documentId: id,
    );
    if (!mounted) return;
    setState(() {
      _items.removeWhere((e) => (e['id']?.toString() ?? '') == id);
    });
  }

  bool _fileMatchesCategory(MedicalCategory cat, String filename) {
    final lower = filename.toLowerCase();
    final dot = lower.lastIndexOf('.');
    if (dot < 0 || dot >= lower.length - 1) return false;
    final ext = lower.substring(dot + 1);
    return cat.pickExtensions.contains(ext);
  }

  List<PlatformFile> _filterByCategory(MedicalCategory cat, List<PlatformFile> files) {
    return files.where((f) => _fileMatchesCategory(cat, f.name)).toList();
  }

  Future<PlatformFile> _platformFileFromXFile(XFile x) async {
    final bytes = await x.readAsBytes();
    var name = x.name.trim();
    if (name.isEmpty) {
      name = 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
    }
    return PlatformFile(name: name, size: bytes.length, bytes: bytes);
  }

  Future<List<PlatformFile>?> _pickFilesFromDevice(MedicalCategory cat) async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: cat.pickExtensions,
      allowMultiple: true,
      withData: kIsWeb,
    );
    if (res == null || res.files.isEmpty) return null;
    return res.files;
  }

  Future<List<PlatformFile>?> _pickFromGallery() async {
    final picker = ImagePicker();
    final list = await picker.pickMultiImage(
      imageQuality: 85,
      maxWidth: 4096,
    );
    if (list.isEmpty) return null;
    final out = <PlatformFile>[];
    for (final x in list) {
      out.add(await _platformFileFromXFile(x));
    }
    return out;
  }

  Future<List<PlatformFile>?> _pickFromCamera() async {
    final picker = ImagePicker();
    final x = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
      maxWidth: 4096,
    );
    if (x == null) return null;
    return [await _platformFileFromXFile(x)];
  }

  Future<void> _pickAndUpload(MedicalCategory cat) async {
    if (_uploading) return;
    if (!mounted) return;

    final source = await showModalBottomSheet<_ImportSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Text(
                  'Importer vers « ${cat.label} »',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              ListTile(
                leading: Icon(Icons.folder_open_rounded, color: _primaryDark),
                title: const Text('Fichiers de l\'appareil'),
                subtitle: Text(
                  'PDF, images, documents (${cat.acceptedFormatsShort})',
                  style: const TextStyle(fontSize: 12),
                ),
                onTap: () => Navigator.of(ctx).pop(_ImportSource.deviceFiles),
              ),
              ListTile(
                leading: Icon(Icons.photo_library_rounded, color: _primaryDark),
                title: const Text('Galerie photos'),
                subtitle: const Text('Choisir une ou plusieurs photos', style: TextStyle(fontSize: 12)),
                onTap: () => Navigator.of(ctx).pop(_ImportSource.gallery),
              ),
              ListTile(
                leading: Icon(Icons.photo_camera_rounded, color: _primaryDark),
                title: const Text('Appareil photo'),
                subtitle: const Text('Prendre une photo', style: TextStyle(fontSize: 12)),
                onTap: () => Navigator.of(ctx).pop(_ImportSource.camera),
              ),
            ],
          ),
        ),
      ),
    );
    if (source == null || !mounted) return;

    List<PlatformFile>? raw;
    switch (source) {
      case _ImportSource.deviceFiles:
        raw = await _pickFilesFromDevice(cat);
        break;
      case _ImportSource.gallery:
        raw = await _pickFromGallery();
        break;
      case _ImportSource.camera:
        raw = await _pickFromCamera();
        break;
    }
    if (raw == null || raw.isEmpty || !mounted) return;

    final allowed = _filterByCategory(cat, raw);
    if (allowed.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Aucun fichier compatible avec cette catégorie. Formats acceptés : ${cat.acceptedFormatsShort}.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (allowed.length < raw.length && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Certains fichiers ont été ignorés (extension non acceptée pour cet onglet).'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmer l\'ajout'),
        content: Text(
          allowed.length == 1
              ? 'Ajouter « ${allowed.first.name} » à « ${cat.label} » ?'
              : 'Ajouter ${allowed.length} fichiers à « ${cat.label} » ?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: _primaryDark),
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _uploading = true);
    var okCount = 0;
    String? lastError;
    try {
      for (final f in allowed) {
        try {
          await ApiService.uploadPatientMedicalDocument(
            patientId: _effectivePatientId,
            category: cat.apiKey,
            file: f,
            title: null,
            documentDate: null,
          );
          okCount++;
        } catch (e) {
          lastError = e.toString().replaceFirst('Exception: ', '');
        }
      }
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      if (okCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              okCount == 1
                  ? 'Document ajouté à votre dossier.'
                  : '$okCount documents ajoutés à votre dossier.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      if (lastError != null && okCount < allowed.length) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(lastError),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _openShareModal() async {
    final selected = <String>{};
    String? selectedDoctorId;
    String selectedDoctorName = '';
    String doctorQuery = '';
    List<Map<String, dynamic>> doctors = [];
    bool loadingDoctors = true;
    String? doctorError;

    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            Future<void> loadDoctorsIfNeeded() async {
              if (!loadingDoctors || doctors.isNotEmpty || doctorError != null) return;
              try {
                final list = await ApiService.getDoctors();
                if (!mounted) return;
                setLocal(() {
                  doctors = list;
                  loadingDoctors = false;
                });
              } catch (e) {
                setLocal(() {
                  loadingDoctors = false;
                  doctorError = e.toString().replaceFirst('Exception: ', '');
                });
              }
            }

            loadDoctorsIfNeeded();
            final visibleDoctors = doctors.where((d) {
              final n = readableDoctorName(d['fullName']?.toString(), fallback: '').toLowerCase();
              final s = (d['specialty']?.toString() ?? '').toLowerCase();
              final q = doctorQuery.toLowerCase();
              return q.isEmpty || n.contains(q) || s.contains(q);
            }).toList();

            final selectable = _items;

            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 560, maxHeight: 680),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Partager avec un médecin',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const Text(
                      'Les fichiers sélectionnés seront envoyés dans le chat avec le médecin choisi.',
                      style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      onChanged: (v) => setLocal(() => doctorQuery = v),
                      decoration: const InputDecoration(
                        hintText: 'Rechercher un médecin...',
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (loadingDoctors)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (doctorError != null)
                      Text(doctorError!, style: const TextStyle(color: Colors.red))
                    else
                      SizedBox(
                        height: 140,
                        child: ListView.builder(
                          itemCount: visibleDoctors.length,
                          itemBuilder: (_, i) {
                            final d = visibleDoctors[i];
                            final id = d['id']?.toString() ?? '';
                            final selectedNow = selectedDoctorId == id;
                            return ListTile(
                              selected: selectedNow,
                              selectedTileColor: _primary.withValues(alpha: 0.15),
                              leading: CircleAvatar(
                                backgroundColor: _primary.withValues(alpha: 0.25),
                                backgroundImage: (d['photoPath']?.toString().isNotEmpty == true)
                                    ? NetworkImage(
                                        ApiService.resolveMediaUrl(d['photoPath'].toString()),
                                      )
                                    : null,
                                child: (d['photoPath']?.toString().isNotEmpty == true)
                                    ? null
                                    : const Icon(Icons.person_rounded),
                              ),
                              title: Text(readableDoctorName(d['fullName']?.toString())),
                              subtitle: Text(
                                readableDecryptedField(
                                  d['specialty']?.toString(),
                                  fallback: '—',
                                ),
                              ),
                              onTap: () {
                                setLocal(() {
                                  selectedDoctorId = id;
                                  selectedDoctorName = readableDoctorName(d['fullName']?.toString());
                                });
                              },
                            );
                          },
                        ),
                      ),
                    const Divider(height: 18),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () {
                            setLocal(() {
                              selected
                                ..clear()
                                ..addAll(
                                  selectable
                                      .map((e) => e['id']?.toString() ?? '')
                                      .where((e) => e.isNotEmpty),
                                );
                            });
                          },
                          child: const Text('Tout sélectionner'),
                        ),
                        TextButton(
                          onPressed: () => setLocal(selected.clear),
                          child: const Text('Tout désélectionner'),
                        ),
                      ],
                    ),
                    Expanded(
                      child: ListView(
                        children: selectable.map((it) {
                          final id = it['id']?.toString() ?? '';
                          final catLabel = _categoryLabel(it['category']?.toString());
                          return CheckboxListTile(
                            value: selected.contains(id),
                            onChanged: (_) {
                              setLocal(() {
                                if (selected.contains(id)) {
                                  selected.remove(id);
                                } else if (id.isNotEmpty) {
                                  selected.add(id);
                                }
                              });
                            },
                            title: Text(
                              _displayName(it),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text('$catLabel • ${_fmtSize(it['size'] as num?)}'),
                            controlAffinity: ListTileControlAffinity.leading,
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: _primary.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${selected.length} sélectionné(s)',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _primaryDark,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: selectedDoctorId == null || selected.isEmpty
                            ? null
                            : () async {
                                try {
                                  final result = await ApiService.sharePatientMedicalDossier(
                                    patientId: _effectivePatientId,
                                    doctorId: selectedDoctorId!,
                                    itemIds: selected.toList(),
                                  );
                                  if (!mounted || !context.mounted) return;
                                  if (!ctx.mounted) return;
                                  Navigator.of(ctx).pop();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Envoyé à Dr. ${readableDoctorName(result['doctorName']?.toString(), fallback: selectedDoctorName)} (${result['sharedCount'] ?? selected.length} fichier(s)).',
                                      ),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                } catch (e) {
                                  if (!mounted || !context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        e.toString().replaceFirst('Exception: ', ''),
                                      ),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                }
                              },
                        icon: const Icon(Icons.send_rounded),
                        style: FilledButton.styleFrom(
                          backgroundColor: _primaryDark,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        label: Text(
                          selected.isEmpty
                              ? 'Envoyer au médecin'
                              : 'Envoyer au médecin (${selected.length})',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  MedicalCategory get _currentCategory => MedicalCategory.values[_tabController.index];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surface,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
          tooltip: 'Retour',
        ),
        title: const Text('Dossier médical personnel'),
        centerTitle: true,
        backgroundColor: _primaryDark,
        foregroundColor: Colors.white,
        bottom: _loading || _error != null
            ? null
            : TabBar(
                controller: _tabController,
                isScrollable: true,
                indicatorColor: Colors.white,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                tabs: [
                  for (final c in MedicalCategory.values) Tab(text: c.label),
                ],
              ),
      ),
      floatingActionButton: _loading || _error != null
          ? null
          : FloatingActionButton.extended(
              onPressed: _uploading ? null : () => _pickAndUpload(_currentCategory),
              backgroundColor: _primaryDark,
              foregroundColor: Colors.white,
              icon: _uploading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.add_rounded),
              label: Text(_uploading ? 'Envoi…' : 'Ajouter'),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Votre dossier vous appartient : ajoutez vos documents hors des conversations. '
                            'Vous pouvez les partager ensuite dans un chat médecin.',
                            style: TextStyle(fontSize: 13, color: Color(0xFF475569), height: 1.35),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _searchCtrl,
                                  onChanged: (_) => setState(() {}),
                                  decoration: InputDecoration(
                                    hintText: 'Rechercher dans l’onglet…',
                                    prefixIcon: const Icon(Icons.search_rounded),
                                    fillColor: Colors.white,
                                    filled: true,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: BorderSide.none,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              FilledButton.icon(
                                onPressed: _items.isEmpty ? null : _openShareModal,
                                icon: const Icon(Icons.share_rounded),
                                style: FilledButton.styleFrom(
                                  backgroundColor: _primaryDark,
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size(0, 42),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                ),
                                label: const Text('Partager'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          for (final c in MedicalCategory.values)
                            RefreshIndicator(
                              onRefresh: _load,
                              child: _buildCategoryBody(c),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildCategoryBody(MedicalCategory cat) {
    final list = _itemsForCategory(cat);
    final hint = cat.hint;

    if (list.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          Icon(Icons.folder_open_rounded, size: 56, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(
            'Aucun document dans « ${cat.label} ».',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            hint,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(hint, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
        ),
        for (final it in list)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _openInAppViewer(it),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Icon(
                          _iconForFilename(
                            it['filename']?.toString() ?? '',
                            (it['type']?.toString() ?? '') == 'image',
                          ),
                          color: _primaryDark,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _displayName(it),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${_categoryLabel(it['category']?.toString())} • ${_dateLine(it)} • ${_fmtSize(it['size'] as num?)}',
                              maxLines: 2,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Supprimer',
                        onPressed: () => _deleteItem(it),
                        icon: Icon(
                          Icons.delete_outline_rounded,
                          color: _accent.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
