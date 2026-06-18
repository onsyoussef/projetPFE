import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import 'headsapp_theme.dart';
import 'services/api_service.dart';
import 'screens/share_doctor_picker_page.dart';
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

class _DossierMedicalPageState extends State<DossierMedicalPage> {
  static const Color _surface = Color(0xFFF5F7FB);
  static const Color _primary = HeadsAppColors.brandAccent;
  static const Color _primaryDark = HeadsAppColors.brandPrimary;
  static const Color _accent = HeadsAppColors.danger;
  static const Color _mutedText = Color(0xFF64748B);
  static const Color _chipInactive = Color(0xFFE8EEF5);
  static const Color _searchFill = Color(0xFFF0F4FA);

  final TextEditingController _searchCtrl = TextEditingController();

  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;
  bool _uploading = false;
  String _effectivePatientId = '';
  MedicalCategory? _filterCategory;
  final Set<String> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
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

  List<Map<String, dynamic>> _visibleItems() {
    final q = _searchCtrl.text.trim().toLowerCase();
    return _items.where((it) {
      if (_filterCategory != null &&
          (it['category']?.toString() ?? '') != _filterCategory!.apiKey) {
        return false;
      }
      if (q.isEmpty) return true;
      final title = (it['title']?.toString() ?? '').toLowerCase();
      final name = (it['filename']?.toString() ?? '').toLowerCase();
      return title.contains(q) || name.contains(q);
    }).toList();
  }

  String _displayName(Map<String, dynamic> it) {
    final t = it['title']?.toString().trim() ?? '';
    if (t.isNotEmpty) return t;
    return it['filename']?.toString() ?? 'Document';
  }

  String _fmtDateFrench(String? raw) {
    if (raw == null || raw.isEmpty) return '—';
    final dt = DateTime.tryParse(raw)?.toLocal();
    if (dt == null) return '—';
    const months = [
      'janvier',
      'février',
      'mars',
      'avril',
      'mai',
      'juin',
      'juillet',
      'août',
      'septembre',
      'octobre',
      'novembre',
      'décembre',
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  String _cardDate(Map<String, dynamic> it) {
    final doc = it['documentDate']?.toString();
    if (doc != null && doc.isNotEmpty) return _fmtDateFrench(doc);
    return _fmtDateFrench(it['createdAt']?.toString());
  }

  String _fileTypeLabel(Map<String, dynamic> it) {
    final isImage = (it['type']?.toString() ?? '') == 'image';
    if (isImage) return 'IMG';
    final name = (it['filename']?.toString() ?? '').toLowerCase();
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot >= name.length - 1) return 'DOC';
    final ext = name.substring(dot + 1).toUpperCase();
    return ext.length <= 5 ? ext : 'DOC';
  }

  Color _iconAccentForFile(Map<String, dynamic> it) {
    final label = _fileTypeLabel(it);
    if (label == 'PDF') return const Color(0xFFE53935);
    if (label == 'IMG' || label == 'JPG' || label == 'JPEG' || label == 'PNG') {
      return const Color(0xFF2563EB);
    }
    return _primaryDark;
  }

  Color _iconBgForFile(Map<String, dynamic> it) {
    final label = _fileTypeLabel(it);
    if (label == 'PDF') return const Color(0xFFFFEBEE);
    if (label == 'IMG' || label == 'JPG' || label == 'JPEG' || label == 'PNG') {
      return const Color(0xFFEFF6FF);
    }
    return _chipInactive;
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

  Future<void> _openShareModal({Set<String>? initialSelection}) async {
    final ids = initialSelection?.where((e) => e.isNotEmpty).toList() ?? const <String>[];
    if (ids.isEmpty) return;

    final shared = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ShareDoctorPickerPage(
          patientId: _effectivePatientId,
          selectedItemIds: ids,
        ),
      ),
    );
    if (shared == true && mounted) {
      setState(_selectedIds.clear);
    }
  }

