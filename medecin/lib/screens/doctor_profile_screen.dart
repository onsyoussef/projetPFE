import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../headsapp_theme.dart';
import '../services/api_service.dart';
import '../utils/doctor_session_utils.dart';
import '../utils/doctor_ui_utils.dart';

class DoctorProfileScreen extends StatefulWidget {
  const DoctorProfileScreen({super.key, required this.doctorId});

  final String doctorId;

  @override
  State<DoctorProfileScreen> createState() => _DoctorProfileScreenState();
}

class _DoctorProfileScreenState extends State<DoctorProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  final _orderController = TextEditingController();
  final _yearsExperienceController = TextEditingController();
  final _hospitalOrClinicController = TextEditingController();

  String? _specialty;
  String? _governorate;
  String _country = 'Tunisie';
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
    _fullNameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _orderController.dispose();
    _yearsExperienceController.dispose();
    _hospitalOrClinicController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final p = await ApiService.getDoctorProfile(widget.doctorId);
      if (!mounted) return;
      _fullNameController.text = readableDoctorName(p['fullName']?.toString(), fallback: '');
      _addressController.text = readableDecryptedField(p['address']?.toString());
      _phoneController.text = readableDecryptedField(p['phone']?.toString());
      _orderController.text = (p['orderNumber'] ?? '').toString();
      _yearsExperienceController.text =
          (p['yearsExperience'] == null ? '' : p['yearsExperience'].toString());
      _hospitalOrClinicController.text = (p['hospitalOrClinic'] ?? '').toString();
      _specialty = readableDecryptedField(p['specialty']?.toString());
      _specialty = _specialty.isEmpty ? null : _specialty;
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
    final f = await picker.pickImage(source: source, imageQuality: 85, maxWidth: 1400);
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
        fullName: _fullNameController.text.trim(),
        specialty: _specialty,
        governorate: _governorate,
        address: _addressController.text.trim(),
        phone: _phoneController.text.replaceAll(' ', ''),
        orderNumber: _orderController.text.trim().isEmpty
            ? ''
            : _orderController.text.trim(),
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    const sky = HeadsAppColors.brandPrimary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestion du profil'),
        backgroundColor: sky,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          CircleAvatar(
                            radius: 56,
                            backgroundColor: sky.withValues(alpha: 0.2),
                            backgroundImage: _photoUrl() != null
                                ? NetworkImage(_photoUrl()!)
                                : null,
                            child: _photoUrl() == null
                                ? Text(
                                    doctorInitials(_fullNameController.text),
                                    style: const TextStyle(
                                      fontSize: 36,
                                      color: sky,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  )
                                : null,
                          ),
                          if (_uploadingPhoto)
                            const Positioned.fill(
                              child: Center(
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: TextButton.icon(
                        onPressed: _uploadingPhoto ? null : _pickAndUploadPhoto,
                        icon: const Icon(Icons.photo_camera_outlined),
                        label: Text(
                          _uploadingPhoto ? 'Envoi…' : 'Ajouter ou modifier la photo',
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _fullNameController,
                      decoration: const InputDecoration(
                        labelText: 'Nom et prénom',
                        border: OutlineInputBorder(),
                      ),
                      textCapitalization: TextCapitalization.words,
                      onChanged: (_) => setState(() {}),
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? 'Requis' : null,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _specialty,
                      decoration: const InputDecoration(
                        labelText: 'Spécialité',
                        border: OutlineInputBorder(),
                      ),
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
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _governorate,
                      decoration: const InputDecoration(
                        labelText: 'Gouvernorat',
                        border: OutlineInputBorder(),
                      ),
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
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _yearsExperienceController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Nombre d\'années d\'expérience',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        final n = int.tryParse((v ?? '').trim());
                        if (n == null || n < 0 || n > 80) return 'Valeur invalide';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _hospitalOrClinicController,
                      decoration: const InputDecoration(
                        labelText: 'Nom de l\'hôpital ou clinique',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? 'Requis' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _addressController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Adresse exacte',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? 'Requis' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Téléphone',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? 'Requis' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _orderController,
                      decoration: const InputDecoration(
                        labelText: 'N° d\'ordre (optionnel)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _country,
                      decoration: const InputDecoration(
                        labelText: 'Pays',
                        border: OutlineInputBorder(),
                      ),
                      items: _countries
                          .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setState(() => _country = v);
                      },
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFE1395F),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: _saving
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Enregistrer'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
