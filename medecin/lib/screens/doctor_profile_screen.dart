import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../headsapp_theme.dart';
import '../services/api_service.dart';
import '../utils/doctor_session_utils.dart';
import '../utils/doctor_ui_utils.dart';
import '../widgets/auth_ui_widgets.dart';

class DoctorProfileScreen extends StatefulWidget {
  const DoctorProfileScreen({super.key, required this.doctorId});

  final String doctorId;

  @override
  State<DoctorProfileScreen> createState() => _DoctorProfileScreenState();
}

class _DoctorProfileScreenState extends State<DoctorProfileScreen> {
  static const Color _titleNavy = Color(0xFF1A4D8C);
  static const Color _fieldFill = Color(0xFFF0F4F8);
  static const Color _labelColor = Color(0xFF7B8BA3);
  static const Color _buttonBlue = Color(0xFF265AA6);

  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  final _orderController = TextEditingController();
  final _yearsExperienceController = TextEditingController();
  final _hospitalOrClinicController = TextEditingController();

  String? _specialty;
  String? _governorate;
  String _country = 'Tunisie';
  String _email = '';
  String? _photoPath;
  bool _loading = true;
  bool _saving = false;
  bool _uploadingPhoto = false;

  static const List<String> _countries = [
    'Tunisie',
    'France',
    'Belgique',
    'Suisse',
    'Algérie',
    'Maroc',
    'Italie',
    'Canada',
    'Royaume-Uni',
  ];

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _orderController.dispose();
    _yearsExperienceController.dispose();
    _hospitalOrClinicController.dispose();
    super.dispose();
  }

  void _splitFullName(String fullName) {
    final parts =
        fullName.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) {
      _firstNameController.clear();
      _lastNameController.clear();
    } else if (parts.length == 1) {
      _firstNameController.text = parts.first;
      _lastNameController.clear();
    } else {
      _firstNameController.text = parts.first;
      _lastNameController.text = parts.sublist(1).join(' ');
    }
  }

  String get _fullName =>
      '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}'
          .trim();

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final p = await ApiService.getDoctorProfile(widget.doctorId);
      if (!mounted) return;
      _splitFullName(readableDoctorName(p['fullName']?.toString(), fallback: ''));
      _email = readableDecryptedField(p['email']?.toString());
      _addressController.text = readableDecryptedField(p['address']?.toString());
      _phoneController.text = readableDecryptedField(p['phone']?.toString());
      _orderController.text = (p['orderNumber'] ?? '').toString();
      _yearsExperienceController.text =
          (p['yearsExperience'] == null ? '' : p['yearsExperience'].toString());
      _hospitalOrClinicController.text = (p['hospitalOrClinic'] ?? '').toString();
      final specialty = readableDecryptedField(p['specialty']?.toString());
      _specialty = specialty.isEmpty ? null : specialty;
      final gov = readableDecryptedField(p['governorate']?.toString());
      _governorate = gov.isEmpty ? null : gov;
      final c = readableDecryptedField(p['country']?.toString());
      if (c.isNotEmpty) _country = c;
      _photoPath = p['photoPath']?.toString();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String? _photoUrl() {
    if (_photoPath == null || _photoPath!.trim().isEmpty) return null;
    return ApiService.resolveMediaUrl(_photoPath);
  }

  Future<void> _pickAndUploadPhoto() async {
    final picker = ImagePicker();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('Choisir depuis la galerie'),
              onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded),
              title: const Text('Prendre une photo'),
              onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final f = await picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1400,
    );
    if (f == null) return;
    setState(() => _uploadingPhoto = true);
    try {
      final data = await ApiService.uploadDoctorPhotoXFile(
        doctorId: widget.doctorId,
        file: f,
      );
      if (!mounted) return;
      setState(() {
        _photoPath = data['photoPath']?.toString();
        _uploadingPhoto = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Photo mise à jour.')),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _uploadingPhoto = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_specialty == null || _governorate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Spécialité et gouvernorat requis.')),
      );
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    try {
      await ApiService.patchDoctorProfile(
        doctorId: widget.doctorId,
        fullName: _fullName,
        specialty: _specialty,
        governorate: _governorate,
        address: _addressController.text.trim(),
        phone: _phoneController.text.replaceAll(' ', ''),
        orderNumber:
            _orderController.text.trim().isEmpty ? '' : _orderController.text.trim(),
        country: _country,
        yearsExperience: int.tryParse(_yearsExperienceController.text.trim()) ?? 0,
        hospitalOrClinic: _hospitalOrClinicController.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profil enregistré.')),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  InputDecoration _fieldDecoration({
    required String hint,
    IconData? prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: HeadsAppColors.textTertiary, fontSize: 15),
      prefixIcon: prefixIcon == null
          ? null
          : Icon(prefixIcon, color: HeadsAppColors.textTertiary, size: 20),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: _fieldFill,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: _titleNavy.withValues(alpha: 0.45)),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: HeadsAppColors.danger),
      ),
    );
  }

  Widget _buildPhotoSection() {
    final photoUrl = _photoUrl();
    return Column(
      children: [
        Stack(
          alignment: Alignment.bottomRight,
          children: [
            Container(
              width: 112,
              height: 112,
              decoration: BoxDecoration(
                color: HeadsAppColors.brandHighlight,
                shape: BoxShape.circle,
              ),
              child: ClipOval(
                child: photoUrl != null
                    ? Image.network(photoUrl, fit: BoxFit.cover)
                    : Center(
                        child: Icon(
                          Icons.person_rounded,
                          size: 52,
                          color: _titleNavy.withValues(alpha: 0.82),
                        ),
                      ),
              ),
            ),
            if (_uploadingPhoto)
              const Positioned.fill(
                child: Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Material(
                color: _titleNavy,
                shape: const CircleBorder(),
                child: InkWell(
                  onTap: _uploadingPhoto ? null : _pickAndUploadPhoto,
                  customBorder: const CircleBorder(),
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(
                      Icons.photo_camera_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: _uploadingPhoto ? null : _pickAndUploadPhoto,
          child: Text(
            _uploadingPhoto ? 'Envoi en cours…' : 'Modifier la photo de profil',
            style: const TextStyle(
              color: _titleNavy,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: HeadsAppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: HeadsAppColors.success.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.verified_user_outlined,
              color: HeadsAppColors.success,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Informations Professionnelles',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: HeadsAppColors.success,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Ces informations sont utilisées pour votre identification '
                  'professionnelle et la validation de votre compte médecin.',
                  style: TextStyle(
                    fontSize: 13,
                    color: HeadsAppColors.textSecondary,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          color: _titleNavy,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text(
          'Profil',
          style: TextStyle(
            color: _titleNavy,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _titleNavy))
          : Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(22, 8, 22, 20),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(child: _buildPhotoSection()),
                          const SizedBox(height: 24),
                          AuthLabeledField(
                            label: 'Nom',
                            labelUppercase: true,
                            labelColor: _labelColor,
                            child: TextFormField(
                              controller: _lastNameController,
                              textCapitalization: TextCapitalization.words,
                              decoration: _fieldDecoration(hint: ''),
                              validator: (v) =>
                                  v == null || v.trim().isEmpty ? 'Requis' : null,
                            ),
                          ),
                          const SizedBox(height: 16),
                          AuthLabeledField(
                            label: 'Prénom',
                            labelUppercase: true,
                            labelColor: _labelColor,
                            child: TextFormField(
                              controller: _firstNameController,
                              textCapitalization: TextCapitalization.words,
                              decoration: _fieldDecoration(hint: ''),
                              validator: (v) =>
                                  v == null || v.trim().isEmpty ? 'Requis' : null,
                            ),
                          ),
                          const SizedBox(height: 16),
                          AuthLabeledField(
                            label: 'Email pro',
                            labelUppercase: true,
                            labelColor: _labelColor,
                            child: InputDecorator(
                              decoration: _fieldDecoration(
                                hint: '—',
                                prefixIcon: Icons.mail_outline_rounded,
                              ),
                              child: Text(
                                _email.isEmpty ? '—' : _email,
                                style: TextStyle(
                                  fontSize: 15,
                                  color: _email.isEmpty
                                      ? HeadsAppColors.textTertiary
                                      : HeadsAppColors.textPrimary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          AuthLabeledField(
                            label: 'Téléphone',
                            labelUppercase: true,
                            labelColor: _labelColor,
                            child: TextFormField(
                              controller: _phoneController,
                              keyboardType: TextInputType.phone,
                              decoration: _fieldDecoration(
                                hint: '',
                                prefixIcon: Icons.phone_outlined,
                              ),
                              validator: (v) =>
                                  v == null || v.trim().isEmpty ? 'Requis' : null,
                            ),
                          ),
                          const SizedBox(height: 16),
                          AuthLabeledField(
                            label: 'Numéro RPPS',
                            labelUppercase: true,
                            labelColor: _labelColor,
                            child: TextFormField(
                              controller: _orderController,
                              decoration: _fieldDecoration(
                                hint: '',
                                prefixIcon: Icons.badge_outlined,
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          _buildInfoCard(),
                          const SizedBox(height: 24),
                          AuthLabeledField(
                            label: 'Spécialité',
                            labelUppercase: true,
                            labelColor: _labelColor,
                            child: DropdownButtonFormField<String>(
                              value: _specialty,
                              decoration: _fieldDecoration(hint: ''),
                              hint: const Text('Choisir une spécialité'),
                              items: [
                                ...kSpecialties.map(
                                  (s) => DropdownMenuItem(value: s, child: Text(s)),
                                ),
                                if (_specialty != null &&
                                    !kSpecialties.contains(_specialty))
                                  DropdownMenuItem(
                                    value: _specialty,
                                    child: Text(_specialty!),
                                  ),
                              ],
                              onChanged: (v) => setState(() => _specialty = v),
                            ),
                          ),
                          const SizedBox(height: 16),
                          AuthLabeledField(
                            label: 'Gouvernorat',
                            labelUppercase: true,
                            labelColor: _labelColor,
                            child: DropdownButtonFormField<String>(
                              value: _governorate,
                              decoration: _fieldDecoration(hint: ''),
                              hint: const Text('Choisir un gouvernorat'),
                              items: [
                                ...kGovernorates.map(
                                  (g) => DropdownMenuItem(value: g, child: Text(g)),
                                ),
                                if (_governorate != null &&
                                    !kGovernorates.contains(_governorate))
                                  DropdownMenuItem(
                                    value: _governorate,
                                    child: Text(_governorate!),
                                  ),
                              ],
                              onChanged: (v) => setState(() => _governorate = v),
                            ),
                          ),
                          const SizedBox(height: 16),
                          AuthLabeledField(
                            label: 'Années d\'expérience',
                            labelUppercase: true,
                            labelColor: _labelColor,
                            child: TextFormField(
                              controller: _yearsExperienceController,
                              keyboardType: TextInputType.number,
                              decoration: _fieldDecoration(hint: ''),
                              validator: (v) {
                                final n = int.tryParse((v ?? '').trim());
                                if (n == null || n < 0 || n > 80) {
                                  return 'Valeur invalide';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(height: 16),
                          AuthLabeledField(
                            label: 'Hôpital ou clinique (optionnel)',
                            labelUppercase: true,
                            labelColor: _labelColor,
                            child: TextFormField(
                              controller: _hospitalOrClinicController,
                              decoration: _fieldDecoration(hint: ''),
                            ),
                          ),
                          const SizedBox(height: 16),
                          AuthLabeledField(
                            label: 'Adresse',
                            labelUppercase: true,
                            labelColor: _labelColor,
                            child: TextFormField(
                              controller: _addressController,
                              maxLines: 3,
                              decoration: _fieldDecoration(hint: ''),
                              validator: (v) =>
                                  v == null || v.trim().isEmpty ? 'Requis' : null,
                            ),
                          ),
                          const SizedBox(height: 16),
                          AuthLabeledField(
                            label: 'Pays',
                            labelUppercase: true,
                            labelColor: _labelColor,
                            child: DropdownButtonFormField<String>(
                              value: _country,
                              decoration: _fieldDecoration(hint: ''),
                              items: _countries
                                  .map(
                                    (c) => DropdownMenuItem(
                                      value: c,
                                      child: Text(c),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) {
                                if (v != null) setState(() => _country = v);
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 8, 22, 20),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox.shrink()
                          : const Icon(Icons.save_outlined, size: 20),
                      label: _saving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Enregistrer les modifications',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                      style: FilledButton.styleFrom(
                        backgroundColor: _buttonBlue,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor:
                            _buttonBlue.withValues(alpha: 0.55),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