  Future<void> _onAddTapped() async {
    if (_uploading) return;
    MedicalCategory? cat = _filterCategory;
    if (cat == null) {
      cat = await showModalBottomSheet<MedicalCategory>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: Text(
                  'Ajouter un document',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
              ),
              for (final c in MedicalCategory.values)
                ListTile(
                  leading: Icon(Icons.folder_open_rounded, color: _primaryDark),
                  title: Text(c.label),
                  subtitle: Text(c.hint, style: const TextStyle(fontSize: 12)),
                  onTap: () => Navigator.of(ctx).pop(c),
                ),
            ],
          ),
        ),
      );
    }
    if (cat != null && mounted) await _pickAndUpload(cat);
  }

  void _toggleSelection(String id) {
    if (id.isEmpty) return;
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            color: _primaryDark,
            onPressed: () => Navigator.of(context).maybePop(),
            tooltip: 'Retour',
          ),
          const Expanded(
            child: Text(
              'Mon dossier médical',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: _primaryDark,
              ),
            ),
          ),
          Material(
            color: _primaryDark,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: _uploading ? null : _onAddTapped,
              child: SizedBox(
                width: 40,
                height: 40,
                child: _uploading
                    ? const Padding(
                        padding: EdgeInsets.all(10),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.add_rounded, color: Colors.white, size: 26),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _FilterChip(
            label: 'Tout',
            selected: _filterCategory == null,
            onTap: () => setState(() => _filterCategory = null),
          ),
          for (final c in MedicalCategory.values)
            _FilterChip(
              label: c.label,
              selected: _filterCategory == c,
              onTap: () => setState(() => _filterCategory = c),
            ),
        ],
      ),
    );
  }

  Widget _buildDocumentCard(Map<String, dynamic> it) {
    final id = it['id']?.toString() ?? '';
    final selected = _selectedIds.contains(id);
    final iconColor = _iconAccentForFile(it);
    final iconBg = _iconBgForFile(it);
    final typeLabel = _fileTypeLabel(it);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _openInAppViewer(it),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _iconForFilename(
                      it['filename']?.toString() ?? '',
                      (it['type']?.toString() ?? '') == 'image',
                    ),
                    color: iconColor,
                    size: 26,
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
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: _primaryDark,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: _chipInactive,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              typeLabel,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: _mutedText,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _cardDate(it),
                            style: const TextStyle(fontSize: 12, color: _mutedText),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert_rounded, color: _primaryDark.withValues(alpha: 0.7)),
                  onSelected: (value) {
                    if (value == 'open') {
                      _openInAppViewer(it);
                    } else if (value == 'delete') {
                      _deleteItem(it);
                    }
                  },
                  itemBuilder: (ctx) => const [
                    PopupMenuItem(value: 'open', child: Text('Ouvrir')),
                    PopupMenuItem(value: 'delete', child: Text('Supprimer')),
                  ],
                ),
                GestureDetector(
                  onTap: () => _toggleSelection(id),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4, right: 4),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: selected ? _primaryDark : Colors.transparent,
                        border: Border.all(
                          color: selected ? _primaryDark : const Color(0xFFCBD5E1),
                          width: 2,
                        ),
                      ),
                      child: selected
                          ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
                          : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDocumentsList() {
    final list = _visibleItems();
    final hint = _filterCategory?.hint ??
        'Sélectionnez les documents de santé que vous souhaitez transmettre en toute sécurité.';

    if (list.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
        children: [
          Icon(Icons.folder_open_rounded, size: 56, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(
            _filterCategory == null
                ? 'Aucun document dans votre dossier.'
                : 'Aucun document dans « ${_filterCategory!.label} ».',
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

    return ListView.builder(
      padding: EdgeInsets.fromLTRB(16, 4, 16, _selectedIds.isNotEmpty ? 12 : 24),
      itemCount: list.length,
      itemBuilder: (_, i) => _buildDocumentCard(list[i]),
    );
  }

  Widget _buildShareBottomBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: SafeArea(
        top: false,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: const LinearGradient(
              colors: [
                Color(0xFFE8719A),
                Color(0xFF3B5998),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF3B5998).withValues(alpha: 0.22),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () => _openShareModal(initialSelection: _selectedIds),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Text(
                      'Partager avec un médecin',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(width: 10),
                    Icon(Icons.send_rounded, color: Colors.white, size: 22),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surface,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: _primaryDark))
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(_error!, textAlign: TextAlign.center),
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Padding(
                              padding: EdgeInsets.fromLTRB(20, 8, 20, 6),
                              child: Text(
                                'Partager mon dossier',
                                style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w800,
                                  color: _primaryDark,
                                  height: 1.15,
                                ),
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.fromLTRB(20, 0, 20, 16),
                              child: Text(
                                'Sélectionnez les documents de santé que vous souhaitez transmettre en toute sécurité.',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: _mutedText,
                                  height: 1.4,
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: TextField(
                                controller: _searchCtrl,
                                onChanged: (_) => setState(() {}),
                                decoration: InputDecoration(
                                  hintText: 'Rechercher un document...',
                                  hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 14),
                                  prefixIcon: Icon(Icons.search_rounded, color: Colors.grey.shade500),
                                  filled: true,
                                  fillColor: _searchFill,
                                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            _buildFilterChips(),
                            const SizedBox(height: 8),
                            Expanded(
                              child: RefreshIndicator(
                                color: _primaryDark,
                                onRefresh: _load,
                                child: _buildDocumentsList(),
                              ),
                            ),
                          ],
                        ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                return SizeTransition(
                  sizeFactor: animation,
                  axisAlignment: -1,
                  child: FadeTransition(opacity: animation, child: child),
                );
              },
              child: (!_loading && _error == null && _selectedIds.isNotEmpty)
                  ? KeyedSubtree(
                      key: const ValueKey('share-visible'),
                      child: _buildShareBottomBar(),
                    )
                  : const SizedBox.shrink(key: ValueKey('share-hidden')),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  static const Color _primaryDark = HeadsAppColors.brandPrimary;
  static const Color _chipInactive = Color(0xFFE8EEF5);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: selected ? _primaryDark : _chipInactive,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : _primaryDark,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
