import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'headsapp_theme.dart';
import 'services/api_service.dart';
import 'utils/patient_ui_utils.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({
    super.key,
    required this.patientName,
    required this.patientId,
  });

  final String patientName;
  final String patientId;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  static const Color _pageBg = Color(0xFFF1F5F9);
  static const Color _titleNavy = Color(0xFF1A458B);
  static const Color _subtitleGrey = Color(0xFF6B7280);
  static const Color _iconBlue = Color(0xFF1A458B);
  static const List<String> _bloodGroups = [
    '',
    'A+',
    'A-',
    'B+',
    'B-',
    'AB+',
    'AB-',
    'O+',
    'O-',
  ];

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;
  late final TextEditingController _addressController;
  late final TextEditingController _weightController;
  late final TextEditingController _heightController;
  late final TextEditingController _allergiesController;

  String? _photoPath;
  DateTime? _birthDate;
  DateTime? _memberSince;
  String? _sex;
  String? _bloodGroup;
  late String _savedName;

  bool _loading = true;
  bool _savingProfile = false;
  bool _uploadingPhoto = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: readablePatientName(widget.patientName),
    );
    _emailController = TextEditingController();
    _phoneController = TextEditingController();
    _addressController = TextEditingController();
    _weightController = TextEditingController();
    _heightController = TextEditingController();
    _allergiesController = TextEditingController();
    _savedName = readablePatientName(widget.patientName);
    _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _weightController.dispose();
    _heightController.dispose();
    _allergiesController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() => _loading = true);
    try {
      final profile =
          await ApiService.getPatientProfile(patientId: widget.patientId);
      if (!mounted) return;
      setState(() {
        _photoPath = profile['photoPath'] as String?;
        _emailController.text =
            readableDecryptedField(profile['email'] as String?);
        _phoneController.text =
            readableDecryptedField(profile['phone'] as String?);
        _addressController.text =
            readableDecryptedField(profile['addressExact'] as String?);
        final birthIso = profile['birthDate']?.toString();
        _birthDate = birthIso == null || birthIso.isEmpty
            ? null
            : DateTime.tryParse(birthIso)?.toLocal();
        final createdIso = profile['createdAt']?.toString();
        _memberSince = createdIso == null || createdIso.isEmpty
            ? null
            : DateTime.tryParse(createdIso)?.toLocal();
        final sexValue = profile['sex']?.toString().toLowerCase();
        _sex = (sexValue == 'homme' || sexValue == 'femme') ? sexValue : null;
        final bg = profile['bloodGroup']?.toString().trim();
        _bloodGroup = (bg != null && bg.isNotEmpty) ? bg : null;
        final weight = profile['weightKg'];
        final height = profile['heightCm'];
        _weightController.text =
            weight != null ? weight.toString().replaceAll('.0', '') : '';
        _heightController.text =
            height != null ? height.toString().replaceAll('.0', '') : '';
        _allergiesController.text =
            readableDecryptedField(profile['knownAllergies'] as String?);
        final fullName = readablePatientName(
          profile['fullName'] as String?,
          fallback: readablePatientName(widget.patientName),
        );
        _savedName = fullName;
        _nameController.text = fullName;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String? _photoUrl() => ApiService.resolveMediaUrlOrNull(_photoPath);

  int? _computeAge() {
    if (_birthDate == null) return null;
    final now = DateTime.now();
    var age = now.year - _birthDate!.year;
    if (now.month < _birthDate!.month ||
        (now.month == _birthDate!.month && now.day < _birthDate!.day)) {
      age--;
    }
    return age < 0 ? null : age;
  }

  String _formatPatientSince() {
    if (_memberSince == null) return 'Patient';
    const months = [
      'Janvier',
      'Février',
      'Mars',
      'Avril',
      'Mai',
      'Juin',
      'Juillet',
      'Août',
      'Septembre',
      'Octobre',
      'Novembre',
      'Décembre',
    ];
    return 'Patient depuis ${months[_memberSince!.month - 1]} ${_memberSince!.year}';
  }

  String _formatBirthDate() {
    if (_birthDate == null) return 'Sélectionner une date';
    final d = _birthDate!;
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    final newName = _nameController.text.trim();
    final newEmail = _emailController.text.trim();
    final newPhone = _phoneController.text.trim();
    final newAddress = _addressController.text.trim();
    final weightText = _weightController.text.trim();
    final heightText = _heightController.text.trim();
    num? weightKg;
    num? heightCm;
    if (weightText.isNotEmpty) {
      weightKg = num.tryParse(weightText.replaceAll(',', '.'));
    }
    if (heightText.isNotEmpty) {
      heightCm = num.tryParse(heightText.replaceAll(',', '.'));
    }

    setState(() => _savingProfile = true);
    try {
      await ApiService.updatePatientProfile(
        patientId: widget.patientId,
        fullName: newName,
        birthDateIso: _birthDate?.toUtc().toIso8601String(),
        sex: _sex,
        phone: newPhone,
        email: newEmail,
        addressExact: newAddress,
        bloodGroup: _bloodGroup ?? '',
        weightKg: weightKg,
        heightCm: heightCm,
        knownAllergies: _allergiesController.text.trim(),
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('patientName', newName);

      if (!mounted) return;
      setState(() => _savingProfile = false);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profil mis à jour.'),
          behavior: SnackBarBehavior.floating,
        ),
      );

      _savedName = newName;
      Navigator.of(context).pop({
        'patientName': newName,
        'photoPath': _photoPath,
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _savingProfile = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
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
    if (source == null || _uploadingPhoto) return;
    setState(() => _uploadingPhoto = true);

    try {
      final file = await picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1200,
      );
      if (file == null) {
        setState(() => _uploadingPhoto = false);
        return;
      }
      final response = await ApiService.uploadPatientPhotoXFile(
        patientId: widget.patientId,
        file: file,
      );
      if (!mounted) return;
      setState(() {
        _photoPath = response['photoPath'] as String?;
        _uploadingPhoto = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Photo mise à jour.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploadingPhoto = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(now.year - 25, now.month, now.day),
      firstDate: DateTime(1900),
      lastDate: now,
      locale: const Locale('fr'),
    );
    if (selected == null) return;
    setState(() => _birthDate = selected);
  }

  void _popWithResult() {
    Navigator.of(context).pop({
      'patientName': _savedName,
      'photoPath': _photoPath,
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final photoUrl = _photoUrl();
    final age = _computeAge();

    return Scaffold(
      backgroundColor: _pageBg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(4, 4, 12, 12),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      onPressed: _popWithResult,
                      icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                      color: _titleNavy,
                      tooltip: 'Retour',
                    ),
                  ),
                  Text(
                    'Mon profil',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: _titleNavy,
                      fontWeight: FontWeight.w700,
                      fontSize: 20,
                      letterSpacing: -0.2,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Center(
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  CircleAvatar(
                                    radius: 54,
                                    backgroundColor: const Color(0xFFE8F0FE),
                                    backgroundImage: photoUrl != null
                                        ? NetworkImage(photoUrl)
                                        : null,
                                    child: photoUrl == null
                                        ? const Icon(
                                            Icons.person_rounded,
                                            color: _iconBlue,
                                            size: 54,
                                          )
                                        : null,
                                  ),
                                  Positioned(
                                    right: 4,
                                    bottom: 4,
                                    child: Material(
                                      color: _titleNavy,
                                      shape: const CircleBorder(),
                                      child: InkWell(
                                        customBorder: const CircleBorder(),
                                        onTap: _uploadingPhoto
                                            ? null
                                            : _pickAndUploadPhoto,
                                        child: Padding(
                                          padding: const EdgeInsets.all(8),
                                          child: _uploadingPhoto
                                              ? const SizedBox(
                                                  width: 16,
                                                  height: 16,
                                                  child:
                                                      CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                    color: Colors.white,
                                                  ),
                                                )
                                              : const Icon(
                                                  Icons.edit_rounded,
                                                  color: Colors.white,
                                                  size: 16,
                                                ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _nameController.text.trim().isEmpty
                                  ? readablePatientName(widget.patientName)
                                  : _nameController.text.trim(),
                              textAlign: TextAlign.center,
                              style: theme.textTheme.titleLarge?.copyWith(
                                color: _titleNavy,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _formatPatientSince(),
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: _subtitleGrey,
                              ),
                            ),
                            const SizedBox(height: 24),
                    _ProfileSectionCard(
                      title: 'Informations personnelles',
                      icon: Icons.person_outline_rounded,
                      children: [
                        _ProfileLabeledField(
                          label: 'Nom complet',
                          icon: Icons.person_outline_rounded,
                          child: TextFormField(
                            controller: _nameController,
                            style: _fieldTextStyle(theme),
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                            validator: (v) =>
                                (v == null || v.trim().isEmpty) ? 'Nom requis' : null,
                          ),
                        ),
                        const SizedBox(height: 14),
                        _ProfileLabeledField(
                          label: 'Email',
                          icon: Icons.mail_outline_rounded,
                          child: TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            style: _fieldTextStyle(theme),
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                            validator: (v) {
                              final s = (v ?? '').trim();
                              if (s.isEmpty) return 'Email requis';
                              return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                      .hasMatch(s)
                                  ? null
                                  : 'Email invalide';
                            },
                          ),
                        ),
                        const SizedBox(height: 14),
                        _ProfileLabeledField(
                          label: 'Téléphone',
                          icon: Icons.phone_outlined,
                          child: TextFormField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            style: _fieldTextStyle(theme),
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Téléphone requis'
                                : null,
                          ),
                        ),
                        const SizedBox(height: 14),
                        _ProfileLabeledField(
                          label: 'Adresse',
                          icon: Icons.location_on_outlined,
                          child: TextFormField(
                            controller: _addressController,
                            style: _fieldTextStyle(theme),
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Adresse requise'
                                : null,
                          ),
                        ),
                        const SizedBox(height: 14),
                        _ProfileLabeledField(
                          label: 'Date de naissance',
                          icon: Icons.cake_outlined,
                          child: InkWell(
                            onTap: _pickBirthDate,
                            child: Text(
                              _formatBirthDate(),
                              style: _fieldTextStyle(theme).copyWith(
                                color: _birthDate == null
                                    ? _subtitleGrey
                                    : _titleNavy,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        _ProfileLabeledField(
                          label: 'Sexe',
                          icon: Icons.wc_rounded,
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _sex,
                              isExpanded: true,
                              hint: Text(
                                'Sélectionner',
                                style: _fieldTextStyle(theme).copyWith(
                                  color: _subtitleGrey,
                                ),
                              ),
                              icon: const Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: _iconBlue,
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'homme',
                                  child: Text('Homme'),
                                ),
                                DropdownMenuItem(
                                  value: 'femme',
                                  child: Text('Femme'),
                                ),
                              ],
                              onChanged: (v) => setState(() => _sex = v),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _ProfileSectionCard(
                      title: 'Informations de santé',
                      icon: Icons.health_and_safety_outlined,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _ProfileLabeledField(
                                label: 'Groupe sanguin',
                                icon: Icons.bloodtype_outlined,
                                compact: true,
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: _bloodGroup ?? '',
                                    isExpanded: true,
                                    icon: const Icon(
                                      Icons.keyboard_arrow_down_rounded,
                                      color: _iconBlue,
                                      size: 20,
                                    ),
                                    items: _bloodGroups
                                        .map(
                                          (g) => DropdownMenuItem(
                                            value: g,
                                            child: Text(
                                              g.isEmpty ? '—' : g,
                                              style: _fieldTextStyle(theme),
                                            ),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (v) => setState(
                                      () => _bloodGroup =
                                          (v == null || v.isEmpty) ? null : v,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _ProfileLabeledField(
                                label: 'Poids',
                                icon: Icons.monitor_weight_outlined,
                                compact: true,
                                child: TextFormField(
                                  controller: _weightController,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(
                                      RegExp(r'[0-9.,]'),
                                    ),
                                  ],
                                  style: _fieldTextStyle(theme),
                                  decoration: InputDecoration(
                                    border: InputBorder.none,
                                    isDense: true,
                                    contentPadding: EdgeInsets.zero,
                                    suffixText: 'kg',
                                    suffixStyle:
                                        _fieldTextStyle(theme).copyWith(
                                      color: _subtitleGrey,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: _ProfileLabeledField(
                                label: 'Taille',
                                icon: Icons.height_rounded,
                                compact: true,
                                child: TextFormField(
                                  controller: _heightController,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(
                                      RegExp(r'[0-9.,]'),
                                    ),
                                  ],
                                  style: _fieldTextStyle(theme),
                                  decoration: InputDecoration(
                                    border: InputBorder.none,
                                    isDense: true,
                                    contentPadding: EdgeInsets.zero,
                                    suffixText: 'cm',
                                    suffixStyle:
                                        _fieldTextStyle(theme).copyWith(
                                      color: _subtitleGrey,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _ProfileLabeledField(
                                label: 'Âge',
                                icon: Icons.calendar_today_outlined,
                                compact: true,
                                child: Text(
                                  age != null ? '$age ans' : '—',
                                  style: _fieldTextStyle(theme),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _ProfileLabeledField(
                          label: 'Allergies connues',
                          icon: Icons.medical_services_outlined,
                          child: TextFormField(
                            controller: _allergiesController,
                            maxLines: 3,
                            minLines: 2,
                            style: _fieldTextStyle(theme),
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                              hintText: 'Décrivez vos allergies connues…',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    _SaveGradientButton(
                      loading: _savingProfile,
                      onPressed: _savingProfile ? null : _saveProfile,
                    ),
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  TextStyle _fieldTextStyle(ThemeData theme) {
    return theme.textTheme.bodyMedium?.copyWith(
          color: _titleNavy,
          fontWeight: FontWeight.w500,
        ) ??
        const TextStyle(color: _titleNavy, fontWeight: FontWeight.w500);
  }
}

class _ProfileSectionCard extends StatelessWidget {
  const _ProfileSectionCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A2B48).withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                color: const Color(0xFF1A458B),
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: const Color(0xFF1A458B),
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ...children,
        ],
      ),
    );
  }
}

class _ProfileLabeledField extends StatelessWidget {
  const _ProfileLabeledField({
    required this.label,
    required this.icon,
    required this.child,
    this.compact = false,
  });

  static const Color labelColor = Color(0xFF1A458B);
  static const Color fieldBg = Color(0xFFF0F4F8);

  final String label;
  final IconData icon;
  final Widget child;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 8),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: _ProfileLabeledField.labelColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
          ),
        ),
        Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: 14,
            vertical: compact ? 12 : 14,
          ),
          decoration: BoxDecoration(
            color: _ProfileLabeledField.fieldBg,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(
                  icon,
                  color: const Color(0xFF1A458B),
                  size: compact ? 18 : 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: child),
            ],
          ),
        ),
      ],
    );
  }
}

class _SaveGradientButton extends StatelessWidget {
  const _SaveGradientButton({
    required this.onPressed,
    this.loading = false,
  });

  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: onPressed == null
            ? null
            : const LinearGradient(
                colors: [
                  Color(0xFFE8719A),
                  Color(0xFF3B5998),
                ],
              ),
        color: onPressed == null ? const Color(0xFFE5E7EB) : null,
        boxShadow: onPressed == null
            ? null
            : [
                BoxShadow(
                  color: HeadsAppColors.brandPrimary.withValues(alpha: 0.28),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            width: double.infinity,
            height: HeadsAppMetrics.buttonHeight,
            child: Center(
              child: loading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.save_outlined,
                          color: Colors.white,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Enregistrer les modifications',
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
